"""Read-only fresh verification of published D evidence and its trace payload.

Requires Python standard library only. Use --workspace to also check the
original author's protected local file states and frozen source hashes.
"""
import argparse
import itertools
import json
from pathlib import Path

from study_l1_d_compare import COMPARISON_FIELDS, differences, load_case, shared_contract
from study_l1_d_publish import IMPLEMENTATIONS, SCENARIOS, STUDY, ROOT, load, sha, verify_case, protected_verify, final_report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", action="store_true")
    args = parser.parse_args()
    report = STUDY / "reports/checkpoint_d"
    verification = report / "verification"
    summary = load(report / "summary.json")
    provenance = load(verification / "provenance.json")
    comparison = load(verification / "comparison.json")
    assert summary["system_case_count"] == 9 and summary["raw_mismatches"] == 0
    assert summary["hand_sv_50mhz_setup_pass"] is False
    assert summary["hand_sv_frozen_wns_ns"] == -1.957
    assert not any(summary[field] for field in ("permanent_primary_model_changes", "existing_foc_changes",
                                               "speed_pi_retuned", "bitstream", "hardware", "next_checkpoint_started"))
    for relative, expected in provenance["evidence_sha256"].items():
        assert sha(report / relative) == expected, relative
    html = (verification / "comparison.html").read_text(encoding="utf-8")
    payload = html.split('<script id="data" type="application/json">', 1)[1].split("</script>", 1)[0]
    plotted = json.loads(payload)
    raw_comparisons = 0
    for scenario in SCENARIOS:
        traces, contracts = {}, []
        for implementation in IMPLEMENTATIONS:
            folder = verification / scenario / implementation
            case, bit = verify_case(folder, scenario, implementation)
            assert summary["cases"][scenario][implementation] == {"case": case, "bit_true": bit}
            metrics, data, _ = load_case(folder, scenario, implementation)
            traces[implementation] = data
            contracts.append(shared_contract(metrics))
            assert plotted[scenario][implementation] == data, "HTML payload differs from exact CSV data."
            raw_comparisons += bit["raw_comparisons"]
        assert contracts[0] == contracts[1] == contracts[2]
        for first, second in itertools.combinations(IMPLEMENTATIONS, 2):
            actual = differences(traces[first], traces[second])
            recorded = comparison["scenarios"][scenario]["unshifted_pairwise_difference"][f"{first}_vs_{second}"]
            assert actual == recorded
        rtl = differences(traces["coder_baseline"], traces["hand_sv"])
        assert all(rtl[field]["max_abs"] == 0 for field in COMPARISON_FIELDS)
    assert raw_comparisons == 109200
    a = load(STUDY / "reports/checkpoint_a/verification/summary.json")
    b = load(STUDY / "reports/checkpoint_b/summary.json")
    c = load(STUDY / "reports/checkpoint_c/summary.json")
    expected_report = final_report(a, b, c, summary, comparison)
    assert (STUDY / "reports/STUDY_L1_FINAL_REPORT.md").read_text(encoding="utf-8") == expected_report
    console = (verification / "runtime/fresh_saved_verification_console.txt").read_text(encoding="utf-8-sig")
    assert console.count("D_FRESH_SAVED_VERIFY_PASS ") == 9
    assert "D_FRESH_ALL_NINE_SAVED_VERIFY_PASS" in console
    current_console = verification / "runtime/fresh_final_current_code_console.txt"
    if current_console.exists():
        console = current_console.read_text(encoding="utf-8-sig")
        assert console.count("D_FRESH_SAVED_VERIFY_PASS ") == 9
        assert "D_FRESH_ALL_NINE_SAVED_VERIFY_PASS" in console
    assert "Vivado v2026.1" in (verification / "runtime/vivado_compile_console.txt").read_text(encoding="utf-8-sig")
    figure_console = verification / "runtime/portable_figures_console.txt"
    if figure_console.exists():
        console = figure_console.read_text(encoding="utf-8-sig")
        for scenario in SCENARIOS:
            assert f"D_PORTABLE_FIGURE_PASS {scenario}" in console
            assert (verification / f"{scenario}_comparison.png").read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
    for implementation in IMPLEMENTATIONS:
        console = (verification / "runtime" / f"system_console_{implementation}.txt").read_text(encoding="utf-8-sig")
        assert "D_SYSTEM_RUN_PASS" in console and console.count("D_CASE_DONE ") == 3
    if args.workspace:
        print(protected_verify().strip())
        for relative, expected in provenance["source_sha256"].items():
            assert sha(ROOT / relative) == expected, relative
    print("D_FRESH_PUBLISHED_VERIFICATION_PASS cases=9 raw_codes=109200 mismatches=0 HTML_CSV_equal=1 RTL_fields_equal=7 hand_setup_pass=0")


if __name__ == "__main__":
    main()
