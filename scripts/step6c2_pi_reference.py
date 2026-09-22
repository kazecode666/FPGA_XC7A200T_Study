"""C2 integer oracle: unbounded Python integers, math.isqrt and integer //.

No RTL algorithm is reproduced here. CLI inputs are the protected actual-source
CSV; all external physical values are quantized using Decimal ties-away.
Fixtures use fixed-width lowercase hexadecimal two's complement, even for IDs.
See generated manifest.json for ordered columns and exact bit widths/counts.
"""
import argparse
import csv
from decimal import Decimal, ROUND_FLOOR, ROUND_HALF_UP, localcontext
import io
import json
import math
from pathlib import Path
import random
import sys

if sys.flags.optimize:
    raise SystemExit('C2 rejects optimized Python: run without -O/-OO')

ROOT = Path(__file__).resolve().parents[1]
VECTOR_DIR = ROOT / 'motor_control_ip/foc/tb/vectors/step6c2'
COMPARISON = ROOT / 'coordination/reports/step6c2_pi_fixed_vectors.csv'
SOURCE = ROOT / 'coordination/reports/step6a_pi_foc_golden_vectors.csv'
SEED = 0x6C22026
OFFSETS = {'round':0x1000,'sqrt':0x2000,'divider':0x3000,
           'limiter':0x4000,'evaluator':0x5000,'core0':0x6000,'core1':0x7000}
STATE_MIN, STATE_MAX = -(1<<39),(1<<39)-1
ONE_SCALE = 1<<32
PROFILES = ['real_commissioning','MIL_PI_override']
INPUTS = ['id_meas','iq_meas','id_ref','iq_ref','we','vdc','pi_reset','uq_zero_en']
STATE_NAMES = ['xd','xq','du_d','du_q','sat']
LIMIT_FIELDS = ['error_code','ud_hi','uq_hi','du_d_next','du_q_next','ud_lim','uq_lim','scale','limited','sat_flag']


def require(condition, message):
    if not condition: raise ValueError(message)


def integer(value, name):
    require(type(value) is int, f'{name} must be an integer')
    return value


def fits_signed(value, width):
    return -(1<<(width-1)) <= value < 1<<(width-1)


def validate(value, width, signed, name):
    integer(value,name)
    require(fits_signed(value,width) if signed else 0<=value<1<<width,
            f'{name} out of {"S" if signed else "U"}{width} range: {value}')


def round_shift_away(x:int, shift:int)->int:
    integer(x,'x'); integer(shift,'shift')
    require(shift>=0,'negative shift')
    if shift==0: return x
    magnitude = (abs(x)+(1<<(shift-1))) >> shift
    return -magnitude if x<0 else magnitude


def quantize(text, fraction):
    with localcontext() as ctx:
        ctx.prec=90
        value=Decimal(str(text))
        require(value.is_finite(),'nonfinite physical input')
        return int((value*(1<<fraction)).to_integral_value(rounding=ROUND_HALF_UP))


def constants():
    with localcontext() as ctx:
        ctx.prec=90
        return {'KP':[quantize('8.725',24),quantize('4.3625',24)],
                'KI_TS':[quantize('1.185',24),quantize('0.5925',24)],
                'KAW':quantize('0.2',24),'LD':quantize('0.001745',30),
                'LQ':quantize('0.001745',30),'PSI_F':quantize('0.141',30),
                'C_UMAX':int((Decimal('0.9')/Decimal(3).sqrt()*(1<<30)).to_integral_value(rounding=ROUND_FLOOR)),
                'EPS_RAW':quantize('0.000001',24)}


C=constants()


def sample(**kwargs):
    result=dict(id_meas=0,iq_meas=0,id_ref=0,iq_ref=0,we=0,vdc=48<<15,pi_reset=0,uq_zero_en=0)
    require(set(kwargs)<=set(INPUTS),'unknown sample input')
    result.update(kwargs)
    return result


def validate_sample(s):
    require(set(s)==set(INPUTS),'sample keys do not match schema')
    for key in INPUTS:
        validate(s[key],1 if key in ('pi_reset','uq_zero_en') else 32 if key=='we' else 25,
                 key not in ('pi_reset','uq_zero_en'),key)


