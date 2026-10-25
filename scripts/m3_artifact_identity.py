"""Small standard-library identity bridge for MATLAB installations without Java."""
import argparse
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('operation', choices=['hash', 'run_path'])
p.add_argument('--path', required=True)
p.add_argument('--root')
a = p.parse_args()
file = Path(a.path).resolve()
if a.operation == 'hash':
    result = {'sha256': hashlib.sha256(file.read_bytes()).hexdigest()}
else:
    allowed = (Path(a.root) / '.runtime').resolve()
    assert file != allowed and file.is_relative_to(allowed), 'Use a distinct directory inside checkout .runtime'
    result = {'path': str(file)}
print(json.dumps(result, ensure_ascii=True))
