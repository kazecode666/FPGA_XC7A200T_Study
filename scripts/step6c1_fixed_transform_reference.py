#!/usr/bin/env python3
"""Bit-exact Step 6C1 fixed-point transform oracle and fixture generator."""

from __future__ import annotations

import argparse
import csv
import io
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STEP6A = ROOT / "coordination/reports/step6a_pi_foc_golden_vectors.csv"
ROM_PATH = ROOT / "motor_control_ip/foc/rom/sin_qw_4096x18.mem"
CSV_PATH = ROOT / "coordination/reports/step6c1_fixed_transform_vectors.csv"
VECTOR_DIR = ROOT / "motor_control_ip/foc/tb/vectors"

C_TWO_THIRDS = 43691
C_INV_SQRT3 = 37837
SIN_COS_ONE = 65536
F15 = 1 << 15
TWO_PI = 2.0 * math.pi


def round_shift_away(x: int, shift: int) -> int:
    if shift < 0:
        raise ValueError("shift must be nonnegative")
    if shift == 0:
        return x
    rounded_mag = (abs(x) + (1 << (shift - 1))) >> shift
    return -rounded_mag if x < 0 else rounded_mag


def divide_by_two_away(x: int) -> int:
    """One-bit magnitude division, nearest with ties away from zero."""
    return round_shift_away(x, 1)


def sat_signed(x: int, width: int) -> int:
    lo = -(1 << (width - 1))
    hi = (1 << (width - 1)) - 1
    return min(max(x, lo), hi)


def quantize_signed(value: float, fraction_bits: int, width: int) -> int:
    scaled = abs(value) * (1 << fraction_bits)
    raw = math.floor(scaled + 0.5)
    return sat_signed(-raw if value < 0 else raw, width)


def radians_to_u16(theta: float) -> int:
    return math.floor((theta % TWO_PI) * 65536.0 / TWO_PI + 0.5) & 0xFFFF


def clarke_raw(ia: int, ib: int, ic: int) -> tuple[int, int]:
    half_bc = divide_by_two_away(ib + ic)
    alpha_pre = ia - half_bc
    beta_pre = ib - ic
    return (
        sat_signed(round_shift_away(alpha_pre * C_TWO_THIRDS, 16), 25),
        sat_signed(round_shift_away(beta_pre * C_INV_SQRT3, 16), 25),
    )


def generate_rom() -> list[int]:
    return [
        math.floor(math.sin(k * (math.pi / 2.0) / 4096.0) * (1 << 16) + 0.5)
        for k in range(4096)
    ]


def sincos_raw(theta_u16: int, rom: list[int]) -> tuple[int, int]:
    theta_u16 &= 0xFFFF
    quadrant = (theta_u16 >> 14) & 3
    q = (theta_u16 >> 2) & 0xFFF
    sine_mag = rom[q]
    cosine_mag = SIN_COS_ONE if q == 0 else rom[4096 - q]
    if quadrant == 0:
        return sine_mag, cosine_mag
    if quadrant == 1:
        return cosine_mag, -sine_mag
    if quadrant == 2:
        return -sine_mag, -cosine_mag
    return -cosine_mag, sine_mag


def park_raw(alpha: int, beta: int, sine: int, cosine: int) -> tuple[int, int]:
    # Python integers preserve the required 43-bit products and >=44-bit sums.
    d_acc = alpha * cosine + beta * sine
    q_acc = -alpha * sine + beta * cosine
    return (
        sat_signed(round_shift_away(d_acc, 16), 25),
        sat_signed(round_shift_away(q_acc, 16), 25),
    )


def inv_park_raw(d_axis: int, q_axis: int, sine: int, cosine: int) -> tuple[int, int]:
    alpha_acc = d_axis * cosine - q_axis * sine
    beta_acc = d_axis * sine + q_axis * cosine
    return (
        sat_signed(round_shift_away(alpha_acc, 16), 25),
        sat_signed(round_shift_away(beta_acc, 16), 25),
    )


def load_step6a() -> list[dict[str, str]]:
    with STEP6A.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 160:
        raise AssertionError(f"expected 160 Step 6A rows, found {len(rows)}")
    return rows


def render_rom(values: list[int]) -> str:
    return "".join(f"{value & 0x3FFFF:05X}\n" for value in values)


CSV_FIELDS = [
    "row_index", "parameter_profile", "case_id", "ia_raw", "ib_raw", "ic_raw",
    "theta_u16", "i_alpha_raw", "i_beta_raw", "sin_raw", "cos_raw", "id_raw",
    "iq_raw", "ud_lim_raw", "uq_lim_raw", "v_alpha_raw", "v_beta_raw",
    "ia_A", "ib_A", "ic_A", "theta_rad", "i_alpha_A", "i_beta_A", "id_A",
    "iq_A", "v_alpha_V", "v_beta_V", "step6a_i_alpha", "step6a_i_beta",
    "step6a_id", "step6a_iq", "step6a_v_alpha", "step6a_v_beta",
]


