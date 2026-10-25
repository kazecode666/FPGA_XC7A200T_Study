"""Map actual final gm state blocks to qualified RTL events; no model edits."""
import csv,json,zipfile
from pathlib import Path
import xml.etree.ElementTree as E
root=Path(__file__).resolve().parents[1];run=root/'.runtime/pr53_20261025/p3q'
build=json.loads((run/'final_build.json').read_text());gmfile=Path(build['rtl_dir'])/'PMLSM_FOC_FixedPoint/gm_PMLSM_FOC_FixedPoint.slx'
model='gm_PMLSM_FOC_FixedPoint';found={}
with zipfile.ZipFile(gmfile) as z:
    def walk(ref,parent):
        tree=E.fromstring(z.read('simulink/systems/'+ref+'.xml'))
        for b in tree.findall('Block'):
            path=parent+'/'+b.get('Name');found[path]=b
            s=b.find('System')
            if s is not None and s.get('Ref'):walk(s.get('Ref'),path)
    walk('system_root',model)
logs={x['signal']:x for x in json.loads((root/'.runtime/pr53_20261025/state_log_audit.json').read_text())}
rows=[]
for axis,source_sid,path,signal in [('d',47,'Id/x_d_z','x_d_old'),('q',78,'Iq/x_q_z','x_q_old'),
 ('awd',213,'dq_voltage_limiter/Unit Delay','aw_d_old'),('awq',214,'dq_voltage_limiter/Unit Delay1','aw_q_old')]:
    block=found[model+'/FOC_DUT/FOC_DUT/'+path]
    pi=axis in ['d','q']
    rows.append({'logical_state':signal,'source_sid':source_sid,'source_block':'FOC_DUT/'+path,
      'source_type':'sfix64_En40','initial_hex':'0000000000000000','gm_sid':block.get('SID'),
      'gm_block':'FOC_DUT/FOC_DUT/'+path,'gm_block_type':block.get('BlockType'),
      'gm_declared_sample_time':block.findtext("P[@Name='SampleTime']") or 'inherited',
      'gm_observed_log_period_s':logs[signal]['observed_log_period_s'],
      'rtl_observation':('dut.u_I'+axis+'.x_'+axis+'_z_out1') if pi else ('dut.u_dq_voltage_limiter.Unit_Delay'+('1' if axis=='awq' else '')+'_bypass_reg'),
      'rtl_D_input':('dut.u_I'+axis+'.x_'+axis+'_z_out1_1') if pi else ('dut.u_dq_voltage_limiter.Subtract'+('1' if axis=='awq' else '')+'_out1_1'),
      'old_consumed_pre_edge':5000,'commit_post_edge':1,'commit_frame':'next frame',
      'source_gm_event':'old(n) at n*100us; source next(n) equals gm old(n+1) at (n+1)*100us',
      'rtl_commit_event':'current row old at phase1; unchanged source old at consuming pre5000; every active edge still checked',
      'scope':'structural map plus directed17 stored fi log audit; full acceptance results separate'})
target=root/'docs/reports/m3_foc_hdl/pr53_pipeline_revision/state_mapping_p3.csv'
with target.open('w',encoding='utf8',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
print('M3_P3_STATE_MAP',len(rows),[(r['logical_state'],r['gm_sid'],r['gm_block_type']) for r in rows])