def validate_state(state):
    require(isinstance(state,tuple) and len(state)==5,'state must be 5-tuple')
    for name,value in zip(STATE_NAMES,state): validate(value,1 if name=='sat' else 40,name!='sat',name)


def limiter_raw(ud:int, uq:int, vdc:int)->dict:
    validate(ud,40,True,'ud'); validate(uq,40,True,'uq'); validate(vdc,25,True,'vdc')
    result=dict.fromkeys(LIMIT_FIELDS,0)
    if vdc<=0:
        result['error_code']=1
        return result
    norm_sq=ud*ud+uq*uq
    root=math.isqrt(norm_sq)
    remainder=norm_sq-root*root
    denom=root+int(remainder!=0)+C['EPS_RAW']
    umax=(vdc*C['C_UMAX'])>>21
    scale=ONE_SCALE if umax>=denom else (umax<<32)//denom
    dh=round_shift_away(ud*scale,32); qh=round_shift_away(uq*scale,32)
    dd=ud-dh; dq=uq-qh
    dl=round_shift_away(dh,9); ql=round_shift_away(qh,9)
    require(all(fits_signed(x,40) for x in (dh,qh,dd,dq)),'limiter internal S40 invariant')
    require(all(fits_signed(x,25) for x in (dl,ql)),'limiter external S25 invariant')
    result.update(ud_hi=dh,uq_hi=qh,du_d_next=dd,du_q_next=dq,ud_lim=dl,uq_lim=ql,
                  scale=scale,limited=int(scale<ONE_SCALE),sat_flag=int(1000*scale<999*ONE_SCALE),
                  norm_sq=norm_sq,root_floor=root,remainder=remainder,denom=denom,umax=umax)
    return result


def pi_eval(state, s, profile, coefficients=None):
    coeff = C if coefficients is None else coefficients
    validate_state(state); validate_sample(s)
    require(type(profile) is int and profile in (0,1),'invalid PI profile')
    result=dict(error_code=0,ud_raw=0,uq_raw=0,xd_next=state[0],xq_next=state[1])
    if s['vdc']<=0:
        result['error_code']=1
        return result
    xd,xq,dd,dq,_=state
    ed=s['id_ref']-s['id_meas']; eq=0 if s['uq_zero_en'] else s['iq_ref']-s['iq_meas']
    pd=round_shift_away(ed*coeff['KP'][profile],15); pq=round_shift_away(eq*coeff['KP'][profile],15)
    di=round_shift_away(ed*coeff['KI_TS'][profile],15); qi=round_shift_away(eq*coeff['KI_TS'][profile],15)
    da=round_shift_away(dd*C['KAW'],24); qa=round_shift_away(dq*C['KAW'],24)
    fd=round_shift_away(-s['we']*C['LQ']*s['iq_meas'],37)
    fq=round_shift_away(s['we']*(C['LD']*s['id_meas']+(C['PSI_F']<<15)),37)
    ud,uq,xn,yn=pd+xd+fd,pq+xq+fq,xd+di-da,xq+qi-qa
    if s['pi_reset']: ud=uq=xn=yn=0
    elif s['uq_zero_en']: uq=yn=0
    if not all(fits_signed(x,40) for x in (ud,uq,xn,yn)):
        result['error_code']=2
        return result
    result.update(ud_raw=ud,uq_raw=uq,xd_next=xn,xq_next=yn)
    return result


def pi_step(state:tuple[int,int,int,int,int], sample:dict, profile:int, coefficients=None)->dict:
    e=pi_eval(state,sample,profile,coefficients)
    result={**dict.fromkeys(LIMIT_FIELDS,0),'old_state':state,'next_state':state,
            'ud_raw':0,'uq_raw':0,'error_code':e['error_code']}
    result.update(du_d_next=state[2],du_q_next=state[3])
    if e['error_code']: return result
    lim=limiter_raw(e['ud_raw'],e['uq_raw'],sample['vdc'])
    result.update(lim,ud_raw=e['ud_raw'],uq_raw=e['uq_raw'])
    result['next_state']=(e['xd_next'],e['xq_next'],lim['du_d_next'],lim['du_q_next'],lim['sat_flag'])
    return result


