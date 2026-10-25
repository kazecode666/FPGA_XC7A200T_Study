"""Manifest-locker unit fixtures only; no controller simulation is claimed."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / 'scripts/m3_lock_manifest.py'
AREA = ROOT / '.runtime' / ('m3_manifest_tests_' + uuid.uuid4().hex)
AREA.mkdir()


def fixture(name, completed=True, data=True, source=True):
    work = AREA / name
    hdl = work / 'rtl' / 'GeneratedModel'
    model = work / 'model'
    hdl.mkdir(parents=True); model.mkdir()
    frozen = work / 'source'
    frozen.mkdir()
    names = ('PMLSM_PI_FOC_Float_Baseline.slx', 'PMLSM_FOC_FixedPoint.slx',
             'init_PMLSM_PI_FOC_Float_Baseline.m', 'm1a_require_float_init.m',
             'pmlsm_foc_fixed_config.m', 'design_PMLSM_three_loop.m',
             'pmlsm_scurve_profile.m', 'pmlsm_point_move_step.m')
    if source:
        for name in names:
            (frozen / name).write_bytes(('identity fixture ' + name).encode())
    (hdl / 'FOC_DUT_pkg.sv').write_text('package FOC_DUT_pkg; typedef logic [63:0] wide_t; endpackage\n')
    (hdl / 'child.sv').write_text('module child(input logic clk, output FOC_DUT_pkg::wide_t q); always_ff @(posedge clk) q <= q+1; endmodule\n')
    (hdl / 'FOC_DUT.sv').write_text('module FOC_DUT(input logic clk, output FOC_DUT_pkg::wide_t q); child u_child(clk,q); endmodule\n')
    (hdl / 'FOC_DUT_tb.sv').write_text('module FOC_DUT_tb; integer f; initial begin f=$fopen("FOC_DUT_tb_data.dat","r"); $display("TEST COMPLETED (PASSED)"); $finish; end endmodule\n')
    if data:
        (hdl / 'FOC_DUT_tb_data.dat').write_text('0123456789abcdef\n')
    (hdl / 'FOC_DUT_map.txt').write_text('Mapping report, not runtime stimulus.\n')
    (work / 'hdl_config_readback.json').write_text(json.dumps({'TargetLanguage': 'SystemVerilog', 'Oversampling': 5000}))
    if completed:
        (work / 'generate_result.json').write_text(json.dumps({'stage': 'generate', 'status': 'PASS', 'actual_language': 'SystemVerilog'}))
    descriptor = work / 'final_build.json'
    descriptor.write_text(json.dumps({'work_dir': str(work), 'model_folder': str(model), 'rtl_dir': str(work / 'rtl')}))
    return work, hdl, descriptor


class ManifestTests(unittest.TestCase):
    def run_lock(self, descriptor, output):
        return subprocess.run([sys.executable, str(SCRIPT), '--build', str(descriptor), '--output', str(output)], capture_output=True, text=True)

    def test_partial_generation_rejected(self):
        work, _, descriptor = fixture('partial', completed=False)
        output = work / 'manifest.json'
        result = self.run_lock(descriptor, output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('makehdltb', result.stderr)
        self.assertFalse(output.exists())

    def test_package_and_dependency_order_hashes_and_data(self):
        work, hdl, descriptor = fixture('complete')
        output = work / 'manifest.json'
        result = self.run_lock(descriptor, output)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads(output.read_text(encoding='utf8'))
        self.assertEqual([x['path'] for x in manifest['design_files']], ['FOC_DUT_pkg.sv', 'child.sv', 'FOC_DUT.sv'])
        self.assertEqual([x['path'] for x in manifest['testbench_files']], ['FOC_DUT_tb.sv'])
        self.assertEqual([x['path'] for x in manifest['data_files']], ['FOC_DUT_tb_data.dat'])
        self.assertEqual(manifest['simulation']['kind'], 'generated_ordinary')
        self.assertEqual(len(manifest['build_identity']['source_files']), 8)
        self.assertEqual(manifest['compile_order'], ['FOC_DUT_pkg.sv', 'child.sv', 'FOC_DUT.sv', 'FOC_DUT_tb.sv'])
        self.assertIsNone(manifest['simulation']['expected_frames'])
        for entry in manifest['design_files'] + manifest['testbench_files'] + manifest['data_files']:
            self.assertEqual(entry['sha256'], hashlib.sha256((hdl / entry['path']).read_bytes()).hexdigest())

    def test_missing_read_dependency_rejected(self):
        work, _, descriptor = fixture('missing_data', data=False)
        result = self.run_lock(descriptor, work / 'manifest.json')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('dependency', result.stderr)

    def test_missing_frozen_source_rejected(self):
        work, _, descriptor = fixture('missing_source', source=False)
        output = work / 'manifest.json'
        result = self.run_lock(descriptor, output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('eight frozen source', result.stderr)
        self.assertFalse(output.exists())

    def test_manifest_cannot_be_overwritten(self):
        work, _, descriptor = fixture('immutable')
        output = work / 'manifest.json'
        first = self.run_lock(descriptor, output)
        self.assertEqual(first.returncode, 0, first.stderr)
        saved = output.read_bytes()
        second = self.run_lock(descriptor, output)
        self.assertNotEqual(second.returncode, 0)
        self.assertIn('exists', second.stderr)
        self.assertEqual(saved, output.read_bytes())


if __name__ == '__main__':
    unittest.main(verbosity=2)
