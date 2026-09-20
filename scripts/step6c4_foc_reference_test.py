"""Small integration checks; accepted mathematical kernels stay read-only."""
import unittest
from unittest.mock import patch
import step6c4_foc_reference as f

class IntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.rom=f.read_rom()

    def test_zero_chain(self):
        for p in (0,1):
            r=f.foc_step(f.ZERO,f.sample(),p,self.rom)
            self.assertEqual((r['duty_u'],r['duty_v'],r['duty_w']),(8388608,)*3)
            self.assertEqual((r['sector'],r['error_code'],r['next_state']),(2,0,f.ZERO))

    def test_invalid_bus_holds_history_before_commands(self):
        state=(123,456,789,-345,1)
        for bus in (0,-32768):
            with patch.object(f.c2,'pi_step',side_effect=AssertionError('invalid bus reached PI')):
                r=f.foc_step(state,f.sample(vdc=bus,pi_reset=1),0,self.rom)
            self.assertEqual((r['error_code'],r['next_state'],r['duty_u']),(1,state,0))

    def test_state_is_recursive_and_command_reset_clears(self):
        s=f.sample(id_ref=32768)
        a=f.foc_step(f.ZERO,s,0,self.rom)
        b=f.foc_step(a['next_state'],s,0,self.rom)
        self.assertGreater(a['next_state'][0],0)
        self.assertEqual(b['next_state'][0],2*a['next_state'][0])
        self.assertGreater(b['ud_raw'],a['ud_raw'])
        r=f.foc_step(b['next_state'],f.sample(pi_reset=1),0,self.rom)
        self.assertEqual(r['next_state'],f.ZERO)

    def test_q_zero_uses_same_nonzero_angle(self):
        r=f.foc_step(f.ZERO,f.sample(theta_e=16384,id_ref=32768,iq_ref=65536,uq_zero_en=1),0,self.rom)
        self.assertEqual(r['uq_lim'],0)
        self.assertEqual(r['v_alpha'],0)
        self.assertGreater(r['v_beta'],0)

    def test_downstream_error_does_not_undo_pi(self):
        with patch.object(f.c3,'svpwm_step',return_value={'error_code':2}):
            r=f.foc_step(f.ZERO,f.sample(id_ref=32768),0,self.rom)
        self.assertEqual(r['error_code'],2)
        self.assertGreater(r['next_state'][0],0)
        self.assertEqual((r['duty_u'],r['duty_v'],r['duty_w']),(0,0,0))

    def test_raw_and_physical_range_rejected(self):
        with self.assertRaises(ValueError): f.foc_step(f.ZERO,f.sample(ia=1<<23),0,self.rom)
        with self.assertRaises(ValueError): f.foc_step(f.ZERO,f.sample(),2,self.rom)
        with self.assertRaises(ValueError): f.quantize_current(1000)

if __name__=='__main__': unittest.main()
