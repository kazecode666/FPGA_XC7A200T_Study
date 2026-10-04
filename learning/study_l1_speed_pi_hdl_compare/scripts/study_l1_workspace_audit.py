"""Hash the original dirty files; never edit, delete, stash or restore them."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCOPE = 'learning/study_l1_speed_pi_hdl_compare/'
REPORT = ROOT / SCOPE / 'reports/checkpoint_a/workspace_preflight.json'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT).decode('utf-8')


def digest(path):
    p = ROOT / path
    if not p.exists():
        return None
    assert p.is_file(), p
    h = hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


if sys.argv[1] == 'capture':
    assert not REPORT.exists(), 'Never overwrite the original preflight.'
    assert not git('diff', '--cached', '--name-only').strip(), 'Index must be empty.'
    names = set(git('diff', '--name-only', '-z').split('\0'))
    names.update(git('ls-files', '--others', '--exclude-standard', '-z').split('\0'))
    names = sorted(n for n in names if n and not n.startswith(SCOPE))
    data = dict(branch=git('branch', '--show-current').strip(),
                head=git('rev-parse', 'HEAD').strip(),
                main=git('rev-parse', 'origin/main').strip(),
                status=git('-c', 'core.quotepath=false', 'status', '--short'),
                files={n: digest(n) for n in names})
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    print('PREFLIGHT_CAPTURED', len(names), 'files')
elif sys.argv[1] == 'verify':
    data = json.loads(REPORT.read_text(encoding='utf-8'))
    changed = [n for n, h in data['files'].items() if digest(n) != h]
    assert not changed, f'Original local files changed: {changed}'
    print('ORIGINAL_LOCAL_FILES_PRESERVED', len(data['files']))
else:
    raise ValueError('Use capture or verify')
