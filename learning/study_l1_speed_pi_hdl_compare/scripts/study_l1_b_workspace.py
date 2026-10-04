"""Checkpoint B protection of user files and the complete committed A baseline."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCOPE = "learning/study_l1_speed_pi_hdl_compare/"
REPORT = ROOT / SCOPE / "reports/checkpoint_b/workspace_preflight.json"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode("utf-8")


def digest(name):
    path = ROOT / name
    return hashlib.file_digest(path.open("rb"), "sha256").hexdigest() if path.is_file() else None


if sys.argv[1] == "capture":
    assert not REPORT.exists(), "Never overwrite the original preflight."
    assert not git("diff", "--cached", "--name-only").strip(), "Index must be empty."
    names = set(git("diff", "--name-only", "-z").split("\0"))
    names.update(git("ls-files", "--others", "--exclude-standard", "-z").split("\0"))
    user = sorted(n for n in names if n and not n.startswith(SCOPE))
    frozen = sorted(n for n in git("ls-files", "-z", SCOPE).split("\0") if n)
    data = dict(branch=git("branch", "--show-current").strip(),
                head=git("rev-parse", "HEAD").strip(),
                main=git("rev-parse", "origin/main").strip(),
                status=git("-c", "core.quotepath=false", "status", "--short"),
                user_files={n: digest(n) for n in user},
                frozen_a_files={n: digest(n) for n in frozen})
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print("CAPTURED", len(user), "user files and", len(frozen), "frozen A files")
elif sys.argv[1] == "verify":
    data = json.loads(REPORT.read_text(encoding="utf-8"))
    for category in ("user_files", "frozen_a_files"):
        changed = [n for n, h in data[category].items() if digest(n) != h]
        assert not changed, f"Protected files changed: {changed}"
        print("PRESERVED", category, len(data[category]))
else:
    raise ValueError("Use capture or verify")