def comparison_rows(step6a: list[dict[str, str]], rom: list[int]) -> list[dict[str, object]]:
    output: list[dict[str, object]] = []
    for index, row in enumerate(step6a):
        ia = quantize_signed(float(row["ia"]), 15, 24)
        ib = quantize_signed(float(row["ib"]), 15, 24)
        ic = quantize_signed(float(row["ic"]), 15, 24)
        theta = radians_to_u16(float(row["theta_e"]))
        alpha, beta = clarke_raw(ia, ib, ic)
        sine, cosine = sincos_raw(theta, rom)
        d_axis, q_axis = park_raw(alpha, beta, sine, cosine)
        ud = quantize_signed(float(row["ud_lim"]), 15, 25)
        uq = quantize_signed(float(row["uq_lim"]), 15, 25)
        v_alpha, v_beta = inv_park_raw(ud, uq, sine, cosine)
        output.append({
            "row_index": index, "parameter_profile": row["parameter_profile"],
            "case_id": row["case_id"], "ia_raw": ia, "ib_raw": ib, "ic_raw": ic,
            "theta_u16": theta, "i_alpha_raw": alpha, "i_beta_raw": beta,
            "sin_raw": sine, "cos_raw": cosine, "id_raw": d_axis, "iq_raw": q_axis,
            "ud_lim_raw": ud, "uq_lim_raw": uq, "v_alpha_raw": v_alpha,
            "v_beta_raw": v_beta, "ia_A": f"{ia/F15:.12g}",
            "ib_A": f"{ib/F15:.12g}", "ic_A": f"{ic/F15:.12g}",
            "theta_rad": f"{float(row['theta_e']):.12g}",
            "i_alpha_A": f"{alpha/F15:.12g}", "i_beta_A": f"{beta/F15:.12g}",
            "id_A": f"{d_axis/F15:.12g}", "iq_A": f"{q_axis/F15:.12g}",
            "v_alpha_V": f"{v_alpha/F15:.12g}", "v_beta_V": f"{v_beta/F15:.12g}",
            "step6a_i_alpha": row["i_alpha"], "step6a_i_beta": row["i_beta"],
            "step6a_id": row["id"], "step6a_iq": row["iq"],
            "step6a_v_alpha": row["v_alpha"], "step6a_v_beta": row["v_beta"],
        })
    return output


def render_csv(rows: list[dict[str, object]]) -> str:
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=CSV_FIELDS, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue()


