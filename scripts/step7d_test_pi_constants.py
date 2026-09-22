"""Lightweight PR33 source checks; does not claim Step6 dynamic acceptance."""
from pathlib import Path
import re
import sys
import step6c2_pi_reference as ref

if sys.flags.optimize:
    raise SystemExit('Run without -O/-OO: constant checks must remain enabled')

root=Path(__file__).resolve().parents[1]
text=(root/'motor_control_ip/foc/rtl/mc_pi_fxp_pkg.sv').read_text()
for name,raw,target in [('PI_KP_REAL_COMMISSIONING',146381210,8.725),
                        ('PI_KI_TS_REAL_COMMISSIONING',19881001,1.185),
                        ('PI_KP_MIL_PI_OVERRIDE',73190605,4.3625),
                        ('PI_KI_TS_MIL_PI_OVERRIDE',9940500,.5925),
                        ('PI_KAW_D_REAL_COMMISSIONING',3355443,.2),
                        ('PI_KAW_Q_REAL_COMMISSIONING',3355443,.2)]:
    actual=int(re.search(r'\b'+name+r"\s*=\s*32'sd(\d+)",text)[1])
    assert actual==raw,(name,actual,raw)
    assert abs(actual/2**24-target)<=.5/2**24
assert ref.constants()['KP']==[146381210,73190605]
assert ref.constants()['KI_TS']==[19881001,9940500]
print('STEP7D_AUM3_S4_CONSTANTS_PASS')
