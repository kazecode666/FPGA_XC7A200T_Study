"""Read-only audit of M2 against this run's local entry snapshots and patch."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import zipfile


def main():
    root = Path(__file__).resolve().parents[1]
    runtime = root / '.runtime/m2_20261024'
    manifest = json.loads((runtime / 'source_manifest.json').read_text(encoding='utf-8-sig'))
    permitted = {'PMLSM_PI_FOC_Float_Baseline.slx', 'init_PMLSM_PI_FOC_Float_Baseline.m', 'm1a_require_float_init.m'}
    rows = []
    for item in manifest:
        path = root / item['path']
        snapshot = root / item['snapshot']
        same = path.read_bytes() == snapshot.read_bytes()
        required = path.name not in permitted
        assert same or not required, f'Protected source changed: {path}'
        rows.append({'file': item['path'], 'must_remain_identical': required, 'byte_identical': same,
                     'entry_sha256': hashlib.sha256(snapshot.read_bytes()).hexdigest(),
                     'current_sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    with zipfile.ZipFile(root / manifest[0]['snapshot']) as old, zipfile.ZipFile(root / manifest[0]['path']) as new:
        # All original systems except the necessarily edited caller/root must
        # remain byte-identical, including the complete original FOC subtree.
        systems = [n for n in old.namelist() if re.fullmatch(r'simulink/systems/system_\d+\.xml', n)]
        preserved = [n for n in systems if not n.endswith('/system_505.xml')]
        differences = [n for n in preserved if old.read(n) != new.read(n)]
        assert not differences, f'Original subsystem changed: {differences}'
        new_systems = set(new.namelist()) - set(old.namelist())
        # The same FOC block SID546 was moved inside a Float choice, not rebuilt.
        assert old.read('simulink/systems/system_546.xml') == new.read('simulink/systems/system_546.xml')
        stateflow = [n for n in old.namelist() if 'stateflow' in n.lower()]
        assert all(n in new.namelist() and old.read(n) == new.read(n) for n in stateflow), 'Original Stateflow changed'
    def sections(text):
        return {part.split('\n', 1)[0]: part.rstrip('\n') for part in re.split(r'(?=^diff --git )', text, flags=re.M) if part.startswith('diff --git ')}
    before = sections((runtime / 'user_before.patch').read_text(encoding='utf-8-sig').replace('\r\n', '\n'))
    current = sections(subprocess.check_output(['git', 'diff', '--binary'], cwd=root).decode('utf8').replace('\r\n', '\n'))
    unrelated = [key for key in before if not any(name in key for name in permitted)]
    mismatches = [key for key in unrelated if current.get(key) != before[key]]
    assert not mismatches, f'Unrelated dirty patch changed: {mismatches}'
    result = {'pass': True, 'source_files': rows, 'original_subsystems_identical': len(preserved),
              'original_foc_system_546_identical': True, 'unrelated_dirty_patch_sections_identical': len(unrelated),
              'original_stateflow_archive_parts_identical': len(stateflow),
              'new_archive_parts': len(new_systems), 'old_models_modified_by_M2': False,
              'layout_note': 'R2026b grid snapped39 existing block positions by1-2px; restored only serialized Position fields from local entry snapshot after native API also snapped. Reopen/update validated; no original math or wiring restored from remote.'}
    output = root / 'docs/reports/m2_foc_fixed_point/preservation.json'
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf8')
    print('M2_PRESERVATION_PASS', len(preserved), len(unrelated))


if __name__ == '__main__':
    main()