def check_ideal(d,q,bus,result,decimal=False):
    require(result['error_code']==0,'unexpected limiter error')
    if decimal:
        with localcontext() as ctx:
            ctx.prec=90
            dv,qv,bv=Decimal(d)/(1<<24),Decimal(q)/(1<<24),Decimal(bus)/(1<<15)
            umax=Decimal('0.9')*bv/Decimal(3).sqrt()
            scale=min(Decimal(1),umax/((dv*dv+qv*qv).sqrt()+Decimal('0.000001')))
            dl,ql=Decimal(result['ud_lim'])/(1<<15),Decimal(result['uq_lim'])/(1<<15)
            error=max(abs(dl-dv*scale),abs(ql-qv*scale))
            norm=(dl*dl+ql*ql).sqrt()
            require(error<=Decimal(2)/(1<<15),'Decimal ideal component gate')
            require(norm<=umax+Decimal(1)/(1<<15),'Decimal ideal norm gate')
    else:
        dv,qv,bv=d/(1<<24),q/(1<<24),bus/(1<<15)
        umax=.9*bv/math.sqrt(3)
        scale=min(1.,umax/(math.hypot(dv,qv)+1e-6))
        dl,ql=result['ud_lim']/(1<<15),result['uq_lim']/(1<<15)
        error=max(abs(dl-dv*scale),abs(ql-qv*scale))
        norm=math.hypot(dl,ql)
        require(math.isfinite(error) and error<=2/(1<<15),'ideal component gate')
        require(norm<=umax+1/(1<<15),'ideal norm gate')
    require((d==0 and result['ud_lim']==0) or d*result['ud_lim']>=0,'d sign gate')
    require((q==0 and result['uq_lim']==0) or q*result['uq_lim']>=0,'q sign gate')
    return float(error),float(norm-umax)


def rng(name): return random.Random(SEED+OFFSETS[name])


