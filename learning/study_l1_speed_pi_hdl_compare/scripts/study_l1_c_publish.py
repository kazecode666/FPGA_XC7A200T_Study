"""Publish C evidence without replacing any existing baseline or user file."""
import csv
import difflib
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path
from study_l1_c_coverage import audit

STUDY = Path(__file__).resolve().parents[1]
ROOT = STUDY.parents[1]
golden, coder = (Path(p).resolve() for p in sys.argv[1:3])
# Arguments alternate implementation-job root and XSim directory, in table order.
runs = {name: (Path(i).resolve(), Path(s).resolve())
        for name, i, s in zip(("baseline", "hand", "csd"), sys.argv[3::2], sys.argv[4::2])}
assert len(sys.argv) == 9
REPORT = STUDY / "reports/checkpoint_c"
GENERATED = coder / "generated/speed_pi_hdl"
OPT = STUDY / "generated_hdl/aw_csd"


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def copy(source, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        assert sha(source) == sha(dest), f"Never overwrite {dest}"
        return
    shutil.copyfile(source, dest)
    assert sha(source) == sha(dest)


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        assert path.read_text(encoding="utf-8") == text, f"Never overwrite {path}"
        return
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(text)


def json_write(path, data):
    write(path, json.dumps(data, ensure_ascii=False, indent=2) + "\n")


pre = json.loads((REPORT / "workspace_preflight.json").read_text(encoding="utf-8"))
for category in ("user_files", "frozen_ab_files"):
    for name, expected in pre[category].items():
        path = ROOT / name
        assert (sha(path) if path.is_file() else None) == expected, name
assert "GOLDEN_EXPORT_PASS normal_rows=2580 stress_rows=5262" in (golden / "matlab_run.txt").read_text(encoding="utf-8")
assert (golden / "normal_vectors.txt").read_text().splitlines() == (STUDY / "reports/checkpoint_b/verification/vectors.txt").read_text().splitlines()
coverage = audit(golden)
assert json.loads((coder / "pi_semantic_fingerprint.json").read_text()) == json.loads((STUDY / "reports/checkpoint_b/pi_semantic_fingerprint.json").read_text())
assert json.loads((coder / "compatibility.json").read_text()) == []
status = json.loads((GENERATED / "hdlcodegenstatus.json").read_text())
assert status["Latency"] == 2 and status["GenFileList"] == ["PI.sv", "HDLCore.sv"]


def functional_lines(path):
    return [r for r in path.read_text().splitlines() if r.strip() and not r.lstrip().startswith("//")]


assert functional_lines(GENERATED / "HDLCore.sv") == functional_lines(STUDY / "generated_hdl/baseline/HDLCore.sv")
before = functional_lines(STUDY / "generated_hdl/baseline/PI.sv")
after = functional_lines(GENERATED / "PI.sv")
delta = [(a, b) for a, b in zip(before, after) if a != b]
assert len(before) == len(after) and len(delta) == 1 and "assign AW_mul_temp" in delta[0][0]
write(REPORT / "codegen/single_option_rtl.diff", "\n".join(difflib.unified_diff(before, after, fromfile="baseline/PI.sv (comments removed)", tofile="aw_csd/PI.sv (comments removed)", lineterm="")) + "\n")
all_traces = []
metrics = {}
for variant, (impl, xsim) in runs.items():
    log = (xsim / "xsim.log").read_text()
    assert "STUDY_L1_C_XSIM_PASS rows=7842 events=2886" in log and "raw_mismatches=0" in log
    assert "Fatal:" not in log and "Error:" not in log
    trace = list(csv.reader((xsim / "trace.csv").open()))
    assert len(trace) == 2887
    all_traces.append(trace)
    data = impl / "reports"
    m = json.loads((data / "metrics.json").read_text())
    assert m["part"] == "xc7a200tfbg484-2" and m["clock_mhz"] == 50
    check = (data / "check_timing.rpt").read_text()
    for category in ("no_clock", "unconstrained_internal_endpoints", "no_input_delay", "no_output_delay", "loops", "latch_loops"):
        assert f"checking {category} (0)" in check
    route = (data / "route_status.rpt").read_text()
    assert re.search(r"nets with routing errors\.+\s*:\s*0\b", route)
    util = (data / "route_utilization.rpt").read_text()
    m["LUT"] = int(re.search(r"\| Slice LUTs\s*\|\s*(\d+)", util)[1])
    assert m["FF"] == int(re.search(r"\| Slice Registers\s*\|\s*(\d+)", util)[1])
    critical = (data / "critical_paths.rpt").read_text()
    m["critical_source"] = re.search(r"Source:\s+(\S+)", critical)[1]
    m["critical_destination"] = re.search(r"Destination:\s+(\S+)", critical)[1]
    m["critical_data_delay_ns"] = float(re.search(r"Data Path Delay:\s+([\d.]+)ns", critical)[1])
    m["critical_logic_levels"] = int(re.search(r"Logic Levels:\s+(\d+)", critical)[1])
    m["timing_met"] = m["WNS_ns"] >= 0 and m["WHS_ns"] >= 0
    m["latency_launch_clocks"] = 2
    for name in ("synth_utilization.rpt", "synth_timing.rpt", "route_utilization.rpt", "route_timing.rpt", "critical_paths.rpt", "route_status.rpt", "check_timing.rpt", "drc.rpt", "metrics.json"):
        copy(data / name, REPORT / "verification" / variant / name)
    copy(xsim / "xsim.log", REPORT / "verification" / variant / "xsim.log.txt")
    copy(xsim / "trace.csv", REPORT / "verification" / variant / "trace.csv")
    # Retain tool versions, synthesis warnings and route completion without hundreds of OOC port repeats.
    vlog = (impl / "vivado.log").read_text()
    assert "STUDY_L1_C_IMPLEMENTATION_COMPLETE" in vlog and "ERROR:" not in vlog
    excerpts = [r for r in vlog.splitlines() if any(s in r for s in ("Vivado v", "Command:", "STUDY_L1", "synth_design completed", "route_design completed", "Critical Warnings", "WARNING: [Synth", "WARNING: [Timing"))]
    write(REPORT / "verification" / variant / "vivado_excerpt.txt", "\n".join(excerpts) + "\n")
    assert not list(impl.rglob("*.bit"))
    metrics[variant] = m
assert all(t == all_traces[0] for t in all_traces)
coverage["identical_rtl_traces"] = 3
json_write(REPORT / "coverage.json", coverage)
for name in ("normal_vectors.txt", "stress_vectors.txt"):
    copy(golden / name, REPORT / "verification" / name)
copy(golden / "matlab_run.txt", REPORT / "verification/golden_matlab.txt")
copy(coder / "matlab_run.txt", REPORT / "codegen/generation_matlab.txt")
for name in ("single_option_config.json", "compatibility.json", "pi_semantic_fingerprint.json"):
    copy(coder / name, REPORT / "codegen" / name)
for name in ("PI.sv", "HDLCore.sv"):
    copy(GENERATED / name, OPT / name)
write(OPT / ".gitattributes", "*.sv -text -whitespace\n")
copy(coder / "speed_pi_hdl.slx", STUDY / "models/checkpoint_c_aw_csd/speed_pi_hdl.slx")
write(STUDY / "models/checkpoint_c_aw_csd/.gitattributes", "*.slx -text\n")
copy(GENERATED / "hdlcodegenstatus.json", REPORT / "codegen/hdlcodegenstatus.json")
for name in ("HDLCore_report.html", "speed_pi_hdl_bill_of_materials.html", "speed_pi_hdl_dut_information.html", "speed_pi_hdl_delay_balancing.html", "speed_pi_hdl_distributed_pipelining.html", "rtwreport.css", "rtwshrink.js"):
    copy(GENERATED / "html/pages" / name, REPORT / "codegen" / name)
write(REPORT / "codegen/generator_parameters.txt", status["ModelGenStatus"]["CLI"])
sources = [STUDY / "handwritten/speed_pi_sv.sv", STUDY / "handwritten/speed_pi_compare.sv", STUDY / "scripts/study_l1_c_tb.sv", STUDY / "scripts/study_l1_c_vivado.tcl", STUDY / "scripts/study_l1_50mhz.xdc"]
sources += list((STUDY / "generated_hdl/baseline").glob("*.sv")) + list(OPT.glob("*.sv"))
source_hashes = {str(path.relative_to(STUDY)).replace("\\", "/"): sha(path) for path in sources}
part_evidence = {}
for path in (ROOT / "FOC_Current/FOC_Current.xpr", ROOT / "FOC_Transforms/FOC_Transforms.xpr", ROOT / "PWM_Controller/PWM_Controller.xpr", ROOT / "PWM_Breathe/PWM_Breathe.xpr"):
    part = re.search(r'<Option Name="Part" Val="([^"]+)"', path.read_text())[1]
    assert part == "xc7a200tfbg484-2"
    part_evidence[str(path.relative_to(ROOT)).replace("\\", "/")] = dict(part=part, sha256=sha(path))
loc = {"hand": len((STUDY / "handwritten/speed_pi_sv.sv").read_text().splitlines()),
       "baseline": sum(len((STUDY / "generated_hdl/baseline" / n).read_text().splitlines()) for n in ("PI.sv", "HDLCore.sv")),
       "csd": sum(len((OPT / n).read_text().splitlines()) for n in ("PI.sv", "HDLCore.sv")),
       "common_adapter": len((STUDY / "handwritten/speed_pi_compare.sv").read_text().splitlines())}
summary = dict(checkpoint="C", status="COMPLETE_WITH_HAND_50MHZ_SETUP_VIOLATION", base_main=pre["main"],
               golden_B1_sha256=sha(STUDY / "models/speed_pi_fixed.slx"), all_14_raw_bit_exact=True,
               rows_per_implementation=7842, valid_events_per_implementation=2886, raw_mismatches=0,
               first_source_tick_us=900, normal_update_period_us=1000, update_interval_clocks=50000,
               minimum_event_interval_clocks=2, latency_launch_clocks=2, latency_accept_clocks=1,
               testbench_drive_edge="negedge", testbench_drive_to_output_ns=30, testbench_observation_delay_ns=1,
               global_CE_inflight_stall=True, synchronous_reset_over_CE=True, diagnostics=14,
               metrics=metrics, RTL_physical_LOC_including_comments=loc, sources_sha256=source_hashes,
               actual_xpr_part_evidence=part_evidence, user_files_preserved=288, frozen_AB_files_preserved=88,
               golden_run=str(golden), optimization_run=str(coder),
               implementation_runs={k: str(v[0]) for k, v in runs.items()},
               xsim_runs={k: str(v[1]) for k, v in runs.items()},
               optimization="AW Gain ConstMultiplierOptimization: none -> csd (one option, one block)",
               timing_scope="OOC registered IP; no package/board I/O route signoff",
               checkpoint_D=False, full_motor_cosimulation=False, bitstream=False, hardware=False)
json_write(REPORT / "summary.json", summary)
manifest = "# AW CSD generated RTL manifest\n\nUntouched native HDL Coder 26.2 / MATLAB R2026b GA output.\n\n"
manifest += "Only `speed_pi_hdl/HDLCore/PI/AW: ConstMultiplierOptimization=csd` differs from the frozen baseline. InputPipeline=1, OutputPipeline=1, all numerical block parameters/wiring and global settings unchanged; latency=2.\n\n"
manifest += "| Native file | SHA256 |\n|---|---|\n"
for name in ("PI.sv", "HDLCore.sv"):
    manifest += f"| {name} | `{sha(OPT / name)}` |\n"
manifest += f"\nGeneration source: `{coder}`. Reproduce with `study_l1_c_csd(freshDirectory)`. Native bytes preserved by local .gitattributes.\n"
manifest += "\n[Single-option configuration](../../reports/checkpoint_c/codegen/single_option_config.json), [native status / latency](../../reports/checkpoint_c/codegen/hdlcodegenstatus.json), [functional RTL diff](../../reports/checkpoint_c/codegen/single_option_rtl.diff).\n"
write(OPT / "MANIFEST.md", manifest)
print(json.dumps(dict(metrics=metrics, LOC=loc, published="Checkpoint C only"), indent=2))
