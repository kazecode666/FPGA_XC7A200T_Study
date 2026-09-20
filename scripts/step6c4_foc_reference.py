"""C4 composition of the accepted C1/C2/C3 integer algorithms, never RTL output.

Only raw Step 6A inputs enter the chain. PI history advances once per sample.
Historical floating-point differences are observations, not a new tolerance.
"""
import argparse
import csv
import io
import json
import math
from pathlib import Path
import random
import step6c1_fixed_transform_reference as c1
import step6c2_pi_reference as c2
import step6c3_svpwm_reference as c3

ROOT=Path(__file__).resolve().parents[1]
VECTORS=ROOT/'motor_control_ip/foc/tb/vectors/step6c4'
CSV_PATH=ROOT/'coordination/reports/step6c4_foc_fixed_vectors.csv'
ZERO=(0,0,0,0,0)
INPUTS='ia ib ic theta_e we id_ref iq_ref vdc pi_reset uq_zero_en'.split()
STATES=['xd','xq','du_d','du_q','sat']
TRANSFORMS='i_alpha i_beta sine cosine id iq'.split()
PI_FIELDS='ud_raw uq_raw ud_hi uq_hi ud_lim uq_lim scale limited sat_flag'.split()
SVPWM_FIELDS='sector overmodulated t1 t2 L M H duty_u duty_v duty_w error_code'.split()
COLUMNS=(['row_id','profile','index']+INPUTS+[x+'_old' for x in STATES]+TRANSFORMS+
         PI_FIELDS+[x+'_next' for x in STATES]+['v_alpha','v_beta']+SVPWM_FIELDS)

def require(ok,message):
    if not ok: raise ValueError(message)

def read_rom():
    rom=[int(line,16) for line in c1.ROM_PATH.read_text().splitlines()]
    require(len(rom)==4096,'accepted ROM must contain 4096 entries')
    return rom

def sample(**kw):
    s=dict(ia=0,ib=0,ic=0,theta_e=0,we=0,id_ref=0,iq_ref=0,vdc=48<<15,pi_reset=0,uq_zero_en=0)
    require(set(kw)<=set(INPUTS),'unknown input')
    s.update(kw)
    return s

def validate_sample(s):
    require(set(s)==set(INPUTS),'sample schema mismatch')
    for k,v in s.items():
        width=24 if k in ('ia','ib','ic') else 32 if k=='we' else 16 if k=='theta_e' else 1 if k in ('pi_reset','uq_zero_en') else 25
        c2.validate(v,width,k not in ('theta_e','pi_reset','uq_zero_en'),k)

def quantize_current(value):
    value=float(value)
    require(math.isfinite(value) and -(1<<23)<=value*32768<=(1<<23)-1,'physical phase current outside S24/F15')
    return c1.quantize_signed(value,15,24)

def raw_sample(row):
    s=sample(**{k:quantize_current(row[k]) for k in ('ia','ib','ic')})
    angle=float(row['theta_e']);require(math.isfinite(angle),'nonfinite angle')
    s['theta_e']=c1.radians_to_u16(angle)
    for k in ('we','id_ref','iq_ref','vdc'):
        s[k]=c2.quantize(row[k],16 if k=='we' else 15)
    for k in ('pi_reset','uq_zero_en'):
        require(float(row[k]) in (0,1),'nonboolean command')
        s[k]=int(row[k])
    validate_sample(s)
    return s

def foc_step(state,sample,profile,rom):
    validate_sample(sample);c2.validate_state(state)
    require(type(profile) is int and profile in (0,1),'invalid PI profile')
    r=dict.fromkeys(TRANSFORMS+PI_FIELDS+['v_alpha','v_beta']+SVPWM_FIELDS,0)
    r.update(old_state=state,next_state=state)
    if sample['vdc']<=0:
        r['error_code']=1
        return r
    r['i_alpha'],r['i_beta']=c1.clarke_raw(*(sample[k] for k in ('ia','ib','ic')))
    r['sine'],r['cosine']=c1.sincos_raw(sample['theta_e'],rom)
    r['id'],r['iq']=c1.park_raw(r['i_alpha'],r['i_beta'],r['sine'],r['cosine'])
    p=c2.pi_step(state,c2.sample(id_meas=r['id'],iq_meas=r['iq'],
         **{k:sample[k] for k in ('id_ref','iq_ref','we','vdc','pi_reset','uq_zero_en')}),profile)
    r.update({k:p[k] for k in PI_FIELDS})
    r['next_state']=p['next_state']
    r['error_code']=p['error_code']
    if r['error_code']: return r
    r['v_alpha'],r['v_beta']=c1.inv_park_raw(r['ud_lim'],r['uq_lim'],r['sine'],r['cosine'])
    v=c3.svpwm_step(r['v_alpha'],r['v_beta'],sample['vdc'])
    r['error_code']=v['error_code']
    if not r['error_code']: r.update({k:v[k] for k in SVPWM_FIELDS})
    # C2 has already committed. A downstream error does not roll it back.
    return r

def seeded_samples(profile):
    rng=random.Random(0x6C42026+profile)
    for n in range(256):
        d={k:rng.uniform(-5,5) for k in ('ia','ib','ic')}
        d.update(theta_e=rng.uniform(-2*math.pi,2*math.pi),we=rng.uniform(-100,100),
                 id_ref=rng.uniform(-30,30),iq_ref=rng.uniform(-30,30),vdc=(12,48,72)[n%3],
                 pi_reset=int(n in (0,128)),uq_zero_en=int(n%37==0))
        if 32<=n<96: d.update(id_ref=30,iq_ref=-30,vdc=12)
        if 96<=n<128: d.update(ia=0,ib=0,ic=0,id_ref=0,iq_ref=0,we=0,vdc=72)
        yield raw_sample(d)

