"""Inspect actual SLX archive without executing callbacks."""
import hashlib
import json
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MODEL = ROOT / 'simulink模型/PMLSM_ThreeLoop_Simple.slx'
OUT = Path(__file__).resolve().parents[1] / 'reports/checkpoint_a/slx_static_audit.txt'
skip = {'Position', 'ZOrder', 'ShowName', 'Points', 'Labels', 'FontSize',
        'LibraryVersion', 'AttributesFormatString', 'ContentPreviewEnabled',
        'DataLogging', 'DataLoggingNameMode', 'DataLoggingName'}
lines = ['SOURCE=' + str(MODEL), 'SHA256=' + hashlib.sha256(MODEL.read_bytes()).hexdigest()]
with zipfile.ZipFile(MODEL) as z:
    bd = json.loads(z.read('simulink/blockDiagram.json'))['BlockDiagram']
    lines.append(json.dumps({k: v for k, v in bd.items() if 'Fcn' in k or k == 'ModelWorkspace'}, ensure_ascii=False))
    for sid in ('root', '191', '505', '740', '991', '1030', '1122', '1189'):
        lines.append('\nSYSTEM ' + sid)
        r = ET.fromstring(z.read('simulink/systems/system_' + sid + '.xml'))
        for b in r.findall('Block'):
            props = {p.get('Name'): p.text for p in b.findall('P') if p.get('Name') not in skip}
            props.update({p.get('Name'): p.text for p in b.findall('InstanceData/P')
                          if p.get('Name') in ('relop', 'const')})
            lines.append(str(b.attrib) + ' ' + str(props))
        for wire in r.findall('Line'):
            src = next((p.text for p in wire.findall('P') if p.get('Name') == 'Src'), None)
            dst = [p.text for p in wire.iter('P') if p.get('Name') == 'Dst']
            lines.append('WIRE ' + str(src) + ' -> ' + str(dst))
    for name in z.namelist():
        if name.startswith('simulink/stateflow/chart_'):
            r = ET.fromstring(z.read(name))
            for p in r.iter('P'):
                if p.get('Name') == 'script':
                    lines.append('\n' + name + '\n' + p.text)
OUT.write_text('\n'.join(lines), encoding='utf-8')
print(OUT)
