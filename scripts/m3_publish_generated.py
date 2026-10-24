"""Publish raw manifest artifacts or compare independently generated builds."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def read(p):
    return json.loads(Path(p).read_text(encoding='utf-8-sig'))


def artifacts(file):
    m = read(file)
    root = Path(m.get('root_dir', '.'))
    if not root.is_absolute():
        root = Path(file).resolve().parent / root
    root = root.resolve()
    entries = {}
    for kind in ('design_files', 'testbench_files', 'data_files'):
        for item in m[kind]:
            p = (root / item['path']).resolve()
            assert p.is_relative_to(root), 'Artifact escapes root'
            assert sha(p) == item['sha256'], 'Hash mismatch ' + str(p)
            relative = p.relative_to(root).as_posix()
            entries[relative] = (p, kind, item['sha256'])
    assert entries, 'No artifacts'
    return m, entries


def publish(file, destination):
    m, items = artifacts(file)
    target = Path(destination).resolve()
    assert not target.exists(), 'Preserve existing directory ' + str(target)
    target.mkdir(parents=True)
    for name, (p, _, digest) in items.items():
        dest = target / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(p, dest)
        assert sha(dest) == digest
    m['root_dir'] = '.'
    if 'candidate_contract' in m:
        contract=Path(m['candidate_contract']['path'])
        if not contract.is_absolute():contract=Path(__file__).resolve().parents[1]/contract
        assert sha(contract)==m['candidate_contract']['sha256'],'Candidate contract hash mismatch'
        shutil.copyfile(contract,target/'candidate_contract.json')
        m['candidate_contract']['path']='candidate_contract.json'
    m['publication'] = {'source_manifest_sha256': sha(Path(file)),
                        'raw_files_unchanged': True,
                        'dependency_scope': 'all design/testbench/data files; provenance absolute paths are informational'}
    write(target / 'manifest.json', m)
    print('M3_PUBLISH_PASS', target, 'files=' + str(len(items)))


def compare(a, b, output):
    ma, aa = artifacts(a)
    mb, bb = artifacts(b)
    mismatches = []
    for name in sorted(set(aa) | set(bb)):
        if name not in aa or name not in bb or aa[name][2] != bb[name][2]:
            mismatches.append(name)
    ca = ma['build_identity']['configuration_sha256']
    cb = mb['build_identity']['configuration_sha256']
    if ca != cb:
        mismatches.append('configuration_readback')
    sa = {Path(x['path']).name: x['sha256'] for x in ma['build_identity']['source_files']}
    sb = {Path(x['path']).name: x['sha256'] for x in mb['build_identity']['source_files']}
    if sa != sb:
        mismatches.append('frozen_source_files')
    if ma.get('candidate_id')!=mb.get('candidate_id'):
        mismatches.append('candidate_id')
    if 'candidate_id' in ma:
        def contract(m):
            p=Path(m['candidate_contract']['path'])
            if not p.is_absolute():p=Path(__file__).resolve().parents[1]/p
            assert sha(p)==m['candidate_contract']['sha256'],'Candidate contract hash mismatch'
            c=read(p)
            return {key:c[key] for key in ('candidate_id','configuration_sha256','output_phase_cycles','frame_cycles','state_events','state_mapping')}
        if contract(ma)!=contract(mb):mismatches.append('candidate_schedule_or_state_contract')
    result = {'status': 'FAIL' if mismatches else 'PASS',
              'first_manifest_sha256': sha(Path(a)), 'repeat_manifest_sha256': sha(Path(b)),
              'files_compared': len(aa), 'comparison': 'exact raw bytes SHA256; no token/path/time exclusions',
              'configuration_equal': ca == cb, 'frozen_sources_equal': sa == sb,
              'mismatches': mismatches}
    write(Path(output), result)
    assert not mismatches, str(mismatches)
    print('M3_REPEAT_IDENTITY_PASS', len(aa))


def write(p, value):
    with p.open('x', encoding='utf8', newline='\n') as f:
        json.dump(value, f, ensure_ascii=False, indent=2)
        f.write('\n')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    s = p.add_subparsers(dest='operation', required=True)
    q = s.add_parser('publish')
    q.add_argument('--manifest', required=True)
    q.add_argument('--destination', required=True)
    q = s.add_parser('compare')
    q.add_argument('--first', required=True)
    q.add_argument('--repeat', required=True)
    q.add_argument('--output', required=True)
    a = p.parse_args()
    if a.operation == 'publish':
        publish(a.manifest, a.destination)
    else:
        compare(a.first, a.repeat, a.output)


if __name__ == '__main__':
    main()
