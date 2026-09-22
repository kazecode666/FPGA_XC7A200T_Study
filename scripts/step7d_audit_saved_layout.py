"""Read-only SLX audit against the committed as-found Step 7D baseline."""
import io
import subprocess
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = 'simulink模型/PMLSM_ThreeLoop_Simple.slx'
BASE = 'f6e4e5096ad55fa67e94076893ac915ac56724c9'
before = zipfile.ZipFile(io.BytesIO(subprocess.check_output(['git', 'show', f'{BASE}:{MODEL}'], cwd=ROOT)))
after = zipfile.ZipFile(ROOT / MODEL)
ports = 0
changed = []
for name in before.namelist():
    if not name.startswith('simulink/systems/') or not name.endswith('.xml'):
        continue
    a, b = ET.fromstring(before.read(name)), ET.fromstring(after.read(name))
    old = {x.get('SID'): x for x in a.iter('Block')}
    new = {x.get('SID'): x for x in b.iter('Block')}
    for sid, block in old.items():
        if block.get('BlockType') not in ('Inport', 'Outport'):
            continue
        for prop in ('Position', 'IconDisplay'):
            assert block.findtext(f"P[@Name='{prop}']") == new[sid].findtext(f"P[@Name='{prop}']"), (sid, prop)
        ports += 1
    if before.read(name) != after.read(name):
        changed.append(name)
    for sid, block in new.items():
        if sid in old:
            continue
        if block.get('BlockType') == 'Outport':
            p = [int(v) for v in block.findtext("P[@Name='Position']").strip('[]').replace(',', ' ').split()]
            assert p[2]-p[0] == 30 and p[3]-p[1] == 14
        if block.get('BlockType') == 'Goto':
            assert block.findtext("P[@Name='TagVisibility']", 'local') == 'local'
            assert block.findtext("P[@Name='ShowName']") == 'off'
            assert not block.findtext("P[@Name='AttributesFormatString']", '')
assert set(changed) == {'simulink/systems/system_root.xml', 'simulink/systems/system_505.xml'}, changed
print(f'AS_FOUND_BASELINE={BASE}')
print(f'EXISTING_PORT_GEOMETRY_PRESERVED={ports}')
print('ONLY_CHANGED_SYSTEMS=' + ','.join(changed))
print('NEW_OUTPORT_DEFAULT_SIZE=30x14')
print('NEW_GOTO_LOCAL_AND_LABELS_HIDDEN=1')
print('STEP7D_SAVED_LAYOUT_PASS')
