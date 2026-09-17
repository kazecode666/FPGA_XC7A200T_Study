"""Read-only equation cross-check of CSV captured from actual Simulink blocks.

This checker does NOT generate golden values and does not edit the references.
Run: python scripts/reference_audit/verify_step6a_vectors.py
"""
import csv
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
rows = list(csv.DictReader((ROOT / 'coordination/reports/step6a_pi_foc_golden_vectors.csv').open(encoding='utf-8-sig')))
max_error = 0.0
checks = 0


def check(row, name, expected, tolerance=2e-10):
    global max_error, checks
    actual = float(row[name])
    error = abs(actual - expected)
    max_error = max(max_error, error)
    checks += 1
    assert error <= tolerance, (row['parameter_profile'], row['case_id'], name, actual, expected)


profile = None
for row in rows:
    if row['parameter_profile'] != profile:
        profile = row['parameter_profile']
        xd = xq = dud = duq = sat = 0.0
    v = {k: float(value) for k, value in row.items() if k not in ('parameter_profile', 'case_id')}
    alpha = (2/3)*(v['ia']-.5*v['ib']-.5*v['ic'])
    beta = (v['ib']-v['ic'])/math.sqrt(3)
    # The installed library's resolved dlgSett uses 800 intervals despite
    # the outer reference mask saying N_points=1024; see audit section 4.
    position = (v['theta_e'] % (2*math.pi))*800/(2*math.pi)
    index = math.floor(position)
    fraction = position-index
    def interp(fn):
        return fn(index*2*math.pi/800)*(1-fraction)+fn((index+1)*2*math.pi/800)*fraction
    c, s = interp(math.cos), interp(math.sin)
    d, q = alpha*c+beta*s, beta*c-alpha*s
    ed = v['id_ref']-d
    eq = 0 if v['uq_zero_en'] > .5 else v['iq_ref']-q
    rd, rq = v['pi_reset'] > .5, bool(v['pi_reset'] or v['uq_zero_en'])
    ud = 0 if rd else v['kp']*ed+xd-v['we']*.001745*q
    uq = 0 if rq else v['kp']*eq+xq+v['we']*(.001745*d+.141)
    scale = min(1, .9*v['vdc']/math.sqrt(3)/(math.hypot(ud, uq)+1e-6))
    dl, ql = ud*scale, uq*scale
    va, vb = dl*c-ql*s, dl*s+ql*c
    for name, expected in zip(
        ['i_alpha','i_beta','id','iq','ud_raw','uq_raw','ud_lim','uq_lim','v_alpha','v_beta','du_d_z','du_q_z','sat_flag_z'],
        [alpha,beta,d,q,ud,uq,dl,ql,va,vb,dud,duq,sat]):
        check(row,name,expected)
    # Near decimal sector edges, tiny roundoff can choose an adjacent sector.
    # Exact predicates are tested whenever the signed value exceeds 1e-12;
    # use the recorded sector to verify dwell/phase permutation at ties.
    b0,b1,b2 = vb,.866*va-.5*vb,-.866*va-.5*vb
    n = int(v['sector'])
    if min(abs(b0),abs(b1),abs(b2)) > 1e-12:
        check(row,'sector',int(b0>0)+2*int(b1>=0)+4*int(b2>0))
    assert 1 <= n <= 6
    x = 1.7321*vb*1e-4/v['vdc']
    y = (.866*vb+1.5*va)*1e-4/v['vdc']
    z = (.866*vb-1.5*va)*1e-4/v['vdc']
    a,b = [(z,y),(y,-x),(-z,x),(-x,z),(x,-y),(-y,-z)][n-1]
    margin = 1e-4-a-b
    t1 = a if margin >= 0 else a*1e-4/(a+b)
    t2 = b if margin > 0 else b*1e-4/(a+b)
    check(row,'t1',t1);check(row,'t2',t2)
    low,mid,high = (1e-4-t1-t2)/4,(1e-4+t1-t2)/4,(1e-4+t1+t2)/4
    abc = [(mid,low,high),(low,high,mid),(low,mid,high),
           (high,mid,low),(high,low,mid),(mid,high,low)][n-1]
    for name,value in zip(['duty_a','duty_b','duty_c'],abc):
        check(row,name,value*200e6)
    xd = 0 if rd else xd+v['ki']*1e-4*ed-.2*dud
    xq = 0 if rq else xq+v['ki']*1e-4*eq-.2*duq
    dud,duq,sat = ud-dl,uq-ql,int(scale<.999)

assert len(rows)==160
assert {int(float(r['sector'])) for r in rows} == set(range(1,7))
print(f'PASS: {len(rows)} actual-source rows, {checks} checks, max absolute error {max_error:.3g}')
