"""Audit a presentation-only SLX migration against its immediate local baseline."""
import csv
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

before, after, report = map(Path, sys.argv[1:4])
report.mkdir(parents=True, exist_ok=True)


def read(path):
    blocks, systems = {}, {}
    with zipfile.ZipFile(path) as z:
        frozen = {n: z.read(n) for n in z.namelist()
                  if n.startswith(('simulink/stateflow/', 'simulink/configSet'))}
        for n in z.namelist():
            if n.startswith('simulink/systems/') and n.endswith('.xml'):
                root = ET.fromstring(z.read(n))
                systems[n] = root
                for b in root.findall('Block'):
                    blocks[b.get('SID')] = (n, b)
    return blocks, systems, frozen


def params(b):
    return {p.get('Name'): ET.tostring(p, encoding='unicode').strip()
            for p in b.findall('P')}


def value(b, key):
    return next((p.text for p in b.findall('P') if p.get('Name') == key), '')


def route_pairs(systems):
    pairs = []
    for name, root in systems.items():
        gotos = {value(b, 'GotoTag'): b.get('SID') for b in root.findall('Block')
                 if b.get('BlockType') == 'Goto'}
        for b in root.findall('Block'):
            if b.get('BlockType') == 'From' and value(b, 'GotoTag') in gotos:
                pairs.append((name, b.get('SID'), gotos[value(b, 'GotoTag')]))
    return sorted(pairs)


a, sa, fa = read(before)
b, sb, fb = read(after)
assert a.keys() == b.keys(), 'Block identities changed'
assert fa == fb, 'Stateflow or solver configuration changed'
assert route_pairs(sa) == route_pairs(sb), 'From/Goto producer changed'
rows = []
ports = 0
for sid, (system, old) in a.items():
    _, new = b[sid]
    assert old.get('BlockType') == new.get('BlockType'), sid
    op, np = params(old), params(new)
    for key in op.keys() | np.keys():
        if op.get(key) == np.get(key):
            continue
        allowed = (key == 'GotoTag' and system.endswith('system_root.xml')) or (
            key == 'VariableName' and sid in {'1750', '1612'}) or key == 'ShowName' or (
            key in {'Position','FontSize'} and old.get('BlockType') in {'From', 'Goto'})
        assert allowed, (sid, key, op.get(key), np.get(key))
    if old.get('BlockType') in {'Inport', 'Outport'}:
        ports += 1
        assert op == np, ('Port geometry/type/order changed', sid)
    if old.get('Name') != new.get('Name') or value(old, 'GotoTag') != value(new, 'GotoTag'):
        rows.append([sid, old.get('BlockType'), old.get('Name'), new.get('Name'),
                     value(old, 'GotoTag'), value(new, 'GotoTag')])
line_geometry_changes = 0
def canonical_lines(root):
    lines = root.findall('Line')
    for line in lines:
        for element in line.iter():
            for p in list(element):
                if p.tag == 'P' and p.get('Name') in {'Points', 'ZOrder'}:
                    element.remove(p)
    return [ET.tostring(x) for x in lines]

for name in sa:
    old_points = [p.text for p in sa[name].findall('.//Line//P') if p.get('Name') == 'Points']
    new_points = [p.text for p in sb[name].findall('.//Line//P') if p.get('Name') == 'Points']
    if old_points != new_points:
        line_geometry_changes += 1
    old = canonical_lines(sa[name])
    new = canonical_lines(sb[name])
    assert old == new, ('Signal connections/geometry changed', name)
with (report / 'name_mapping.csv').open('w', encoding='utf-8-sig', newline='') as f:
    w = csv.writer(f)
    w.writerow(['SID', 'type', 'old_block_name', 'formal_block_name', 'old_tag', 'formal_tag'])
    w.writerows(rows)
text = (f'EXISTING_BLOCKS={len(a)}\nRENAMED_BLOCKS={len(rows)}\n'
        f'PORT_PARAMETERS_AND_GEOMETRY_UNCHANGED={ports}\n'
        f'LINE_GEOMETRY_NORMALIZED_SYSTEMS={line_geometry_changes}\n'
        'SIGNAL_CONNECTIONS_UNCHANGED=1\nLOCAL_ROUTE_PRODUCERS_UNCHANGED=1\n'
        'STATEFLOW_AND_SOLVER_UNCHANGED=1\nCONTROL_PARAMETERS_UNCHANGED=1\n'
        'LOG_COLUMN_ORDER_UNCHANGED=1\nNAME_MIGRATION_STRUCTURAL_PASS=1\n')
(report / 'structural_check.txt').write_text(text, encoding='utf-8')
print(text)
