"""Independent integer oracle and compact fixtures for Step 6C3 Sector SVPWM.

The oracle uses Python arbitrary-precision arithmetic and ordinary divmod; it
does not reproduce the RTL divider state machine.  Decimal calculations are a
separate numerical check of the selected fixed-point algorithm.
"""

import argparse
import csv
from collections import Counter
from decimal import Decimal, ROUND_HALF_UP, localcontext
import io
import json
from pathlib import Path
import random
import sys


if sys.flags.optimize:
    raise SystemExit("Step 6C3 rejects optimized Python: run without -O/-OO")


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "coordination/reports/step6a_pi_foc_golden_vectors.csv"
COMPARISON = ROOT / "coordination/reports/step6c3_svpwm_fixed_vectors.csv"
VECTOR_DIR = ROOT / "motor_control_ip/foc/tb/vectors/step6c3"
ONE_F32 = 1 << 32
SEED = 0x6C32026
SEEDED_COUNT = 768
ALLOWED_SECTOR_EXCEPTIONS = {
    ("real_commissioning", "edge_1_1.732"),
    ("real_commissioning", "edge_1_-1.732"),
    ("MIL_PI_override", "edge_1_1.732"),
    ("MIL_PI_override", "edge_1_-1.732"),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def fits_signed(value, width):
    return -(1 << (width - 1)) <= value < (1 << (width - 1))


def round_shift_away(x, shift):
    require(type(x) is int and type(shift) is int, "round_shift_away needs integers")
    require(shift >= 0, "shift must be nonnegative")
    if shift == 0:
        return x
    magnitude = (abs(x) + (1 << (shift - 1))) >> shift
    return -magnitude if x < 0 else magnitude


def round_div_signed(num, den, frac_bits=32):
    require(type(num) is int and type(den) is int, "round_div_signed needs integers")
    require(type(frac_bits) is int and frac_bits >= 0, "invalid fractional width")
    require(den > 0, "denominator must be positive")
    quotient, remainder = divmod(abs(num) << frac_bits, den)
    if 2 * remainder >= den:
        quotient += 1
    return -quotient if num < 0 else quotient


def sector_xyz(A, B):
    require(type(A) is int and type(B) is int, "A and B must be integers")
    cmp0 = B
    cmp1 = 433 * A - 250 * B
    cmp2 = -433 * A - 250 * B
    b0, b1, b2 = int(cmp0 > 0), int(cmp1 >= 0), int(cmp2 > 0)
    sector = b0 + 2 * b1 + 4 * b2
    require(1 <= sector <= 6, f"illegal sector {sector}")
    X = 17321 * B
    Y = 8660 * B + 15000 * A
    Z = 8660 * B - 15000 * A
    require(all(fits_signed(value, 40) for value in (X, Y, Z)), "XYZ does not fit S40")
    a_num, b_num = (
        (Z, Y),
        (Y, -X),
        (-Z, X),
        (-X, Z),
        (X, -Y),
        (-Y, -Z),
    )[sector - 1]
    return {
        "cmp0": cmp0,
        "cmp1": cmp1,
        "cmp2": cmp2,
        "b0": b0,
        "b1": b1,
        "b2": b2,
        "sector": sector,
        "X": X,
        "Y": Y,
        "Z": Z,
        "a_num": a_num,
        "b_num": b_num,
    }


def dwell_from_ab(a_num, b_num, vdc_raw):
    require(all(type(value) is int for value in (a_num, b_num, vdc_raw)), "dwell inputs must be integers")
    require(vdc_raw > 0, "vdc_raw must be positive")
    base = 10000 * vdc_raw
    sum_num = a_num + b_num
    overmodulated = int(sum_num > base)
    denominator = sum_num if overmodulated else base
    require(denominator > 0, "selected denominator must be positive")
    return {
        "base": base,
        "sum_num": sum_num,
        "denominator": denominator,
        "overmodulated": overmodulated,
        "t1": round_div_signed(a_num, denominator),
        "t2": round_div_signed(b_num, denominator),
    }


def duty_from_sector(sector, t1, t2):
    require(type(sector) is int and 1 <= sector <= 6, "sector must be 1..6")
    require(type(t1) is int and type(t2) is int, "t1 and t2 must be integers")
    L = round_div_signed(ONE_F32 - t1 - t2, 2, frac_bits=0)
    M = round_div_signed(ONE_F32 + t1 - t2, 2, frac_bits=0)
    H = round_div_signed(ONE_F32 + t1 + t2, 2, frac_bits=0)
    u, v, w = (
        (M, L, H),
        (L, H, M),
        (L, M, H),
        (H, M, L),
        (H, L, M),
        (M, H, L),
    )[sector - 1]
    return {
        "L": L,
        "M": M,
        "H": H,
        "duty_u": round_shift_away(u, 8),
        "duty_v": round_shift_away(v, 8),
        "duty_w": round_shift_away(w, 8),
    }


def _error_result(error_code):
    names = (
        "cmp0 cmp1 cmp2 b0 b1 b2 sector X Y Z a_num b_num base sum_num "
        "denominator overmodulated t1 t2 L M H duty_u duty_v duty_w"
    ).split()
    result = {name: 0 for name in names}
    result["error_code"] = error_code
    return result


def svpwm_step(A, B, vdc_raw):
    require(all(type(value) is int for value in (A, B, vdc_raw)), "SVPWM inputs must be integers")
    require(all(fits_signed(value, 25) for value in (A, B, vdc_raw)), "input does not fit S25")
    if vdc_raw <= 0:
        return _error_result(1)
    try:
        xyz = sector_xyz(A, B)
        dwell = dwell_from_ab(xyz["a_num"], xyz["b_num"], vdc_raw)
        duty = duty_from_sector(xyz["sector"], dwell["t1"], dwell["t2"])
    except ValueError:
        return _error_result(2)
    if not all(fits_signed(dwell[name], 34) for name in ("t1", "t2")):
        return _error_result(2)
    if not all(fits_signed(duty[name], 34) for name in ("L", "M", "H")):
        return _error_result(2)
    if not all(fits_signed(duty[name], 26) for name in ("duty_u", "duty_v", "duty_w")):
        return _error_result(2)
    return {**xyz, **dwell, **duty, "error_code": 0}


def quantize_f15(text):
    with localcontext() as ctx:
        ctx.prec = 90
        value = Decimal(str(text))
        require(value.is_finite(), "nonfinite source input")
        return int((value * (1 << 15)).to_integral_value(rounding=ROUND_HALF_UP))


def decimal_reference(A, B, vdc_raw, sector):
    with localcontext() as ctx:
        ctx.prec = 90
        a, b, bus = Decimal(A), Decimal(B), Decimal(vdc_raw)
        x = Decimal("1.7321") * b / bus
        y = (Decimal("0.866") * b + Decimal("1.5") * a) / bus
        z = (Decimal("0.866") * b - Decimal("1.5") * a) / bus
        t1, t2 = (
            (z, y),
            (y, -x),
            (-z, x),
            (-x, z),
            (x, -y),
            (-y, -z),
        )[sector - 1]
        if t1 + t2 > 1:
            denominator = t1 + t2
            t1, t2 = t1 / denominator, t2 / denominator
        low = (Decimal(1) - t1 - t2) / 2
        mid = (Decimal(1) + t1 - t2) / 2
        high = (Decimal(1) + t1 + t2) / 2
        u, v, w = (
            (mid, low, high),
            (low, high, mid),
            (low, mid, high),
            (high, mid, low),
            (high, low, mid),
            (mid, high, low),
        )[sector - 1]
        return {"t1": t1, "t2": t2, "duty_u": u, "duty_v": v, "duty_w": w}


def decimal_errors(cases):
    maxima = {name: Decimal(0) for name in ("t1", "t2", "duty_u", "duty_v", "duty_w")}
    for _, _, A, B, vdc_raw in cases:
        result = svpwm_step(A, B, vdc_raw)
        if result["error_code"]:
            continue
        ideal = decimal_reference(A, B, vdc_raw, result["sector"])
        for name in ("t1", "t2"):
            error = abs(Decimal(result[name]) / ONE_F32 - ideal[name])
            maxima[name] = max(maxima[name], error)
            require(error <= Decimal(1) / ONE_F32, f"Decimal {name} gate failed")
        for name in ("duty_u", "duty_v", "duty_w"):
            error = abs(Decimal(result[name]) / (1 << 24) - ideal[name])
            maxima[name] = max(maxima[name], error)
            require(error <= Decimal(2) / (1 << 24), f"Decimal {name} gate failed")
    return maxima


TAGS = {
    0: "seeded",
    1: "zero",
    2: "sector_1_interior",
    3: "sector_2_interior",
    4: "sector_3_interior",
    5: "sector_4_interior",
    6: "sector_5_interior",
    7: "sector_6_interior",
    8: "cmp1_minus_1",
    9: "cmp1_equal_0",
    10: "cmp1_plus_1",
    11: "sum_base_minus_1",
    12: "sum_base_equal",
    13: "sum_base_plus_1",
    14: "clear_overmodulation",
    15: "negative_unclamped",
    16: "invalid_vdc_zero",
    17: "invalid_vdc_negative",
    18: "cmp1_plan_plus_250",
    19: "cmp1_plan_minus_250",
    20: "cmp2_minus_1",
    21: "cmp2_equal_0",
    22: "cmp2_plus_1",
}


def directed_cases():
    bus = 48 << 15
    return [
        (1, 1, 0, 0, bus),
        (2, 2, 0, 32768, bus),
        (3, 3, 32768, -32768, bus),
        (4, 4, 32768, 32768, bus),
        (5, 5, -32768, -32768, bus),
        (6, 6, -32768, 32768, bus),
        (7, 7, 0, -32768, bus),
        (8, 8, 24903, 43132, bus),
        (9, 9, 25000, 43300, bus),
        (10, 10, 25097, 43468, bus),
        (11, 11, 2345, 4059, 7033),
        (12, 12, 2, 0, 3),
        (13, 13, 544, 941, 1631),
        (14, 14, 40 << 15, 0, bus),
        (15, 15, 24903, 43132, 1),
        (16, 16, 123, -456, 0),
        (17, 17, 123, -456, -1),
        (18, 18, 25000, 43299, bus),
        (19, 19, 25000, 43301, bus),
        (20, 20, -153, 265, bus),
        (21, 21, -250, 433, bus),
        (22, 22, -97, 168, bus),
    ]


def all_cases():
    cases = directed_cases()
    rng = random.Random(SEED)
    for index in range(SEEDED_COUNT):
        A = rng.randint(-(40 << 15), 40 << 15)
        B = rng.randint(-(40 << 15), 40 << 15)
        vdc_raw = rng.randint(24 << 15, 72 << 15)
        cases.append((0x1000 + index, 0, A, B, vdc_raw))
    require(all(svpwm_step(A, B, bus)["error_code"] == 0 for _, _, A, B, bus in cases if bus > 0),
            "valid fixture case produced an error")
    return cases


SECTOR_COLUMNS = [
    ("id", 32, False), ("tag_id", 16, False),
    ("v_alpha", 25, True), ("v_beta", 25, True),
    ("cmp0", 25, True), ("cmp1", 36, True), ("cmp2", 36, True),
    ("b0", 1, False), ("b1", 1, False), ("b2", 1, False),
    ("sector", 3, False), ("X", 40, True), ("Y", 40, True),
    ("Z", 40, True), ("a_num", 40, True), ("b_num", 40, True),
]

SVPWM_COLUMNS = [
    ("id", 32, False), ("tag_id", 16, False),
    ("v_alpha", 25, True), ("v_beta", 25, True), ("vdc", 25, True),
    ("sector", 3, False), ("overmodulated", 1, False), ("error_code", 2, False),
    ("a_num", 40, True), ("b_num", 40, True), ("sum_num", 41, True),
    ("base", 39, True), ("denominator", 41, True),
    ("t1", 34, True), ("t2", 34, True),
    ("L", 34, True), ("M", 34, True), ("H", 34, True),
    ("duty_u", 26, True), ("duty_v", 26, True), ("duty_w", 26, True),
]


def encode(value, width, signed):
    require(type(value) is int, "fixture value must be an integer")
    require(fits_signed(value, width) if signed else 0 <= value < (1 << width),
            f"value {value} does not fit {'S' if signed else 'U'}{width}")
    if value < 0:
        value += 1 << width
    return f"{value:0{(width + 3) // 4}x}"


def render_rows(columns, rows):
    lines = ["# " + " ".join(name for name, _, _ in columns)]
    for row in rows:
        lines.append(" ".join(encode(row[name], width, signed) for name, width, signed in columns))
    return "\n".join(lines) + "\n"


def fixture_texts(cases):
    sector_rows, svpwm_rows = [], []
    for case_id, tag_id, A, B, vdc_raw in cases:
        xyz = sector_xyz(A, B)
        sector_rows.append({"id": case_id, "tag_id": tag_id, "v_alpha": A, "v_beta": B, **xyz})
        result = svpwm_step(A, B, vdc_raw)
        svpwm_rows.append({"id": case_id, "tag_id": tag_id, "v_alpha": A, "v_beta": B,
                            "vdc": vdc_raw, **result})
    return {
        "sector_xyz_vectors.txt": render_rows(SECTOR_COLUMNS, sector_rows),
        "svpwm_vectors.txt": render_rows(SVPWM_COLUMNS, svpwm_rows),
    }


def compare_step6a():
    rows = list(csv.DictReader(SOURCE.open(encoding="utf-8-sig")))
    require(len(rows) == 160, f"expected 160 Step 6A rows, found {len(rows)}")
    require(Counter(row["parameter_profile"] for row in rows) == {
        "real_commissioning": 80, "MIL_PI_override": 80
    }, "expected 80 rows per parameter_profile")
    fields = [
        "row_index", "parameter_profile", "case_id", "v_alpha_raw", "v_beta_raw", "vdc_raw",
        "source_sector", "oracle_sector", "sector_match", "sector_exception",
        "source_t1_norm", "oracle_t1_norm", "t1_error",
        "source_t2_norm", "oracle_t2_norm", "t2_error",
        "source_duty_u_norm", "oracle_duty_u_norm", "duty_u_error",
        "source_duty_v_norm", "oracle_duty_v_norm", "duty_v_error",
        "source_duty_w_norm", "oracle_duty_w_norm", "duty_w_error",
    ]
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    maxima = {name: Decimal(0) for name in ("t1", "t2", "duty_u", "duty_v", "duty_w")}
    mismatches = set()
    with localcontext() as ctx:
        ctx.prec = 90
        for index, row in enumerate(rows):
            A, B, bus = (quantize_f15(row[name]) for name in ("v_alpha", "v_beta", "vdc"))
            result = svpwm_step(A, B, bus)
            require(result["error_code"] == 0, f"Step 6A replay error at row {index}")
            key = (row["parameter_profile"], row["case_id"])
            source_sector = int(Decimal(row["sector"]))
            sector_match = source_sector == result["sector"]
            if not sector_match:
                mismatches.add(key)
                require(key in ALLOWED_SECTOR_EXCEPTIONS, f"unexpected sector mismatch {key}")
            source_values = {
                "t1": Decimal(row["t1"]) / Decimal("0.0001"),
                "t2": Decimal(row["t2"]) / Decimal("0.0001"),
                "duty_u": Decimal(row["duty_a"]) / Decimal(10000),
                "duty_v": Decimal(row["duty_b"]) / Decimal(10000),
                "duty_w": Decimal(row["duty_c"]) / Decimal(10000),
            }
            oracle_values = {
                "t1": Decimal(result["t1"]) / ONE_F32,
                "t2": Decimal(result["t2"]) / ONE_F32,
                "duty_u": Decimal(result["duty_u"]) / (1 << 24),
                "duty_v": Decimal(result["duty_v"]) / (1 << 24),
                "duty_w": Decimal(result["duty_w"]) / (1 << 24),
            }
            errors = {name: abs(oracle_values[name] - source_values[name]) for name in maxima}
            for name, error in errors.items():
                maxima[name] = max(maxima[name], error)
                require(error <= Decimal("0.00005"), f"Step 6A {name} gate failed at {key}")
            writer.writerow({
                "row_index": index,
                "parameter_profile": row["parameter_profile"],
                "case_id": row["case_id"],
                "v_alpha_raw": A, "v_beta_raw": B, "vdc_raw": bus,
                "source_sector": source_sector, "oracle_sector": result["sector"],
                "sector_match": int(sector_match), "sector_exception": int(key in ALLOWED_SECTOR_EXCEPTIONS),
                **{f"source_{name}_norm": str(source_values[name]) for name in maxima},
                **{f"oracle_{name}_norm": str(oracle_values[name]) for name in maxima},
                **{f"{name}_error": str(errors[name]) for name in maxima},
            })
    require(mismatches == ALLOWED_SECTOR_EXCEPTIONS,
            f"sector mismatch set differs: expected {sorted(ALLOWED_SECTOR_EXCEPTIONS)}, got {sorted(mismatches)}")
    return output.getvalue(), maxima, mismatches


def column_manifest(columns):
    return [{"name": name, "width": width, "signed": signed} for name, width, signed in columns]


def build_outputs():
    cases = all_cases()
    fixtures = fixture_texts(cases)
    comparison, replay_maxima, mismatches = compare_step6a()
    precision_maxima = decimal_errors(cases)
    manifest = {
        "version": 1,
        "encoding": "fixed-width lowercase hexadecimal; exact-width two's complement for signed fields; whitespace-separated; one # header; no blank rows",
        "input_format": "v_alpha/v_beta/vdc signed S25/F15",
        "dwell_format": "t1/t2/L/M/H signed S34/F32",
        "duty_format": "duty_u/v/w signed S26/F24; unclamped",
        "master_seed": SEED,
        "master_seed_hex": hex(SEED),
        "seeded_full_top_cases": SEEDED_COUNT,
        "directed_full_top_cases": len(directed_cases()),
        "total_full_top_cases": len(cases),
        "tags": {str(key): value for key, value in TAGS.items()},
        "fixtures": {
            "sector_xyz_vectors.txt": {"rows": len(cases), "columns": column_manifest(SECTOR_COLUMNS)},
            "svpwm_vectors.txt": {"rows": len(cases), "columns": column_manifest(SVPWM_COLUMNS)},
        },
        "step6a_replay": {
            "source": str(SOURCE.relative_to(ROOT)).replace("\\", "/"),
            "rows": 160,
            "rows_per_parameter_profile": 80,
            "allowed_and_observed_sector_exceptions": [
                {"parameter_profile": profile, "case_id": case_id}
                for profile, case_id in sorted(mismatches)
            ],
            "normalized_error_limit": "0.00005",
            "maxima": {name: str(value) for name, value in replay_maxima.items()},
        },
        "decimal_check": {
            "t1_t2_limit": str(Decimal(1) / ONE_F32),
            "duty_limit": str(Decimal(2) / (1 << 24)),
            "maxima": {name: str(value) for name, value in precision_maxima.items()},
        },
    }
    fixtures["manifest.json"] = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    return fixtures, comparison, manifest


def generate():
    fixtures, comparison, manifest = build_outputs()
    VECTOR_DIR.mkdir(parents=True, exist_ok=True)
    for name, text in fixtures.items():
        (VECTOR_DIR / name).write_text(text, encoding="utf-8", newline="")
    COMPARISON.parent.mkdir(parents=True, exist_ok=True)
    COMPARISON.write_text(comparison, encoding="utf-8", newline="")
    return manifest


def check():
    fixtures, comparison, manifest = build_outputs()
    for name, expected in fixtures.items():
        path = VECTOR_DIR / name
        require(path.is_file(), f"missing generated fixture {path}")
        require(path.read_text(encoding="utf-8") == expected, f"stale generated fixture {path}")
    require(COMPARISON.is_file(), f"missing generated comparison {COMPARISON}")
    require(COMPARISON.read_text(encoding="utf-8") == comparison, f"stale generated comparison {COMPARISON}")
    return manifest


def print_summary(action, manifest):
    replay = manifest["step6a_replay"]
    precision = manifest["decimal_check"]
    comparison_rows = list(csv.DictReader(COMPARISON.open(encoding="utf-8")))
    sector_exceptions = [row for row in comparison_rows if row["sector_match"] == "0"]
    observed_exceptions = {
        (row["parameter_profile"], row["case_id"])
        for row in sector_exceptions
    }
    require(len(sector_exceptions) == len(ALLOWED_SECTOR_EXCEPTIONS),
            f"expected four boundary sector rows, found {len(sector_exceptions)}")
    require(observed_exceptions == ALLOWED_SECTOR_EXCEPTIONS,
            "printed boundary sector rows differ from the allowed mismatch set")
    print(f"STEP6C3_REFERENCE_{action.upper()}_PASS")
    print(f"fixtures: {manifest['directed_full_top_cases']} directed + {manifest['seeded_full_top_cases']} seeded = {manifest['total_full_top_cases']}")
    print(f"Step 6A: {replay['rows']} rows, 80/profile, 4 allowed/observed sector exceptions")
    for row in sector_exceptions:
        print(
            "Step 6A boundary sector mismatch: "
            f"row={row['row_index']} profile={row['parameter_profile']} "
            f"case={row['case_id']} v_alpha_raw={row['v_alpha_raw']} "
            f"v_beta_raw={row['v_beta_raw']} source_sector={row['source_sector']} "
            f"oracle_sector={row['oracle_sector']}"
        )
    print("Step 6A normalized maxima: " + ", ".join(f"{key}={value}" for key, value in replay["maxima"].items()))
    print("Decimal maxima: " + ", ".join(f"{key}={value}" for key, value in precision["maxima"].items()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--generate", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    manifest = generate() if args.generate else check()
    print_summary("generate" if args.generate else "check", manifest)


if __name__ == "__main__":
    main()
