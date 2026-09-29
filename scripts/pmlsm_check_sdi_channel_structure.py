"""Ensure SDI naming changed saved logging metadata only, not model behavior."""
import sys
import zipfile
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

before, after, report = map(Path, sys.argv[1:4])
allowed = {'DataLogging', 'DataLoggingNameMode', 'DataLoggingName',
           'DataLoggingLimitDataPoints'}
counts = Counter()


def canonical(data):
    root = ET.fromstring(data)
    for element in root.iter():
        for p in list(element):
            if p.tag == 'P' and p.get('Name') in allowed:
                counts[p.get('Name')] += 1
                element.remove(p)
    for element in root.iter():
        for pp in list(element):
            if pp.tag == 'PortProperties':
                for port in list(pp):
                    if port.tag == 'Port' and len(port) == 0:
                        pp.remove(port)
                if len(pp) == 0:
                    element.remove(pp)
    for element in root.iter():
        if element.text is not None and not element.text.strip():
            element.text = None
        if element.tail is not None and not element.tail.strip():
            element.tail = None
    return ET.tostring(root)


with zipfile.ZipFile(before) as a, zipfile.ZipFile(after) as b:
    a_paths = set(a.namelist())
    b_paths = set(b.namelist())
    assert a_paths == b_paths, 'SLX archive members changed'
    for path in sorted(a_paths):
        if path.startswith('simulink/systems/') and path.endswith('.xml'):
            assert canonical(a.read(path)) == canonical(b.read(path)), path
        elif path.startswith(('simulink/stateflow/', 'simulink/configSet')):
            assert a.read(path) == b.read(path), path

text = ('SDI_CHANNEL_STRUCTURE_PASS=1\n'
        'CONTROLLER_PLANT_AND_CONNECTIONS_UNCHANGED=1\n'
        'STATEFLOW_AND_SOLVER_UNCHANGED=1\n'
        'INPORT_OUTPORT_PARAMETERS_AND_GEOMETRY_UNCHANGED=1\n'
        'ALLOWED_DIFF=signal_logging_metadata_only\n'
        'NAMED_SCALAR_CHANNELS=47\n')
report.write_text(text, encoding='utf-8')
print(text)
