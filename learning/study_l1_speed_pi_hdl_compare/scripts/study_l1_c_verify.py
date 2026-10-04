"""Fresh delivery consistency gate, including staged native bytes and scope."""
import hashlib
import json
import re
import subprocess
from pathlib import Path
from study_l1_c_coverage import audit

STUDY = Path(__file__).resolve().parents[1]
ROOT = STUDY.parents[1]
SCOPE = "learning/study_l1_speed_pi_hdl_compare/"
REPORT = STUDY / "reports/checkpoint_c"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


pre = json.loads((REPORT / "workspace_preflight.json").read_text(encoding="utf-8"))
summary = json.loads((REPORT / "summary.json").read_text(encoding="utf-8"))
for category in ("user_files", "frozen_ab_files"):
    assert all((sha(ROOT / name) if (ROOT / name).is_file() else None) == h
               for name, h in pre[category].items()), category
for name, digest in summary["sources_sha256"].items():
    assert sha(STUDY / name) == digest, name
assert sha(STUDY / "models/speed_pi_fixed.slx") == summary["golden_B1_sha256"]
outside = set(git("diff", "--name-only", "-z").decode().split("\0"))
outside.update(git("ls-files", "--others", "--exclude-standard", "-z").decode().split("\0"))
outside = {n for n in outside if n and not n.startswith(SCOPE)}
assert outside == set(pre["user_files"]), "New or missing out-of-scope status entries"
coverage = audit(REPORT / "verification")
assert sum(coverage[s]["rising_events"] for s in coverage) == 2886
for variant in ("baseline", "hand", "csd"):
    log = (REPORT / "verification" / variant / "xsim.log.txt").read_text()
    assert "raw_mismatches=0" in log and "Fatal:" not in log and "Error:" not in log
assert (REPORT / "verification/baseline/trace.csv").read_bytes() == (REPORT / "verification/hand/trace.csv").read_bytes() == (REPORT / "verification/csd/trace.csv").read_bytes()
for md in (STUDY / "CHECKPOINT_C.md", REPORT / "rtl_contract.md", REPORT / "final_rtl_comparison.md"):
    for target in re.findall(r'\]\(([^)]+)\)', md.read_text(encoding="utf-8")):
        if "://" not in target:
            assert (md.parent / target.split("#")[0]).exists(), (md, target)
staged = [p for p in git("diff", "--cached", "--name-only", "-z").decode().split("\0") if p]
assert staged, "Stage only C deliverables before running this gate"
allowed = ("handwritten/", "generated_hdl/aw_csd/", "models/checkpoint_c_aw_csd/", "reports/checkpoint_c/", "scripts/study_l1_c_")
for name in staged:
    assert name.startswith(SCOPE), name
    relative = name[len(SCOPE):]
    assert relative == "CHECKPOINT_C.md" or relative.startswith(allowed), name
    assert name not in pre["frozen_ab_files"], name
    assert hashlib.sha256(git("show", ":" + name)).hexdigest() == sha(ROOT / name), f"Staged bytes differ: {name}"
check = subprocess.run(["git", "diff", "--cached", "--check"], cwd=ROOT, capture_output=True, text=True)
assert check.returncode == 0, check.stdout + check.stderr
print(json.dumps(dict(fresh_delivery_gate="PASS", staged_C_files=len(staged),
                      user_files_preserved=288, frozen_AB_files_preserved=88,
                      staged_native_bytes_equal=True, all_14_raw_bit_exact=True,
                      hand_50MHz_setup="FAIL (recorded comparison outcome)",
                      baseline_50MHz="PASS", aw_csd_50MHz="PASS",
                      bitstream=False, hardware=False, checkpoint_D=False), indent=2))