def limiter_inputs():
    cases=[]
    for bus in (1,48<<15,(1<<24)-1,0,-1,-(1<<24)):
        for d,q in [(0,0),(1,0),(-1,0),(0,1),(0,-1),
                    (1<<24,1<<24),(-1<<24,1<<24),(1<<24,-1<<24),(-1<<24,-1<<24),
                    (STATE_MIN,STATE_MIN),(STATE_MAX,STATE_MAX),(STATE_MIN,STATE_MAX),(STATE_MAX,STATE_MIN),
                    (STATE_MIN,0),(0,STATE_MAX)]: cases.append((d,q,bus))
    for bus in (1,48<<15,(1<<24)-1):
        umax=(bus*C['C_UMAX'])>>21
        for center in (umax-17,(umax*1000)//999-17):
            for offset in (-2,-1,0,1,2):
                for sign in (-1,1): cases.append((sign*(center+offset),0,bus))
    r=rng('limiter')
    cases.extend((r.randrange(STATE_MIN,STATE_MAX+1),r.randrange(STATE_MIN,STATE_MAX+1),r.randrange(1,1<<24)) for _ in range(4096))
    return cases


def replay_actual():
    # Step6A reports are immutable historical evidence with the old profile0.
    # Only this historical comparison uses old coefficients; current fixtures
    # below replay the same inputs with current coefficients and fresh state.
    historical={**C,'KP':[36595302,73190605],'KI_TS':[4970250,9940500]}
    with SOURCE.open(encoding='utf-8-sig',newline='') as f: source=list(csv.DictReader(f))
    require(len(source)==160,'golden count must equal 160')
    names=['ud_raw','uq_raw','ud_lim','uq_lim','du_d_z','du_q_z']
    maxima={name:{'error':-1} for name in names}
    histories=[]; mismatches=[]; counts=[]; source_ranges={}
    relevant=['id','iq','id_ref','iq_ref','we','vdc','pi_reset','uq_zero_en',*names,'sat_flag_z']
    for name in relevant:
        values=[Decimal(row[name]) for row in source]
        source_ranges[name]={'min':str(min(values)),'max':str(max(values))}
    for profile,label in enumerate(PROFILES):
        rows=source[80*profile:80*(profile+1)]
        require(all(row['parameter_profile']==label for row in rows),'golden profile/order mismatch')
        counts.append(len(rows)); state=(0,0,0,0,0); old_real_scale=1.; old_fixed_scale=ONE_SCALE
        for idx,row in enumerate(rows):
            require(Decimal(row['time_s'])==Decimal(idx)/10000,'golden time/order mismatch')
            s={key:quantize(row['id' if key=='id_meas' else 'iq' if key=='iq_meas' else key],
                           0 if key in ('pi_reset','uq_zero_en') else 16 if key=='we' else 15) for key in INPUTS}
            for key in ('pi_reset','uq_zero_en'): require(Decimal(row[key]) in (0,1),'nonboolean source command')
            r=pi_step(state,s,profile,historical); require(r['error_code']==0,'golden must succeed')
            out={'profile':profile,'parameter_profile':label,'row':idx+1,'source_row':profile*80+idx+1,
                 'case_id':row['case_id'],'time_s':row['time_s'],**s}
            for key,value in zip(STATE_NAMES,state): out[key+'_old_raw']=value
            for key,value in zip(STATE_NAMES,r['next_state']): out[key+'_next_raw']=value
            for key in ('ud_raw','uq_raw','ud_hi','uq_hi','ud_lim','uq_lim','scale','limited','sat_flag'): out['fixed_'+key+'_integer']=r[key]
            vals=[r['ud_raw']/(1<<24),r['uq_raw']/(1<<24),r['ud_lim']/(1<<15),r['uq_lim']/(1<<15),state[2]/(1<<24),state[3]/(1<<24)]
            for name,value in zip(names,vals):
                reference=float(row[name]); error=abs(value-reference)
                out[name+'_reference']=row[name]; out[name+'_fixed']=format(value,'.17g'); out[name+'_abs_error']=format(error,'.17g')
                if error>maxima[name]['error']: maxima[name]={'error':error,'profile':profile,'row':idx+1,'case_id':row['case_id']}
                require(error<=.002,f'Step6A gate {label} row {idx+1} {name}: {error}')
            real_scale=min(1.,.9*float(row['vdc'])/math.sqrt(3)/(math.hypot(float(row['ud_raw']),float(row['uq_raw']))+1e-6))
            out.update(real_scale=format(real_scale,'.17g'),old_real_scale=format(old_real_scale,'.17g'),
                       old_fixed_scale=old_fixed_scale,reference_sat_old=int(row['sat_flag_z']))
            comparisons=[('old',state[4],int(row['sat_flag_z']),old_fixed_scale,old_real_scale),
                         ('current',r['sat_flag'],int(real_scale<.999),r['scale'],real_scale)]
            for when,fixed,real,fs,rs in comparisons:
                if fixed!=real:
                    mismatches.append({'profile':profile,'row':idx+1,'when':when,'fixed_flag':fixed,'real_flag':real,'fixed_scale':fs/ONE_SCALE,'real_scale':rs})
                    require(abs(rs-.999)<=1e-4,'sat mismatch outside allowed threshold neighborhood')
            histories.append(out); state=r['next_state']; old_real_scale=real_scale; old_fixed_scale=r['scale']
    return histories,{'profile_counts':counts,'maxima':maxima,'sat_flag_mismatches':mismatches,'source_ranges':source_ranges,
                     'reset_rows':{p:[i+1 for i,r in enumerate(source[j*80:(j+1)*80]) if r['pi_reset']=='1'] for j,p in enumerate(PROFILES)},
                     'uq_zero_rows':{p:[i+1 for i,r in enumerate(source[j*80:(j+1)*80]) if r['uq_zero_en']=='1'] for j,p in enumerate(PROFILES)}}


def column(name,width,signed=False): return {'name':name,'width':width,'signed':signed}


INPUT_SCHEMA=[column(k,1 if k in ('pi_reset','uq_zero_en') else 32 if k=='we' else 25,k not in ('pi_reset','uq_zero_en')) for k in INPUTS]
OLD_SCHEMA=[column('old_'+k,1 if k=='sat' else 40,k!='sat') for k in STATE_NAMES]
NEXT_SCHEMA=[column('next_'+k,1 if k=='sat' else 40,k!='sat') for k in STATE_NAMES]
LIMIT_SCHEMA=[column(k,2 if k=='error_code' else 33 if k=='scale' else 1 if k in ('limited','sat_flag') else 25 if k in ('ud_lim','uq_lim') else 40,k not in ('error_code','scale','limited','sat_flag')) for k in LIMIT_FIELDS]
CORE_SCHEMA=[column('profile',1),column('sequence_id',16),column('transaction_id',32),column('reset_before',1),*INPUT_SCHEMA,*OLD_SCHEMA,
             column('ud_raw',40,True),column('uq_raw',40,True),*LIMIT_SCHEMA,*NEXT_SCHEMA]


def core_row(profile,sequence,transaction,reset,s,state):
    result=pi_step(state,s,profile)
    row=[profile,sequence,transaction,reset,*[s[k] for k in INPUTS],*state,
         result['ud_raw'],result['uq_raw'],*[result[k] for k in LIMIT_FIELDS],*result['next_state']]
    return row,result


def fixture_text(schema,rows):
    lines=['# '+' '.join(c['name'] for c in schema)]
    for row in rows:
        require(len(row)==len(schema),'fixture column count')
        tokens=[]
        for c,value in zip(schema,row):
            validate(value,c['width'],c['signed'],c['name'])
            tokens.append(format(value&((1<<c['width'])-1),f'0{(c["width"]+3)//4}x'))
        lines.append(' '.join(tokens))
    return '\n'.join(lines)+'\n'


def build_artifacts():
    artifacts={}; manifest={'version':1,'master_seed':SEED,'master_seed_hex':hex(SEED),'stream_offsets':OFFSETS,
                           'encoding':'fixed-width lowercase hexadecimal; signed columns are exact-width two\u2019s complement; whitespace-separated; one # header; no blank rows',
                           'constants':C,'fixtures':{},'source':'coordination/reports/step6a_pi_foc_golden_vectors.csv',
                           'seeded_case_counts':{'round_full_s96':1024,'sqrt_full_u80':2048,'divider_full_u72_u41':2048,
                                                 'limiter_full_s40_positive_s25_bus':4096,'evaluator_per_profile':512,'core_success_per_profile':1024},
                           'core_sequences':{'0':'actual golden, 80 contiguous rows/profile','1':'1024 successful seeded transactions/profile; reset only first row',
                                             '2':'128 errors/profile following one successful state-establishing saturation transaction; hold old state on every error'}}
    def add(name,schema,rows):
        artifacts[VECTOR_DIR/name]=fixture_text(schema,rows)
        manifest['fixtures'][name]={'rows':len(rows),'columns':schema}
    round_cases=[(-8060928,16), (32768,16),(-32768,16),(-(1<<95),16),(0,0),(-7,0)]
    for shift in (1,9,15,16,24,30,32,37,95):
        for sign in (-1,1):
            for n in ((1<<(shift-1))-1,1<<(shift-1),(1<<(shift-1))+1,1<<shift):
                if fits_signed(sign*n,96): round_cases.append((sign*n,shift))
    rr=rng('round'); round_cases.extend((rr.randrange(-(1<<95),1<<95),rr.randrange(96)) for _ in range(1024))
    add('round_vectors.txt',[column('id',32),column('x',96,True),column('shift',8),column('expected',96,True)],
        [[i,x,n,round_shift_away(x,n)] for i,(x,n) in enumerate(round_cases)])
    rails=[0,-(1<<24)-1,-(1<<24),(1<<24)-1,1<<24,STATE_MIN-1,STATE_MIN,STATE_MAX,STATE_MAX+1]
    add('range_vectors.txt',[column('id',32),column('x',96,True),column('s25',1),column('s40',1)],
        [[i,x,int(fits_signed(x,25)),int(fits_signed(x,40))] for i,x in enumerate(rails)])
    roots=[0,1,2,3,4,(1<<80)-1]
    for root in (1,2,3,(1<<20)-1,1<<20,(1<<39)-1,1<<39,(1<<40)-1):
        roots.extend(root*root+delta for delta in (-1,0,1) if 0<=root*root+delta<1<<80)
    rr=rng('sqrt'); roots.extend(rr.getrandbits(80) for _ in range(2048))
    add('sqrt_vectors.txt',[column('id',32),column('radicand',80),column('root',40),column('remainder',41)],
        [[i,n,math.isqrt(n),n-math.isqrt(n)**2] for i,n in enumerate(roots)])
    divs=[(0,0),(0,1),(1,0),(1,1),(5,9),(99,9),(100,9),((1<<72)-1,1),((1<<72)-1,(1<<41)-1),((1<<72)-1,0)]
    rr=rng('divider'); divs.extend((rr.getrandbits(72),rr.getrandbits(41)) for _ in range(2048))
    add('divider_vectors.txt',[column('id',32),column('numerator',72),column('denominator',41),column('quotient',72),column('remainder',41),column('div_by_zero',1)],
        [[i,n,d,n//d if d else 0,n%d if d else 0,int(d==0)] for i,(n,d) in enumerate(divs)])
    limiter_rows=[]; ideal_max=[0.,-1e99]; decimal_count=0
    for i,(d,q,bus) in enumerate(limiter_inputs()):
        r=limiter_raw(d,q,bus)
        if bus>0:
            metrics=check_ideal(d,q,bus,r)
            ideal_max=[max(a,b) for a,b in zip(ideal_max,metrics)]
            if i<150: check_ideal(d,q,bus,r,decimal=True); decimal_count+=1
        limiter_rows.append([i,d,q,bus,*[r[k] for k in LIMIT_FIELDS]])
    add('limiter_vectors.txt',[column('id',32),column('ud_raw',40,True),column('uq_raw',40,True),column('vdc',25,True),*LIMIT_SCHEMA],limiter_rows)
    manifest['ideal_limiter']={'max_component_error_v':ideal_max[0],'max_norm_excess_v':ideal_max[1],'decimal_directed_cases':decimal_count,
                               'double_note':'All raw physical magnitudes <=32768 V; double ulp < 1e-11 V, far below F15 bounds. Directed threshold/rail cases also checked with 90-digit Decimal.'}
    history,summary=replay_actual(); manifest['actual_replay']=summary
    output=io.StringIO(newline=''); writer=csv.DictWriter(output,fieldnames=list(history[0])); writer.writeheader(); writer.writerows(history)
    artifacts[COMPARISON]=output.getvalue()
    golden=[]
    for row in history:
        s={k:row[k] for k in INPUTS}
        if row['row']==1: state=(0,0,0,0,0)
        data,current=core_row(row['profile'],0,row['row']-1,int(row['row']==1),s,state)
        golden.append(data); state=current['next_state']
    add('golden_core_vectors.txt',CORE_SCHEMA,golden)
    seeded=[]; errors=[]; evals=[]
    for p in (0,1):
        rr=rng('core'+str(p)); state=(0,0,0,0,0)
        for i in range(1024):
            phase=i%256
            refs=(80,-60) if phase<64 else (-80,60) if phase<128 else (0,0) if phase<192 else (rr.randrange(-20,21),rr.randrange(-20,21))
            s=sample(id_meas=rr.randrange(-5<<15,5<<15),iq_meas=rr.randrange(-5<<15,5<<15),
                     id_ref=refs[0]<<15,iq_ref=refs[1]<<15,we=rr.randrange(-100<<16,100<<16),
                     vdc=[1,12<<15,48<<15,(1<<24)-1][(i//32)%4],pi_reset=int(i%251==250),uq_zero_en=int(i%71==70))
            data,r=core_row(p,1,i,int(i==0),s,state)
            require(r['error_code']==0,'seeded success stream has error'); seeded.append(data); state=r['next_state']
        state=(0,0,0,0,0)
        data,r=core_row(p,2,0,1,sample(id_ref=30<<15,iq_ref=-20<<15),state); errors.append(data); state=r['next_state']
        for i in range(128):
            s=sample(vdc=0 if i%4==0 else -1,pi_reset=(i//2)%2) if i%2==0 else sample(id_meas=(1<<24)-1,iq_meas=-(1<<24),we=(1<<31)-1,id_ref=-(1<<24),iq_ref=(1<<24)-1)
            data,r=core_row(p,2,i+1,0,s,state)
            require(r['error_code'] in (1,2),'error stream accepted successful request')
            require(r['next_state']==state,'error stream state changed'); errors.append(data)
        er=rng('evaluator')
        directed=[((0,0,0,0,0),sample(id_ref=32768)),((0,0,0,0,0),sample(id_ref=1)),
                  ((STATE_MAX,0,0,0,0),sample(id_ref=32768)),((STATE_MAX,0,0,0,0),sample(id_ref=32768,pi_reset=1)),
                  ((123,456,789,-987,1),sample(uq_zero_en=1,iq_meas=32768,we=65536)),
                  ((STATE_MIN,STATE_MAX,STATE_MAX,STATE_MIN,1),sample(pi_reset=1)),
                  ((0,1<<38,0,0,0),sample(id_meas=(1<<24)-1,id_ref=(1<<24)-1,we=-(1<<31))),
                  ((0,0,0,0,0),sample(id_meas=-(1<<24),id_ref=(1<<24)-1,iq_meas=(1<<24)-1,iq_ref=-(1<<24))),
                  ((STATE_MAX,0,0,0,0),sample(id_meas=(1<<24)-1,we=-(1<<31),iq_meas=(1<<24)-1,pi_reset=1,vdc=0))]
        for _ in range(512):
            st=tuple(er.randrange(STATE_MIN,STATE_MAX+1) for _ in range(4))+(er.randrange(2),)
            s=sample(**{k:er.randrange(-(1<<31),1<<31) if k=='we' else er.randrange(2) if k in ('pi_reset','uq_zero_en') else er.randrange(-(1<<24),1<<24) for k in INPUTS})
            directed.append((st,s))
        for i,(st,s) in enumerate(directed):
            e=pi_eval(st,s,p)
            evals.append([p,i,*[s[k] for k in INPUTS],*st,*[e[k] for k in ('error_code','ud_raw','uq_raw','xd_next','xq_next')]])
    add('seeded_core_vectors.txt',CORE_SCHEMA,seeded); add('error_core_vectors.txt',CORE_SCHEMA,errors)
    add('evaluator_vectors.txt',[column('profile',1),column('id',32),*INPUT_SCHEMA,*OLD_SCHEMA,column('error_code',2),
                         *[column(k,40,True) for k in ('ud_raw','uq_raw','xd_next','xq_next')]],evals)
    manifest['core_counts_per_profile']={'golden':80,'seeded_success':1024,'error_sequence_success_preamble':1,'accepted_errors':128}
    artifacts[VECTOR_DIR/'manifest.json']=json.dumps(manifest,indent=2,sort_keys=True)+'\n'
    return artifacts,manifest


def check_artifacts(artifacts):
    expected={p.name for p in artifacts if p.parent==VECTOR_DIR}
    actual={p.relative_to(VECTOR_DIR).as_posix() for p in VECTOR_DIR.rglob('*') if p.is_file()} if VECTOR_DIR.exists() else set()
    require(actual==expected,f'fixture inventory differs: missing={sorted(expected-actual)}, extra={sorted(actual-expected)}')
    for path,expected_text in artifacts.items():
        require(path.is_file(),f'missing artifact: {path}')
        require(path.read_text(encoding='utf-8')==expected_text.replace('\r\n','\n'),f'content mismatch: {path}')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--generate',action='store_true'); group.add_argument('--check',action='store_true')
    args=parser.parse_args()
    artifacts,manifest=build_artifacts()
    if args.generate:
        for path,content in artifacts.items():
            path.parent.mkdir(parents=True,exist_ok=True)
            with path.open('w',encoding='utf-8',newline='') as stream: stream.write(content.replace('\r\n','\n'))
    else: check_artifacts(artifacts)
    print('C2_ORACLE_PASS: '+('generated' if args.generate else 'checked')+' '+str(len(artifacts))+' artifacts')
    print(json.dumps({'counts':{k:v['rows'] for k,v in manifest['fixtures'].items()},'actual_replay':manifest['actual_replay'],
                      'ideal_limiter':manifest['ideal_limiter']},indent=2,sort_keys=True))


if __name__=='__main__': main()
