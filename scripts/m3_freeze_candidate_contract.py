"""Freeze phase from HDL Coder report (never by searching golden outputs)."""
import argparse,hashlib,json,re
from pathlib import Path
from html import unescape
from m3_candidate_contract import validate

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def freeze(run):
    run=run.resolve()
    mf=run/'manifest.json';m=json.loads(mf.read_text(encoding='utf-8-sig'))
    report=Path(m['build_identity']['work_dir'])/'rtl/PMLSM_FOC_FixedPoint/html/pages/PMLSM_FOC_FixedPoint_delay_balancing.html'
    text=unescape(re.sub('<[^>]+>',' ',report.read_text(encoding='utf8')))
    text=re.sub(r'\s+',' ',text)
    phases=[]
    for name in ['duty_u_cmd','duty_v_cmd','duty_w_cmd']:
        match=re.search(r'/'+name+r'\s+(\d+)\s+(\d+)',text)
        if not match:raise ValueError('missing generated scheduled port '+name)
        phases.append(sum(map(int,match.groups())))
    if len(set(phases))!=1:raise ValueError('three-phase scheduling mismatch')
    c={'candidate_id':m['candidate_id'],'configuration_sha256':m['build_identity']['configuration_sha256'],
       'output_phase_cycles':phases[0],'frame_cycles':5000,
       'state_events':{'pi_consume':5000,'pi_commit':5000,'aw_commit':1},
       'state_mapping':{'x_d_old':'u_Id.x_d_z_out1','x_q_old':'u_Iq.x_q_z_out1',
                        'aw_d_old':'dq_voltage_limiter_du_d_z','aw_q_old':'dq_voltage_limiter_du_q_z'},
       'schedule_evidence':str(report),'schedule_sha256':sha(report),
       'state_mapping_status':'provisional from preserved algorithm state; must pass directed event checks'}
    validate(c,{'candidate_id':m['candidate_id'],'configuration_sha256':m['build_identity']['configuration_sha256']})
    target=run/'candidate_contract.json'
    with target.open('x',encoding='utf8') as f:json.dump(c,f,indent=2)
    m['candidate_contract']={'path':str(target),'sha256':sha(target),'output_phase_cycles':phases[0]}
    with (run/'manifest_before_contract.json').open('x',encoding='utf8') as f:f.write(mf.read_text(encoding='utf8'))
    mf.write_text(json.dumps(m,indent=2)+'\n',encoding='utf8')
    print('M3_CANDIDATE_CONTRACT',m['candidate_id'],phases[0],sha(target))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('run',type=Path);freeze(p.parse_args().run)
