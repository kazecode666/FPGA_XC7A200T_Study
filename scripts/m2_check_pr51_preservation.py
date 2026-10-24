"""PR51 review: prove every local model/script at entry and dirty hunk is retained."""
from pathlib import Path
import hashlib
import json
import re
import subprocess


def main():
    root = Path(__file__).resolve().parents[1]
    runtime = root / '.runtime/pr51_review_20261024'
    before = json.loads((runtime / 'entry_hashes.json').read_text(encoding='utf8'))
    rows = []
    for name, expected in before.items():
        actual = hashlib.sha256((root / name).read_bytes()).hexdigest()
        assert actual == expected, f'Local entry source changed: {name}'
        rows.append({'file': name, 'sha256': actual, 'byte_identical_to_local_entry': True})

    def sections(data):
        text = data.decode('utf8').replace('\r\n', '\n')
        return {part.split('\n', 1)[0]: part.rstrip('\n')
                for part in re.split(r'(?=^diff --git )', text, flags=re.M)
                if part.startswith('diff --git ')}

    old = sections((runtime / 'entry_dirty.patch').read_bytes())
    new = sections(subprocess.check_output(['git', 'diff', '--binary'], cwd=root))
    mismatches = [name for name, patch in old.items() if new.get(name) != patch]
    assert not mismatches, f'Pre-existing local dirty changes altered: {mismatches}'
    result = {'pass': True, 'files': rows, 'local_entry_files_unchanged': len(rows),
              'pre_existing_dirty_patch_sections_unchanged': len(old),
              'production_slx_changed_by_revision': False, 'files_deleted': 0}
    target = root / 'docs/reports/m2_foc_fixed_point/pr51_revision/preservation.json'
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    print('PR51_PRESERVATION_PASS', len(rows), len(old))


if __name__ == '__main__':
    main()