def comparison_row(source,s,r,profile,index):
    out={'profile':profile,'index':index,'source_row':profile*80+index+1,'case_id':source['case_id'],**s}
    mapping={k:(k,15) for k in ('i_alpha','i_beta','id','iq','ud_lim','uq_lim','v_alpha','v_beta')}
    mapping.update(ud_raw=('ud_raw',24),uq_raw=('uq_raw',24),t1=('t1',32),t2=('t2',32),
                   duty_u=('duty_a',24),duty_v=('duty_b',24),duty_w=('duty_c',24))
    for k,(src,fraction) in mapping.items():
        original=float(source[src])/(10000 if k.startswith('duty') else .0001 if k in ('t1','t2') else 1)
        fixed=r[k]/(1<<fraction)
        out.update({k+'_source':original,k+'_fixed':fixed,k+'_error':abs(original-fixed)})
    for k,pos in (('du_d_z',2),('du_q_z',3)):
        original=float(source[k]);fixed=r['old_state'][pos]/(1<<24)
        out.update({k+'_source':original,k+'_fixed':fixed,k+'_error':abs(original-fixed)})
    # Source sat_flag_z describes OLD anti-windup state, not this sample's new flag.
    out.update(sector_source=int(source['sector']),sector_fixed=r['sector'],
               sat_old_source=int(source['sat_flag_z']),sat_old_fixed=r['old_state'][4])
    return out

def build_outputs():
    rom=read_rom()
    with c2.SOURCE.open(encoding='utf-8-sig',newline='') as f: source=list(csv.DictReader(f))
    require(len(source)==160,'source must have 160 rows')
    rows=[];comparisons=[]
    for profile,label in enumerate(c2.PROFILES):
        historical=source[profile*80:(profile+1)*80]
        require(all(x['parameter_profile']==label for x in historical),'source profile/order')
        samples=[raw_sample(x) for x in historical]+list(seeded_samples(profile))
        state=ZERO
        for index,s in enumerate(samples):
            r=foc_step(state,s,profile,rom)
            require(r['error_code']==0,f'unexpected normal-flow error profile={profile} index={index}: {r}')
            flat=dict(row_id=len(rows),profile=profile,index=index,**s,**{k:r[k] for k in TRANSFORMS+PI_FIELDS+['v_alpha','v_beta']+SVPWM_FIELDS})
            flat.update({k+'_old':v for k,v in zip(STATES,state)})
            flat.update({k+'_next':v for k,v in zip(STATES,r['next_state'])})
            rows.append(flat)
            if index<80: comparisons.append(comparison_row(historical[index],s,r,profile,index))
            state=r['next_state']
    require(len(rows)==672,'exact base count')
    text='# '+' '.join(COLUMNS)+'\n'
    text+=''.join(' '.join(f'{row[k]&((1<<64)-1):016x}' for k in COLUMNS)+'\n' for row in rows)
    buf=io.StringIO(newline='');writer=csv.DictWriter(buf,fieldnames=list(comparisons[0]),lineterminator='\n')
    writer.writeheader();writer.writerows(comparisons)
    maxima={}
    for k in comparisons[0]:
        if k.endswith('_error'):
            worst=max(comparisons,key=lambda x:x[k])
            maxima[k[:-6]]={key:worst[key] for key in ('profile','source_row','case_id')}
            maxima[k[:-6]]['absolute_error']=worst[k]
    differences={}
    for name in ('sector','sat_old'):
        differences[name]=[{k:r[k] for k in ('profile','source_row','case_id',name+'_source',name+'_fixed')}
                           for r in comparisons if r[name+'_source']!=r[name+'_fixed']]
    manifest={'schema_version':1,'columns':COLUMNS,'encoding':'16 lowercase hex digits per field, signed quantities in S64 two-complement',
              'rows':672,'profiles':2,'rows_per_profile':336,'historical_per_profile':80,'seeded_per_profile':256,
              'seeds':[0x6C42026,0x6C42027],'state_history':'zero at each profile start; sequential 80 historical + 256 seeded; commands alone reset state',
              'latency':512,'normal_sample_period':5000,'historical_maxima':maxima,'historical_differences':differences,
              'float_policy':'observations only; no inherited C3 tolerance or sector allow-list'}
    return {VECTORS/'foc_vectors.txt':text,VECTORS/'manifest.json':json.dumps(manifest,indent=2)+'\n',CSV_PATH:buf.getvalue()},manifest

def main():
    ap=argparse.ArgumentParser();group=ap.add_mutually_exclusive_group(required=True)
    group.add_argument('--generate',action='store_true');group.add_argument('--check',action='store_true')
    args=ap.parse_args();outputs,manifest=build_outputs()
    for path,expected in outputs.items():
        if args.generate: path.parent.mkdir(parents=True,exist_ok=True);path.write_text(expected,encoding='utf-8',newline='\n')
        else: require(path.read_text(encoding='utf-8')==expected,f'fixture differs: {path}')
    print('STEP6C4_REFERENCE_'+('GENERATE' if args.generate else 'CHECK')+'_PASS rows=672 profiles=2 historical=160 seeded=512')
    for k,v in manifest['historical_maxima'].items(): print('FLOAT_MAX',k,json.dumps(v))
    for k,rows in manifest['historical_differences'].items():
        print('FLOAT_DIFFERENCES',k,'count='+str(len(rows)))
        for row in rows: print(json.dumps(row))

if __name__=='__main__': main()
