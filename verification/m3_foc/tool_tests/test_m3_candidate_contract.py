import copy
import importlib.util
from pathlib import Path
import unittest
import hashlib,json,subprocess,tempfile

ROOT=Path(__file__).resolve().parents[3]
SPEC=importlib.util.spec_from_file_location('contract',ROOT/'scripts/m3_candidate_contract.py')

class CandidateContract(unittest.TestCase):
    def test_real_stager_rejects_stale_candidate_phase_and_mapping(self):
        (ROOT/'.runtime').mkdir(exist_ok=True)
        folder=Path(tempfile.mkdtemp(prefix='pr53_contract_negative_',dir=ROOT/'.runtime'))
        baseline=json.loads((ROOT/'generated/m3_foc/manifest.json').read_text())
        contract={'candidate_id':'p1','configuration_sha256':baseline['build_identity']['configuration_sha256'],
          'output_phase_cycles':293,'frame_cycles':5000,'state_events':{'pi_consume':5000,'pi_commit':5000,'aw_commit':1},
          'state_mapping':dict.fromkeys(['x_d_old','x_q_old','aw_d_old','aw_q_old'],'mapped'),
          'schedule_evidence':'test only scheduling fixture'}
        for name in ['candidate','phase','mapping']:
            c=copy.deepcopy(contract);m=copy.deepcopy(baseline);m['candidate_id']='p1'
            if name=='candidate':m['candidate_id']='p2'
            if name=='phase':c['output_phase_cycles']=274
            if name=='mapping':c['state_mapping'].pop('aw_q_old')
            cf=folder/(name+'_contract.json');cf.write_text(json.dumps(c))
            m['candidate_contract']={'path':str(cf),'sha256':hashlib.sha256(cf.read_bytes()).hexdigest(),'output_phase_cycles':293}
            mf=folder/(name+'_manifest.json');mf.write_text(json.dumps(m))
            result=subprocess.run(['python',str(ROOT/'scripts/m3_build_scoreboard.py'),'--manifest',str(mf),
              '--golden','unused.csv','--out',str(folder/name/'manifest.json'),'--case',name],capture_output=True,text=True)
            with self.subTest(name=name):
                self.assertNotEqual(result.returncode,0)
                self.assertIn('candidate' if name!='mapping' else 'mapping',result.stderr)
                self.assertFalse((folder/name).exists())

    def test_identity_phase_and_state_fail_closed(self):
        self.assertTrue(SPEC.loader is not None)
        module=importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(module)
        identity={'candidate_id':'p1','configuration_sha256':'a'*64}
        good={**identity,'output_phase_cycles':310,'frame_cycles':5000,
              'state_events':{'pi_consume':5000,'pi_commit':5000,'aw_commit':1},
              'state_mapping':dict.fromkeys(['x_d_old','x_q_old','aw_d_old','aw_q_old'],'mapped'),
              'schedule_evidence':'generated scheduling report'}
        self.assertEqual(module.validate(good,identity)['output_phase_cycles'],310)
        for key,value in [('candidate_id','baseline'),('configuration_sha256','b'*64),
                          ('output_phase_cycles',274),('state_events',{}),('state_mapping',{})]:
            bad=copy.deepcopy(good);bad[key]=value
            expected={**identity,'output_phase_cycles':310}
            with self.subTest(key=key),self.assertRaises(ValueError):module.validate(bad,expected)

if __name__=='__main__': unittest.main()
