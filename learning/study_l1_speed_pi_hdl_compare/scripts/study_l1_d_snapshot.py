"""Isolate worker runtime files from one freshly built XSI snapshot.

This copies generated runtime files, not a Git checkout or worktree. Each
process gets its own logs/clock bookkeeping. Never overwrites an existing run.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

study = Path(__file__).resolve().parents[1]
runtime = study / '.runtime'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source_run', help='Fresh generated XSI directory name under .runtime')
parser.add_argument('worker_prefix', nargs='?', default='d_fresh',
                    help='Unused worker prefix; creates PREFIX_original/coder_baseline/hand_sv')
args = parser.parse_args()
source = runtime / args.source_run
assert source.is_dir()
assert '/' not in args.worker_prefix and '\\' not in args.worker_prefix
targets = {implementation: runtime / f'{args.worker_prefix}_{implementation}'
           for implementation in ('original', 'coder_baseline', 'hand_sv')}
assert not any(target.exists() for target in targets.values()), 'All worker directories must be new.'
members = [Path('hdlverifier_wizard_study_l1_system_cosim_top.slx'),
           Path('sin_qw_4096x18.mem'), Path('source_manifest.txt')]
members += [p.relative_to(source) for p in (source / 'xsim.dir' / 'design').rglob('*') if p.is_file()]
for implementation, target in targets.items():
    assert not target.exists()
    target.mkdir()
    checksums = {}
    for relative in members:
        incoming = source / relative
        outgoing = target / relative
        outgoing.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(incoming, outgoing)
        checksums[str(relative)] = hashlib.sha256(outgoing.read_bytes()).hexdigest()
        assert checksums[str(relative)] == hashlib.sha256(incoming.read_bytes()).hexdigest()
    (target / 'snapshot_manifest.json').write_text(json.dumps(dict(source=str(source), files=checksums), indent=2), encoding='utf-8')
    print('D_RUNTIME_ISOLATED', implementation, 'files', len(checksums))
