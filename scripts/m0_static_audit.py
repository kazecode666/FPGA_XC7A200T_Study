"""Read-only SLX/source inventory for M0; no MATLAB, build or model writes.

Run from repository root: python scripts/m0_static_audit.py
Full local export stays in .superpowers/m0_20261022; selected evidence is reviewed
before publication. XML is saved topology, never proof of active execution.
"""
import json
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.superpowers/m0_20261022'
MODELS = ['PMLSM_MIL_ControlCore_Sim', 'PMLSM_ControlCore_Block',
          'PMLSM_ThreeLoop_Simple', 'PMSLM_Close_Loop_MBDL4']
SKIP = {'Position', 'ZOrder', 'Location', 'Points', 'LabelPosition',
        'FontSize', 'ForegroundColor', 'BackgroundColor'}


def props(node):
    return {p.get('Name'): p.text or '' for p in node.findall('P')
            if p.get('Name') not in SKIP}


def export_model(file):
    result = dict(model=file.stem, blocks=[], lines=[], charts=[], callbacks=[], config={})
    with zipfile.ZipFile(file) as z:
        parsed = {}
        for name in z.namelist():
            if name.endswith('.xml'):
                try:
                    parsed[name] = ET.fromstring(z.read(name))
                except ET.ParseError:
                    continue
                for p in parsed[name].iter('P'):
                    if p.get('Name', '').endswith('Fcn') or p.get('Name') == 'Initialization':
                        if p.text:
                            result['callbacks'].append(dict(member=name, name=p.get('Name'), code=p.text))
            if 'configSet0' in name:
                if name.endswith('.xml'):
                    result['config'] = {p.get('Name'): p.text for p in parsed[name].iter('P')
                                        if p.get('Name') in ['SolverType', 'Solver', 'FixedStep', 'StartTime',
                                                            'StopTime', 'SystemTargetFile', 'HardwareBoard', 'TargetHWDeviceType']}
                elif name.endswith('.json'):
                    result['config_json'] = json.loads(z.read(name))
        sid_paths = {}

        def walk(system, parent):
            for b in system.findall('Block'):
                name = b.get('Name', '').replace('/', '//')
                path = parent + '/' + name
                row = dict(path=path, sid=b.get('SID'), type=b.get('BlockType'), parameters=props(b))
                row['parameters'].update(props(b.find('InstanceData')) if b.find('InstanceData') is not None else {})
                mask = b.find('Mask')
                if mask is not None:
                    row['mask'] = ET.tostring(mask, encoding='unicode')
                result['blocks'].append(row)
                sid_paths[b.get('SID')] = path
                child = b.find('System')
                if child is not None:
                    if child.get('Ref'):
                        child = parsed.get('simulink/systems/' + child.get('Ref') + '.xml')
                    if child is not None:
                        walk(child, path)
            for line in system.findall('Line'):
                src = line.find("P[@Name='Src']")
                if src is not None:
                    for dest in line.findall(".//P[@Name='Dst']"):
                        result['lines'].append(dict(system=parent, src=src.text, dst=dest.text,
                                                    name=props(line).get('Name', '')))

        walk(parsed['simulink/systems/system_root.xml'], file.stem)
        for line in result['lines']:
            for key in ['src', 'dst']:
                endpoint = line[key]
                sid, _, port = endpoint.partition('#')
                line[key] = sid_paths.get(sid, sid) + '#' + port
        for name, xml in parsed.items():
            if '/stateflow/' in name:
                scripts = [p.text for p in xml.iter('P') if p.get('Name') == 'script' and p.text]
                chart_names = [p.text for p in xml.iter('P') if p.get('Name') == 'name' and p.text]
                if scripts:
                    result['charts'].append(dict(member=name, names=chart_names, scripts=scripts))
        result['workspace_members'] = [n for n in z.namelist() if re.search('workspace|modelData', n, re.I)]
        result['diagram_metadata'] = [dict(member=n, values=props(x.find('Model')))
                                      for n, x in parsed.items() if n.endswith('blockdiagram.xml') and x.find('Model') is not None]
        for name in z.namelist():
            if name.lower().endswith('blockdiagram.json'):
                diagram = json.loads(z.read(name))['BlockDiagram']
                result['diagram_json'] = {k: v for k, v in diagram.items()
                                          if k.endswith('Fcn') or k == 'ModelWorkspace'}
                for key, value in result['diagram_json'].items():
                    if key.endswith('Fcn') and value:
                        result['callbacks'].append(dict(member=name, name=key, code=value))
    return result


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    for model in MODELS:
        data = export_model(ROOT / 'simulink模型' / (model + '.slx'))
        (OUT / (model + '_static.json')).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
        results.append(dict(model=model, blocks=len(data['blocks']), charts=len(data['charts']),
                            callbacks=data['callbacks'], config=data['config']))
    (OUT / 'static_summary.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
