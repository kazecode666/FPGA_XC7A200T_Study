"""Step 6D polarity boundary, using accepted C4/C3 algorithms without edits."""
import argparse
import csv
import math
from pathlib import Path
import step6c4_foc_reference as c4

ROOT=Path(__file__).resolve().parents[1]
PATH=ROOT/'motor_control_ip/integration/tb/vectors/step6d_pwm_vectors.txt'
ONE=1<<24
COLUMNS='kind profile index ia ib ic theta_e we id_ref iq_ref vdc pi_reset uq_zero_en foc_u foc_v foc_w cmp_u cmp_v cmp_w v_alpha v_beta sector'.split()

def duty_to_cmp(raw):
    if type(raw) is not int or not -(1<<25)<=raw<(1<<25):
        raise ValueError('expected signed S26/F24 raw duty')
    high=min(ONE,max(0,ONE-raw))
    return (high*2500+(1<<23))>>24

def row(kind,profile,index,s,r):
    d=dict(kind=kind,profile=profile,index=index,**s)
    for phase,old in zip('uvw',('duty_u','duty_v','duty_w')):
        d['foc_'+phase]=r[old];d['cmp_'+phase]=duty_to_cmp(r[old])
    d.update(v_alpha=r['v_alpha'],v_beta=r['v_beta'],sector=r['sector'])
    return d

def demo_samples():
    # 24 finite examples; all external values remain stable between requests.
    for n in range(24):
        s=c4.sample()
        if n<4: s['pi_reset']=1
        elif n==4: s['pi_reset']=1
        elif n<8: s.update(ia=32768,ib=-16384,ic=-16384)
        elif n==8: s['pi_reset']=1
        elif n<12: s.update(iq_ref=32768,theta_e=8192)
        elif n==12: s['pi_reset']=1
        else: s.update(id_ref=2*32768 if n<18 else -32768,iq_ref=32768,theta_e=4096)
        yield s

def outputs():
    for raw,expected in ((ONE,0),(3*ONE//4,625),(ONE//2,1250),(ONE//4,1875),(0,2500),(-1,2500),(ONE+1,0)):
        assert duty_to_cmp(raw)==expected
    assert tuple(map(duty_to_cmp,(8960408,7816808,7816808)))==(1165,1335,1335)
    # Exact half ties: high_raw=2^20 gives 156.25; high_raw=2^21 gives 312.5.
    assert duty_to_cmp(ONE-(1<<21))==313
    rom=c4.read_rom();rows=[]
    source=list(csv.DictReader(c4.c2.SOURCE.open(encoding='utf-8-sig')))
    assert len(source)==160
    for profile in (0,1):
        state=c4.ZERO
        for i,src in enumerate(source[profile*80:(profile+1)*80]):
            assert src['parameter_profile']==c4.c2.PROFILES[profile]
            s=c4.raw_sample(src);r=c4.foc_step(state,s,profile,rom)
            assert r['error_code']==0
            rows.append(row(0,profile,i,s,r));state=r['next_state']
        # Explicit tail sample allows observation of the final base active cycle.
        s=c4.sample(pi_reset=1);r=c4.foc_step(state,s,profile,rom)
        rows.append(row(1,profile,80,s,r))
    sectors=set();worst=0
    points=((1,0),(-1,0),(0,1),(0,-1),(0,2),(2,-1),(2,1),(-2,-1),(-2,1),(0,-2))
    for i,(a,b) in enumerate(points):
        r=c4.c3.svpwm_step(a<<15,b<<15,48<<15)
        assert not r['error_code'];r.update(v_alpha=a<<15,v_beta=b<<15)
        d=row(2,0,i,c4.sample(),r);rows.append(d);sectors.add(r['sector'])
        u,v,w=(d['cmp_'+p]/2500 for p in 'uvw')
        aa=48/3*(2*u-v-w);bb=48/math.sqrt(3)*(v-w)
        worst=max(worst,abs(aa-a),abs(bb-b))
        assert abs(aa-a)<=.0202 and abs(bb-b)<=.0202
        assert a==0 or a*aa>0
        assert b==0 or b*bb>0
    assert sectors==set(range(1,7))
    state=c4.ZERO
    for i,s in enumerate([*demo_samples(),c4.sample(pi_reset=1)]):
        r=c4.foc_step(state,s,0,rom);assert not r['error_code']
        rows.append(row(3,0,i,s,r));state=r['next_state']
    assert len(rows)==197
    text='# '+' '.join(COLUMNS)+'\n'
    text+=''.join(' '.join(f'{r[k]&((1<<64)-1):016x}' for k in COLUMNS)+'\n' for r in rows)
    return text,worst

if __name__=='__main__':
    p=argparse.ArgumentParser();g=p.add_mutually_exclusive_group(required=True)
    g.add_argument('--generate',action='store_true');g.add_argument('--check',action='store_true')
    a=p.parse_args();text,worst=outputs()
    if a.generate:
        PATH.parent.mkdir(parents=True,exist_ok=True);PATH.write_text(text,encoding='utf-8',newline='\n')
    elif PATH.read_text(encoding='utf-8')!=text: raise ValueError('Step 6D fixture mismatch')
    print('STEP6D_REFERENCE_PASS rows=197 historical=160 tail=2 direction=10 demo=24 demo_tail=1')
    print(f'DIRECTION_PASS sectors=6 max_voltage_error={worst:.12g} limit=0.0202 V')
