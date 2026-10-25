"""Lock one completed makehdl+makehdltb build without editing generated files."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

REPO = Path(__file__).resolve().parents[1]
EXCLUDE = {'html', 'hdltmp', 'slprj', 'cache', '.git'}
FROZEN_SOURCE_FILES = (
    'PMLSM_PI_FOC_Float_Baseline.slx', 'PMLSM_FOC_FixedPoint.slx',
    'init_PMLSM_PI_FOC_Float_Baseline.m', 'm1a_require_float_init.m',
    'pmlsm_foc_fixed_config.m', 'design_PMLSM_three_loop.m',
    'pmlsm_scurve_profile.m', 'pmlsm_point_move_step.m',
)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def readjson(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def hdl_text(path):
    text = path.read_text(encoding='utf-8-sig')
    token = re.compile(r'("(?:\\.|[^"\\])*")|(/\*.*?\*/|//[^\n]*)', re.S)
    return token.sub(lambda m: m.group(1) if m.group(1) else '\n' * m.group(2).count('\n'), text)


def order_files(files):
    text = {path: hdl_text(path) for path in files}
    units = {}
    packages = set()
    for path, source in text.items():
        for kind, name in re.findall(r'\b(module|package)\s+(?:(?:automatic|static)\s+)?([A-Za-z_]\w*)', source):
            if name in units and units[name] != path:
                raise ValueError('duplicate generated HDL unit: ' + name)
            units[name] = path
            if kind == 'package':
                packages.add(name)
    dependencies = {path: set() for path in files}
    for path, source in text.items():
        for name in re.findall(r'\b([A-Za-z_]\w*)\s*::', source):
            if name not in packages and name != 'std':
                raise ValueError('unlisted generated package dependency: ' + name)
            if name in units and units[name] != path:
                dependencies[path].add(units[name])
        for name, provider in units.items():
            if provider == path or name in packages:
                continue
            instance = r'\b' + re.escape(name) + r'\s+(?:#\s*\(.*?\)\s*)?[A-Za-z_]\w*\s*\('
            if re.search(instance, source, re.S):
                dependencies[path].add(provider)
    result = []; seen = set(); active = set()

    def visit(path):
        if path in seen:
            return
        if path in active:
            raise ValueError('cyclic HDL-unit dependency: ' + path.name)
        active.add(path)
        for dependency in sorted(dependencies[path]):
            visit(dependency)
        active.remove(path); seen.add(path); result.append(path)

    package_files = {units[name] for name in packages}
    for path in sorted(files, key=lambda p: (p not in package_files, str(p))):
        visit(path)
    return result, text, units


def lock(args):
    descriptor = Path(args.build).resolve()
    output = Path(args.output).resolve()
    if output.exists():
        raise ValueError('manifest output exists; preserve the first lock')
    if not descriptor.is_relative_to(REPO) or not output.is_relative_to(REPO):
        raise ValueError('build/output must remain in the original checkout')
    build = readjson(descriptor)
    work = Path(build['work_dir']).resolve()
    rtl = Path(build['rtl_dir']).resolve()
    model = Path(build['model_folder']).resolve()
    if not work.is_relative_to(REPO / '.runtime') or not rtl.is_relative_to(work) or not model.is_relative_to(work):
        raise ValueError('build descriptor is not an isolated local generation')
    completion = work / 'generate_result.json'
    if not completion.is_file():
        raise ValueError('completed makehdltb evidence generate_result.json is absent')
    completed = readjson(completion)
    if completed.get('stage') != 'generate' or completed.get('status') != 'PASS' or completed.get('actual_language') != 'SystemVerilog':
        raise ValueError('makehdltb final generation is not a SystemVerilog PASS')
    config = work / 'hdl_config_readback.json'
    if not config.is_file() or readjson(config).get('TargetLanguage') != 'SystemVerilog':
        raise ValueError('explicit SystemVerilog configuration readback is absent')
    frozen_source = Path(args.source_dir or build.get('source_dir', descriptor.parent / 'source')).resolve()
    if not frozen_source.is_relative_to(REPO / '.runtime'):
        raise ValueError('frozen source snapshot must remain in checkout .runtime')
    frozen_files = [frozen_source / name for name in FROZEN_SOURCE_FILES]
    if not all(path.is_file() for path in frozen_files):
        raise ValueError('the eight frozen source files are required for the final identity lock')
    sources = sorted(p for p in rtl.rglob('*') if p.is_file() and p.suffix.lower() in {'.sv', '.v'} and not (set(p.relative_to(rtl).parts) & EXCLUDE))
    if not sources:
        raise ValueError('generated SystemVerilog files are absent')
    ordered, text, units = order_files(sources)
    if args.dut_top not in units or args.tb_top not in units:
        raise ValueError('final DUT/testbench module absent; makehdltb must complete before locking')
    dut = units[args.dut_top]; tb = units[args.tb_top]
    root = Path(__import__('os').path.commonpath([str(p.parent) for p in sources]))
    if not root.is_relative_to(rtl):
        raise ValueError('generated sources do not share the declared RTL subtree')
    tb_sources = {p for p in sources if p == tb or p.stem.startswith(args.tb_top)}
    design = [p for p in ordered if p not in tb_sources]
    benches = [p for p in ordered if p in tb_sources]
    if dut not in design:
        raise ValueError('DUT was misclassified as a testbench')
    data = set()
    for path in sources:
        source = text[path]
        for call, filename, mode in re.findall(r'\$(fopen|readmemh|readmemb)\s*\(\s*"([^"\n]+)"(?:\s*,\s*"([^"\n]*)")?', source):
            if call == 'fopen' and mode and not mode.startswith('r'):
                continue
            dependency = Path(filename)
            if dependency.is_absolute():
                raise ValueError('absolute runtime dependency prevents portable delivery: ' + filename)
            dependency = (tb.parent / dependency).resolve()
            if not dependency.is_relative_to(root) or not dependency.is_file():
                raise ValueError('runtime dependency missing/outside generated root: ' + filename)
            data.add(dependency)
    # Include generated file-driven vectors even if fopen uses a filename variable.
    for path in root.rglob('*'):
        if not path.is_file() or set(path.relative_to(root).parts) & EXCLUDE:
            continue
        if path.suffix.lower() in {'.dat', '.mem', '.hex', '.bin'} or (path.suffix.lower() == '.txt' and re.search(r'(?:tb.*(?:data|ref|expect)|rom|lut|coef)', path.stem, re.I)):
            data.add(path)
    literals = re.findall(r'\$(?:display|write)\s*\(\s*"((?:\\.|[^"\\])*)"', text[tb])
    success = args.ordinary_success_regex
    if not success:
        markers = [s for s in literals if re.search(r'(?:TEST|SIMULATION).*?(?:PASS|SUCCESS)|(?:PASS|SUCCESS).*?(?:TEST|SIMULATION)', s, re.I)]
        if len(markers) != 1:
            raise ValueError('ordinary TB success marker is ambiguous; provide an observed --ordinary-success-regex')
        success = re.escape(markers[0])
    re.compile(success)

    def entries(paths):
        return [{'path': p.relative_to(root).as_posix(), 'sha256': sha(p)} for p in paths]

    result = {'schema_version': 1, 'root_dir': str(root), 'dut_top': args.dut_top,
              'tb_top': args.tb_top, 'clock_port': args.clock_port, 'part': 'xc7a200tfbg484-2',
              'clock_period_ns': 20, 'runtime_subdir': tb.parent.relative_to(root).as_posix(),
              'design_files': entries(design), 'testbench_files': entries(benches),
              'compile_order': [p.relative_to(root).as_posix() for p in design + benches],
              'data_files': entries(sorted(data)), 'include_dirs': [],
              'simulation': {'kind': 'generated_ordinary', 'success_regex': success,
                             'failure_regex': r'(?im)(?:TEST\s+(?:COMPLETED\s*)?\(?FAILED|TEST\s+FAILURE|^ERROR:|^Error:|^Fatal:|M3_RTL_FAIL)',
                             'expected_frames': None, 'expected_checks': None, 'timeout_seconds': args.timeout},
              'build_identity': {'descriptor': str(descriptor), 'descriptor_sha256': sha(descriptor),
                                 'completion': str(completion), 'completion_sha256': sha(completion),
                                 'configuration_readback': str(config), 'configuration_sha256': sha(config),
                                 'source_dir': str(frozen_source),
                                 'source_files': [{'path': p.name, 'sha256': sha(p)} for p in frozen_files],
                                 'model_folder': str(model), 'work_dir': str(work)},
              'scope': 'final generated files after makehdltb; identity lock is not functional verification'}
    output.parent.mkdir(parents=True, exist_ok=True)
    readback=readjson(config)
    if 'candidate_id' in readback:
        result['candidate_id']=readback['candidate_id']
        result['candidate_settings']=readback['candidate_settings']
    with output.open('x', encoding='utf8', newline='\n') as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2); handle.write('\n')
    print('M3_MANIFEST_LOCKED', output, 'design=' + str(len(design)), 'tb=' + str(len(benches)), 'data=' + str(len(data)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--dut-top', default='FOC_DUT')
    parser.add_argument('--tb-top', default='FOC_DUT_tb')
    parser.add_argument('--clock-port', default='clk')
    parser.add_argument('--source-dir', help='frozen eight-file source snapshot; defaults to descriptor sibling source/')
    parser.add_argument('--ordinary-success-regex')
    parser.add_argument('--timeout', type=int, default=600)
    args = parser.parse_args()
    try:
        lock(args)
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        print('M3_MANIFEST_LOCK_FAIL:', error, file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