def fixture_lines(step6a: list[dict[str, str]], rom: list[int]) -> dict[Path, str]:
    outputs: dict[Path, str] = {}

    clarke_cases = [(0, 0, 0), (F15, F15, F15), (F15, -F15//2, -F15//2),
                    ((1<<23)-1, -(1<<23), (1<<23)-1), (-(1<<23), (1<<23)-1, -(1<<23))]
    clarke_cases += [(quantize_signed(float(r["ia"]),15,24), quantize_signed(float(r["ib"]),15,24),
                      quantize_signed(float(r["ic"]),15,24)) for r in step6a]
    lines = ["# ia_raw ib_raw ic_raw i_alpha_raw i_beta_raw"]
    for ia, ib, ic in clarke_cases:
        alpha, beta = clarke_raw(ia, ib, ic)
        lines.append(f"{ia} {ib} {ic} {alpha} {beta}")
    outputs[VECTOR_DIR / "clarke_vectors.txt"] = "\n".join(lines) + "\n"

    lines = ["# theta_u16 sin_raw cos_raw"]
    for theta in range(65536):
        sine, cosine = sincos_raw(theta, rom)
        lines.append(f"{theta} {sine} {cosine}")
    outputs[VECTOR_DIR / "sincos_all_phases.txt"] = "\n".join(lines) + "\n"

    rng = random.Random(0x6C1)
    park_cases = [(0,0,0), (F15,0,0), (0,F15,0x4000), ((1<<24)-1,(1<<24)-1,0x2000),
                  (-(1<<24),-(1<<24),0x2000)]
    park_cases += [(rng.randint(-(1<<24),(1<<24)-1), rng.randint(-(1<<24),(1<<24)-1), rng.randrange(65536))
                   for _ in range(128)]
    lines = ["# i_alpha_raw i_beta_raw theta_u16 sin_raw cos_raw id_raw iq_raw"]
    inv_lines = ["# d_raw q_raw theta_u16 sin_raw cos_raw alpha_raw beta_raw"]
    for alpha, beta, theta in park_cases:
        sine, cosine = sincos_raw(theta, rom)
        d_axis, q_axis = park_raw(alpha, beta, sine, cosine)
        lines.append(f"{alpha} {beta} {theta} {sine} {cosine} {d_axis} {q_axis}")
        back_alpha, back_beta = inv_park_raw(d_axis, q_axis, sine, cosine)
        inv_lines.append(f"{d_axis} {q_axis} {theta} {sine} {cosine} {back_alpha} {back_beta}")
    # Standalone arithmetic fixtures: theta is descriptive only; explicit coefficients drive the DUT.
    # These hit +/- half-LSB, one below/above the tie, and both 25-bit clipping rails.
    for alpha, beta, sine, cosine in [
        (1, 0, 0, 32767), (1, 0, 0, 32768), (1, 0, 0, 32769),
        (-1, 0, 0, 32767), (-1, 0, 0, 32768), (-1, 0, 0, 32769),
        ((1<<24)-1, (1<<24)-1, 46341, 46341),
        (-(1<<24), -(1<<24), 46341, 46341),
    ]:
        d_axis, q_axis = park_raw(alpha, beta, sine, cosine)
        lines.append(f"{alpha} {beta} 0 {sine} {cosine} {d_axis} {q_axis}")
    # Independent inverse-Park saturation stimuli.
    for d_axis, q_axis, theta in [((1<<24)-1,(1<<24)-1,0x2000), (-(1<<24),-(1<<24),0x2000)]:
        sine, cosine = sincos_raw(theta, rom)
        alpha, beta = inv_park_raw(d_axis, q_axis, sine, cosine)
        inv_lines.append(f"{d_axis} {q_axis} {theta} {sine} {cosine} {alpha} {beta}")
    outputs[VECTOR_DIR / "park_vectors.txt"] = "\n".join(lines) + "\n"
    outputs[VECTOR_DIR / "inv_park_vectors.txt"] = "\n".join(inv_lines) + "\n"

    integration = []
    for index, row in enumerate(step6a):
        integration.append((index, quantize_signed(float(row["ia"]),15,24),
                            quantize_signed(float(row["ib"]),15,24),
                            quantize_signed(float(row["ic"]),15,24), radians_to_u16(float(row["theta_e"]))))
    for n in range(96):
        integration.append((160+n, rng.randint(-(1<<23),(1<<23)-1), rng.randint(-(1<<23),(1<<23)-1),
                            rng.randint(-(1<<23),(1<<23)-1), (n*977+3)&0xFFFF))
    lines = ["# transaction_id ia_raw ib_raw ic_raw theta_u16 i_alpha_raw i_beta_raw sin_raw cos_raw id_raw iq_raw"]
    for txn, ia, ib, ic, theta in integration:
        alpha, beta = clarke_raw(ia, ib, ic); sine, cosine = sincos_raw(theta, rom)
        d_axis, q_axis = park_raw(alpha, beta, sine, cosine)
        lines.append(f"{txn} {ia} {ib} {ic} {theta} {alpha} {beta} {sine} {cosine} {d_axis} {q_axis}")
    outputs[VECTOR_DIR / "current_transform_transactions.txt"] = "\n".join(lines) + "\n"
    return outputs


def self_checks(rom: list[int]) -> dict[str, float]:
    assert len(rom) == 4096 and rom[0] == 0
    assert 0 < rom[1] < rom[-1] <= 65536
    assert all(a <= b for a, b in zip(rom, rom[1:]))
    # Exact multiples, half-LSB ties, one either side of a tie, and signed-44 minimum.
    for n in (-123, -1, 0, 1, 123):
        assert round_shift_away(n << 16, 16) == n
    assert round_shift_away(32768,16)==1 and round_shift_away(-32768,16)==-1
    assert round_shift_away(32767,16)==0 and round_shift_away(-32767,16)==0
    assert round_shift_away(32769,16)==1 and round_shift_away(-32769,16)==-1
    assert round_shift_away(-(1<<43),16) == -(1<<27)
    assert divide_by_two_away(1)==1 and divide_by_two_away(-1)==-1
    assert sat_signed(1<<30,25)==(1<<24)-1 and sat_signed(-(1<<30),25)==-(1<<24)
    axes = {0:(0,65536), 0x4000:(65536,0), 0x8000:(0,-65536), 0xC000:(-65536,0)}
    for theta, expected in axes.items(): assert sincos_raw(theta,rom)==expected
    alpha, beta = clarke_raw(F15, -F15//2, -F15//2)
    assert (alpha,beta)==(F15,0)
    assert park_raw((1<<24)-1,(1<<24)-1,46341,46341)[0] == (1<<24)-1
    assert park_raw(-(1<<24),-(1<<24),46341,46341)[0] == -(1<<24)
    assert inv_park_raw((1<<24)-1,-(1<<24),46341,46341)[0] == (1<<24)-1
    max_trig_error = 0.0
    for theta in range(65536):
        sine, cosine = sincos_raw(theta,rom)
        angle = theta*TWO_PI/65536.0
        max_trig_error = max(max_trig_error, abs(sine/65536.0-math.sin(angle)),
                             abs(cosine/65536.0-math.cos(angle)))
    assert max_trig_error <= 5e-4
    return {"max_trig_ideal_error": max_trig_error}


def metrics(rows: list[dict[str, object]], rom: list[int]) -> dict[str, float]:
    result: dict[str,float] = {}
    for fixed, reference in [("i_alpha_A","step6a_i_alpha"),("i_beta_A","step6a_i_beta"),
                             ("id_A","step6a_id"),("iq_A","step6a_iq"),
                             ("v_alpha_V","step6a_v_alpha"),("v_beta_V","step6a_v_beta")]:
        result[f"max_abs_{fixed}_vs_step6a"] = max(abs(float(r[fixed])-float(r[reference])) for r in rows)
    ideal_errors={name:0.0 for name in ("i_alpha","i_beta","id","iq","v_alpha","v_beta")}
    for row in rows:
        ia=float(row["ia_A"]); ib=float(row["ib_A"]); ic=float(row["ic_A"])
        theta=float(row["theta_rad"]); sine=math.sin(theta); cosine=math.cos(theta)
        ideal_alpha=(2.0/3.0)*(ia-0.5*ib-0.5*ic); ideal_beta=(ib-ic)/math.sqrt(3.0)
        ideal_d=ideal_alpha*cosine+ideal_beta*sine; ideal_q=-ideal_alpha*sine+ideal_beta*cosine
        ud=int(row["ud_lim_raw"])/F15; uq=int(row["uq_lim_raw"])/F15
        ideal_va=ud*cosine-uq*sine; ideal_vb=ud*sine+uq*cosine
        actual={"i_alpha":float(row["i_alpha_A"]),"i_beta":float(row["i_beta_A"]),
                "id":float(row["id_A"]),"iq":float(row["iq_A"]),
                "v_alpha":float(row["v_alpha_V"]),"v_beta":float(row["v_beta_V"])}
        for name,ideal in (("i_alpha",ideal_alpha),("i_beta",ideal_beta),("id",ideal_d),
                           ("iq",ideal_q),("v_alpha",ideal_va),("v_beta",ideal_vb)):
            ideal_errors[name]=max(ideal_errors[name],abs(actual[name]-ideal))
    for name,value in ideal_errors.items(): result[f"max_abs_{name}_vs_ideal"] = value
    rng = random.Random(0xC1A0)
    max_roundtrip = 0
    used = 0
    for _ in range(1000):
        alpha = rng.randint(-8*F15,8*F15); beta = rng.randint(-8*F15,8*F15); theta=rng.randrange(65536)
        sine,cosine=sincos_raw(theta,rom); d_axis,q_axis=park_raw(alpha,beta,sine,cosine)
        back_alpha,back_beta=inv_park_raw(d_axis,q_axis,sine,cosine)
        # This deliberately low-amplitude domain cannot saturate 25-bit outputs.
        assert max(abs(d_axis),abs(q_axis),abs(back_alpha),abs(back_beta)) < (1<<24)
        max_roundtrip=max(max_roundtrip,abs(back_alpha-alpha),abs(back_beta-beta)); used+=1
    result["unsaturated_roundtrip_max_raw_lsb"] = float(max_roundtrip)
    result["unsaturated_roundtrip_max_physical"] = max_roundtrip/F15
    result["unsaturated_roundtrip_count"] = float(used)
    return result


def expected_files() -> tuple[dict[Path,str], dict[str,float]]:
    rom=generate_rom(); checks=self_checks(rom); step6a=load_step6a(); rows=comparison_rows(step6a,rom)
    files={ROM_PATH:render_rom(rom), CSV_PATH:render_csv(rows)}
    files.update(fixture_lines(step6a,rom)); checks.update(metrics(rows,rom))
    return files,checks


def main() -> int:
    parser=argparse.ArgumentParser(); group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--generate",action="store_true"); group.add_argument("--check",action="store_true")
    args=parser.parse_args(); files,summary=expected_files()
    if args.generate:
        for path,content in files.items(): path.parent.mkdir(parents=True,exist_ok=True); path.write_text(content,encoding="ascii",newline="")
    else:
        mismatches=[]
        for path,content in files.items():
            if not path.exists() or path.read_text(encoding="ascii") != content: mismatches.append(str(path.relative_to(ROOT)))
        if mismatches:
            print("Generated-file mismatch: " + ", ".join(mismatches),file=sys.stderr); return 1
    print(f"PASS: {len(generate_rom())} ROM entries; 65536 phases; 160 Step 6A rows")
    for key in sorted(summary): print(f"{key}={summary[key]:.12g}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
