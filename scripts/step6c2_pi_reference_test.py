"""Independent explicit expectations for C2; never rely on disabled asserts."""
import subprocess
import sys
import unittest
from unittest.mock import patch
from pathlib import Path

if sys.flags.optimize:
    raise SystemExit('C2 rejects optimized Python: run without -O/-OO')

import step6c2_pi_reference as ref


class ReferenceTests(unittest.TestCase):
    def test_round(self):
        for x, shift, expected in [(-8060928,16,-123),(32768,16,1),
                (-32768,16,-1),(-(1<<95),16,-(1<<79)),(0,0,0),
                (-7,0,-7),(32767,16,0),(-32767,16,0),(32769,16,1),
                (-32769,16,-1),(65536,16,1),(-65536,16,-1)]:
            self.assertEqual(ref.round_shift_away(x,shift),expected)

    def test_constants_and_ranges(self):
        self.assertEqual(ref.constants(), {'KP':[146381210,73190605],
            'KI_TS':[19881001,9940500], 'KAW':3355443,'LD':1873679,
            'LQ':1873679,'PSI_F':151397597,'C_UMAX':557932618,'EPS_RAW':17})
        for width in (25,40):
            self.assertTrue(ref.fits_signed(-(1<<(width-1)),width))
            self.assertTrue(ref.fits_signed((1<<(width-1))-1,width))
            self.assertFalse(ref.fits_signed(-(1<<(width-1))-1,width))
            self.assertFalse(ref.fits_signed(1<<(width-1),width))

    def test_three_one_amp(self):
        state = (0,0,0,0,0)
        for raw,old,nxt,out in [(146381210,0,19881001,285901),
                (166262211,19881001,39762002,324731),
                (186143212,39762002,59643003,363561)]:
            r = ref.pi_step(state,ref.sample(id_ref=32768),0)
            self.assertEqual((r['ud_raw'],r['old_state'][0],r['next_state'][0],r['ud_lim']),
                             (raw,old,nxt,out))
            self.assertEqual(r['next_state'][1:],(0,0,0,0))
            state = r['next_state']

    def test_feedforward_and_error_signs(self):
        for sign in (-1,1):
            r=ref.pi_step((0,0,0,0,0),ref.sample(id_meas=32768,id_ref=32768,
                          iq_meas=65536,iq_ref=65536,we=sign*65536),0)
            self.assertEqual((r['ud_raw'],r['uq_raw']),(-sign*58552,sign*2394864))
            self.assertEqual(r['next_state'][:2],(0,0))
        r=ref.pi_step((0,0,0,0,0),ref.sample(id_meas=32768,iq_meas=65536),0)
        self.assertEqual((r['ud_raw'],r['uq_raw']),(-146381210,-292762420))

    def test_order_resets_errors(self):
        state = (1000,2000,3000,-4000,1)
        r = ref.pi_step(state,ref.sample(),0)
        self.assertEqual((r['ud_raw'],r['uq_raw']),(1000,2000))
        self.assertEqual(r['next_state'][:2],(400,2800))
        r = ref.pi_step(state,ref.sample(pi_reset=1),0)
        self.assertEqual(r['old_state'],state)
        self.assertEqual(r['next_state'],(0,0,0,0,0))
        r = ref.pi_step(state,ref.sample(uq_zero_en=1,iq_meas=32768,we=65536),0)
        self.assertEqual(r['next_state'][0],400)
        self.assertEqual(r['ud_raw'],1000-ref.round_shift_away(1873679,6))
        self.assertEqual((r['uq_raw'],r['next_state'][1],r['next_state'][3]),(0,0,0))
        for v in (0,-1):
            r = ref.pi_step(state,ref.sample(pi_reset=1,vdc=v),0)
            self.assertEqual(r['error_code'],1)
            self.assertEqual(r['next_state'],state)
            self.assertEqual((r['du_d_next'],r['du_q_next']),state[2:4])
        extreme = (ref.STATE_MAX,0,0,0,0)
        r = ref.pi_step(extreme,ref.sample(id_ref=32768),0)
        self.assertEqual((r['error_code'],r['next_state']),(2,extreme))
        self.assertEqual(ref.pi_step(extreme,ref.sample(pi_reset=1,id_ref=32768),0)['error_code'],0)
        self.assertEqual(ref.pi_step((0,0,0,0,0),ref.sample(id_ref=1),0)['next_state'][0],607)
        # A wide FF term exceeds S40 before valid cancellation with OLD xq.
        cancellation=ref.pi_step((0,1<<38,0,0,0),ref.sample(id_meas=(1<<24)-1,id_ref=(1<<24)-1,we=-(1<<31)),0)
        self.assertEqual(cancellation['error_code'],0)

    def test_fixture_regeneration_and_invariants(self):
        artifacts,manifest=ref.build_artifacts()
        other,_=ref.build_artifacts()
        self.assertEqual(artifacts,other)
        for name,spec in manifest['fixtures'].items():
            lines=artifacts[ref.VECTOR_DIR/name].splitlines()[1:]
            self.assertEqual(len(lines),spec['rows'])
            seen=set()
            for line in lines:
                words=line.split(); self.assertEqual(len(words),len(spec['columns']))
                values={}
                for token,col in zip(words,spec['columns']):
                    self.assertEqual(len(token),(col['width']+3)//4)
                    n=int(token,16); self.assertLess(n,1<<col['width'])
                    if col['signed'] and n&(1<<(col['width']-1)): n-=1<<col['width']
                    values[col['name']]=n
                key=tuple(values[k] for k in ('profile','sequence_id','transaction_id','id') if k in values)
                self.assertNotIn(key,seen); seen.add(key)
                if name=='sqrt_vectors.txt':
                    n,r,m=values['radicand'],values['root'],values['remainder']
                    self.assertEqual(n,r*r+m); self.assertLess(m,2*r+1)
                if name=='divider_vectors.txt' and values['denominator']:
                    self.assertEqual(values['numerator'],values['quotient']*values['denominator']+values['remainder'])
                    self.assertLess(values['remainder'],values['denominator'])
        self.assertEqual(manifest['core_counts_per_profile']['seeded_success'],1024)
        self.assertEqual(manifest['core_counts_per_profile']['accepted_errors'],128)

    def test_check_rejects_tampering_and_inventory(self):
        artifacts,_=ref.build_artifacts()
        # Mock filesystem reads only; leave all real reference/fixture files intact.
        original=Path.read_text
        for target in (ref.VECTOR_DIR/'manifest.json',ref.VECTOR_DIR/'sqrt_vectors.txt',ref.COMPARISON):
            def corrupt(path,*args,**kwargs):
                return original(path,*args,**kwargs)+'BAD\n' if path==target else original(path,*args,**kwargs)
            with patch.object(Path,'read_text',corrupt):
                with self.assertRaisesRegex(ValueError,'content mismatch'): ref.check_artifacts(artifacts)
        inventory=[p for p in ref.VECTOR_DIR.rglob('*') if p.is_file()]
        with patch.object(Path,'rglob',return_value=iter(inventory[1:])):
            with self.assertRaisesRegex(ValueError,'inventory differs'): ref.check_artifacts(artifacts)
        extra=ref.VECTOR_DIR/'unexpected_vectors.txt'
        original_is_file=Path.is_file
        with patch.object(Path,'rglob',return_value=iter(inventory+[extra])), patch.object(Path,'is_file',lambda p: True if p==extra else original_is_file(p)):
            with self.assertRaisesRegex(ValueError,'inventory differs'): ref.check_artifacts(artifacts)

    def test_reject_invalid_inputs(self):
        for kwargs in ({'id_ref':1<<24},{'we':1<<31},{'pi_reset':2},{'vdc':1<<24}):
            with self.assertRaises(ValueError): ref.pi_step((0,0,0,0,0),ref.sample(**kwargs),0)
        with self.assertRaises(ValueError): ref.pi_step((0,0,0,0,0),ref.sample(),2)
        with self.assertRaises(ValueError): ref.limiter_raw(1<<39,0,1)
        with self.assertRaises(ValueError): ref.round_shift_away(1,-1)

    def test_limiter_directed(self):
        r = ref.limiter_raw(0,0,1)
        self.assertEqual((r['denom'],r['ud_lim'],r['uq_lim']),(17,0,0))
        r = ref.limiter_raw(-(1<<39),-(1<<39),1)
        self.assertEqual(r['norm_sq'],1<<79)
        self.assertEqual(r['error_code'],0)
        for d,q,bus in ref.limiter_inputs():
            if bus>0: ref.check_ideal(d,q,bus,ref.limiter_raw(d,q,bus))

    def test_actual_replay(self):
        rows, summary = ref.replay_actual()
        self.assertEqual(len(rows),160)
        self.assertEqual(summary['profile_counts'],[80,80])
        for item in summary['maxima'].values(): self.assertLessEqual(item['error'],.002)

    def test_optimized_rejected(self):
        for flag in ('-O','-OO'):
            run = subprocess.run([sys.executable,flag,str(Path(ref.__file__)),'--check'],capture_output=True,text=True)
            self.assertNotEqual(run.returncode,0)
            self.assertIn('rejects optimized Python',run.stderr+run.stdout)


if __name__ == '__main__': unittest.main(verbosity=2)
