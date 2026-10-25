"""M3 source/dirty protection audit; hashes prove identity, not functional success."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parents[1]
    run = Path(sys.argv[1]) if len(sys.argv) > 1 else root / '.runtime/m3_20261024_001'
    entry = json.loads((run / 'entry_hashes.json').read_text(encoding='utf8'))
    for name, digest in entry.items():
        assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name

    def sections(data):
        return {part.split('\n', 1)[0]: part.rstrip('\n') for part in re.split(
            r'(?=^diff --git )', data.decode('utf8').replace('\r\n', '\n'), flags=re.M)
            if part.startswith('diff --git ')}

    old = sections((run / 'entry_dirty.patch').read_bytes())
    current = sections(subprocess.check_output(['git', 'diff', '--binary'], cwd=root))
    assert all(current.get(k) == v for k, v in old.items()), 'Unrelated user dirty patch changed'
    sources = []
    for file in (run / 'source').iterdir():
        assert file.is_file()
        canonical = root / 'simulink模型' / file.name
        assert canonical.read_bytes() == file.read_bytes(), 'Frozen source differs: ' + file.name
        sources.append({'name': file.name, 'canonical': str(canonical),
                        'snapshot': str(file), 'sha256': hashlib.sha256(file.read_bytes()).hexdigest()})
    result = {'pass': True, 'source_files': sources, 'canonical_entry_files_unchanged': len(entry),
              'user_dirty_patch_sections_unchanged': len(old), 'run_dir': str(run),
              'base_commit': '476c5a36148ad0c54010240e4da25e37436ec600'}
    folder = root / 'docs/reports/m3_foc_hdl'
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'source_identity.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf8')
    print('M3_SOURCE_PROTECTION_PASS', len(entry), len(old), len(sources))


if __name__ == '__main__':
    main()
