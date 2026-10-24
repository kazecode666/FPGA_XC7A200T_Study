import hashlib,importlib.util,json,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('publication',ROOT/'scripts/m3_publish_generated.py')
publication=importlib.util.module_from_spec(spec);spec.loader.exec_module(publication)

class PortableCandidate(unittest.TestCase):
    def test_compare_and_republish_a_portable_candidate(self):
        (ROOT/'.runtime').mkdir(exist_ok=True)
        folder=Path(tempfile.mkdtemp(prefix='pr53_portable_',dir=ROOT/'.runtime'));source=folder/'source';source.mkdir()
        sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
        for name in ['dut.sv','tb.sv','data.dat']:(source/name).write_text('fixture bytes\n')
        contract={'candidate_id':'p3','configuration_sha256':'a'*64,'output_phase_cycles':314,'frame_cycles':5000,
          'state_events':{'pi_consume':5000,'pi_commit':1,'aw_commit':1},'state_mapping':{},'pi_next_signals':{'d':'D','q':'Q'}}
        cf=source/'candidate_contract.json';cf.write_text(json.dumps(contract))
        m={'root_dir':'.','candidate_id':'p3','candidate_contract':{'path':str(cf),'sha256':sha(cf),'output_phase_cycles':314},
          'build_identity':{'configuration_sha256':'a'*64,'source_files':[{'path':'source.slx','sha256':'b'*64}]}}
        for kind,name in [('design_files','dut.sv'),('testbench_files','tb.sv'),('data_files','data.dat')]:m[kind]=[{'path':name,'sha256':sha(source/name)}]
        mf=source/'manifest.json';mf.write_text(json.dumps(m))
        first=folder/'first';second=folder/'second';publication.publish(mf,first)
        publication.compare(mf,first/'manifest.json',folder/'comparison.json')
        publication.publish(first/'manifest.json',second)
        self.assertEqual((first/'candidate_contract.json').read_bytes(),(second/'candidate_contract.json').read_bytes())
        self.assertEqual(json.loads((folder/'comparison.json').read_text())['status'],'PASS')

if __name__=='__main__':unittest.main()
