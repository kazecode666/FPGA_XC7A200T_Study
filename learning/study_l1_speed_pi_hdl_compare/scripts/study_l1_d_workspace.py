"""D preflight: original checkout, user files, frozen A/B/C and all host/FOC sources."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCOPE = "learning/study_l1_speed_pi_hdl_compare/"
REPORT = ROOT / SCOPE / "reports/checkpoint_d/workspace_preflight.json"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode("utf-8")


def digest(name):
    path = ROOT / name
    if not path.is_file():
        return None
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


if sys.argv[1] == "capture":
    assert not REPORT.exists(), "Never replace an original protection snapshot."
    assert not git("diff", "--cached", "--name-only").strip(), "Index must be empty."
    assert not git("diff", "--name-only", "HEAD", "origin/main").strip()
    names = set(git("diff", "--name-only", "-z").split("\0"))
    names.update(git("ls-files", "--others", "--exclude-standard", "-z").split("\0"))
    user = sorted(n for n in names if n and not n.startswith(SCOPE))
    tracked = sorted(n for n in git("ls-files", "-z").split("\0") if n)
    abc = [n for n in tracked if n.startswith(SCOPE)]
    other = [n for n in tracked if not n.startswith(SCOPE)]
    data = dict(original_branch=git("branch", "--show-current").strip(),
                original_head=git("rev-parse", "HEAD").strip(),
                main=git("rev-parse", "origin/main").strip(),
                original_to_main_file_diff="empty",
                status=git("-c", "core.quotepath=false", "status", "--short"),
                user_files={n: digest(n) for n in user},
                frozen_abc_files={n: digest(n) for n in abc},
                frozen_other_tracked={n: digest(n) for n in other})
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    with REPORT.open("x", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print("CAPTURED", len(user), "user states", len(abc), "A/B/C files", len(other), "other tracked sources")
elif sys.argv[1] == "verify":
    data = json.loads(REPORT.read_text(encoding="utf-8"))
    for category in ("user_files", "frozen_abc_files", "frozen_other_tracked"):
        changed = [n for n, h in data[category].items() if digest(n) != h]
        assert not changed, f"Protected content changed: {changed}"
        print("PRESERVED", category, len(data[category]))
else:
    raise ValueError("Use capture or verify")
