"""Audit the local entry, user dirty patch, and ONLY the three temporary edits."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile


def main():
    root = Path(__file__).resolve().parents[1]
    runtime = root / '.runtime/pr51_common_sign_20261024'
    folder = root / 'docs/reports/m2_foc_fixed_point/common_sign_diagnostic'
    entry = json.loads((runtime / 'entry_hashes.json').read_text(encoding='utf8'))
    for name, digest in entry.items():
        assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name

    def sections(data):
        return {part.split('\n', 1)[0]: part.rstrip('\n') for part in re.split(
            r'(?=^diff --git )', data.decode('utf8').replace('\r\n', '\n'), flags=re.M)
            if part.startswith('diff --git ')}

    old = sections((runtime / 'entry_dirty.patch').read_bytes())
    current = sections(subprocess.check_output(['git', 'diff', '--binary'], cwd=root))
    assert all(current.get(key) == value for key, value in old.items()), 'User dirty patch changed'
    template = Path(json.loads((runtime / 'template.json').read_text())['folder'])
    assert (template / 'PMLSM_FOC_FixedPoint.slx').read_bytes() == (
        root / 'simulink模型/PMLSM_FOC_FixedPoint.slx').read_bytes()
    with zipfile.ZipFile(root / 'simulink模型/PMLSM_PI_FOC_Float_Baseline.slx') as a, zipfile.ZipFile(
            template / 'PMLSM_PI_FOC_Float_Baseline.slx') as b:
        changed = [name for name in a.namelist() if a.read(name) != b.read(name)]
        phases = ['simulink/systems/system_' + str(sid) + '.xml' for sid in (814, 829, 844)]
        allowed = phases + ['simulink/systems/system_root.xml', 'simulink/graphicalInterface.json',
                            'metadata/coreProperties.xml', 'simulink/blockDiagram.json']
        assert set(changed) <= set(allowed), changed
        before = ET.fromstring(a.read('simulink/systems/system_root.xml'))
        after = ET.fromstring(b.read('simulink/systems/system_root.xml'))
        for element in (before, after):
            element.remove(element.find("P[@Name='SIDHighWatermark']"))
        assert ET.tostring(before) == ET.tostring(after), 'Root changed beyond SID count'
        for index, name in enumerate(phases):
            before = ET.fromstring(a.read(name)); after = ET.fromstring(b.read(name))
            original = {block.get('SID'): block for block in before.findall('Block')}
            edited = {block.get('SID'): block for block in after.findall('Block')}
            extra = set(edited) - set(original)
            assert len(extra) == 2
            for sid, block in original.items():
                other = edited[sid]
                for obj in (block, other):
                    for prop in list(obj):
                        if prop.tag == 'P' and prop.get('Name') in {'Position', 'ZOrder'}:
                            obj.remove(prop)
                assert ET.tostring(block) == ET.tostring(other), (name, sid)
            types = {edited[sid].get('BlockType'): sid for sid in extra}
            assert set(types) == {'FromWorkspace', 'Terminator'}
            recorded = edited[types['FromWorkspace']]
            props = {p.get('Name'): p.text for p in recorded.findall('P')}
            assert props['VariableName'] == 'M2_Common_Sign_' + 'abc'[index]
            assert props['SampleTime'] == 'PMLSM_Ts_s' and props['Interpolate'] == 'off'

            def edges(system):
                return {(line.find("P[@Name='Src']").text,
                         line.find("P[@Name='Dst']").text) for line in system.findall('Line')}

            sign = (826, 841, 856)[index]; product = (822, 837, 852)[index]
            expected = edges(before) - {(f'{sign}#out:1', f'{product}#in:1')}
            expected |= {(f'{sign}#out:1', types['Terminator'] + '#in:1'),
                         (types['FromWorkspace'] + '#out:1', f'{product}#in:1')}
            assert edges(after) == expected, name
    result = {'pass': True, 'canonical_entry_files_byte_identical': len(entry),
              'pre_existing_dirty_patch_sections_unchanged': len(old),
              'temporary_phase_scopes_changed': 3, 'original_block_parameters_unchanged': True,
              'temporary_root_only_SID_watermark_changed': True, 'fixed_DUT_bytes_identical': True,
              'temporary_archive_parts_changed': changed, 'production_SLX_modified': False}
    (folder / 'preservation.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf8')
    print('COMMON_SIGN_PRESERVATION_PASS', len(entry), len(old))


if __name__ == '__main__':
    main()
