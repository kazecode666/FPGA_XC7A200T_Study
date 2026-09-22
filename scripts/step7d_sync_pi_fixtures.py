"""Refresh direct profile dependencies without running any Step6 HDL suite."""
from pathlib import Path
import re
import step6c2_pi_reference as c2
import step6c4_foc_reference as c4
import step6d_foc_pwm_reference as d6

root=Path(__file__).resolve().parents[1]
# Embedded evaluator directed cases retain their explicit input/state stimuli.
path=root/'motor_control_ip/foc/tb/mc_pi_dq_eval_tb.sv'
text=path.read_text(); rows={}
pattern=r"vec\[(\d+)\]\[(\d+)\]=40'h([0-9a-f]+);"
for i,j,value in re.findall(pattern,text): rows.setdefault(int(i),{})[int(j)]=int(value,16)
def signed(n,width):
    n &= (1<<width)-1
    return n-(1<<width) if n&(1<<(width-1)) else n
updates={}
for i,row in rows.items():
    if len(row)!=20: continue
    s={key:(row[j] if key in ('pi_reset','uq_zero_en') else signed(row[j],32 if key=='we' else 25))
       for j,key in enumerate(c2.INPUTS,2)}
    state=tuple(signed(row[j],40) for j in range(10,14))+(row[14],)
    r=c2.pi_eval(state,s,row[0])
    for j,key in enumerate(('error_code','ud_raw','uq_raw','xd_next','xq_next'),15): updates[i,j]=r[key]&((1<<40)-1)
text=re.sub(pattern,lambda m:f"vec[{m[1]}][{m[2]}]=40'h{updates.get((int(m[1]),int(m[2])),int(m[3],16)):010x};",text)
path.write_text(text,encoding='utf-8')
outputs,_=c4.build_outputs()
for path,text in outputs.items(): path.write_text(text,encoding='utf-8',newline='\n')
text,_=d6.outputs(); d6.PATH.write_text(text,encoding='utf-8',newline='\n')
s=c4.sample(ia=32768,ib=-16384,ic=-16384)
r=c4.foc_step(c4.ZERO,s,0,c4.read_rom())
cmp=tuple(d6.duty_to_cmp(r['duty_'+p]) for p in 'uvw')
assert cmp==(909,1591,1591),cmp
print('CURRENT_WRAPPER_ORACLE_CMP='+str(cmp))
print('DIRECT_PROFILE_FIXTURES_REFRESHED_NOT_STEP6_ACCEPTANCE')
