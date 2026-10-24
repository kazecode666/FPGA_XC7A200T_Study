"""Join real DCP paths to source SID/hierarchy and preserve detailed representatives."""
import csv,hashlib,json,re,shutil,zipfile
from pathlib import Path
import xml.etree.ElementTree as E
root=Path(__file__).resolve().parents[1]
raw=root/'.runtime/pr53_20261025/r1_paths_02'
out=root/'docs/reports/m3_foc_hdl/pr53_pipeline_revision';out.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(root/'simulink模型/PMLSM_FOC_FixedPoint.slx') as z:
    blocks={}
    def walk(ref,parent):
        system=E.fromstring(z.read('simulink/systems/'+ref+'.xml'))
        for b in system.findall('Block'):
            name=b.attrib['Name'];p=parent+'/'+name
            blocks[b.attrib['SID']]=p
            s=b.find('System')
            if s is not None and s.get('Ref'):walk(s.get('Ref'),p)
    walk('system_root','PMLSM_FOC_FixedPoint')
(out/'sid_paths.json').write_text(json.dumps(blocks,ensure_ascii=False,indent=2),encoding='utf8')
maps={
 'limiter':('184','dq_voltage_limiter.sv','Product1_mul_temp'),
 'inverse_park':('51','InversePark.sv','dsin_mul_temp'),
 'sector_xyz':('154','XYZ_Calculate.sv','Product1_mul_temp'),
 'pi_d':('23','Id.sv','x_d_z_out1'),
 'pi_q':('52','Iq.sv','x_q_z_out1')}
rows=list(csv.DictReader((raw/'paths.csv').open()))
for r in rows:
    group=r['group'] if r['group']!='worst' else 'limiter'
    sid,sv,token=maps[group];source=root/'generated/m3_foc'/sv
    lines=source.read_text().splitlines() if source.is_file() else []
    at=next((i for i,l in enumerate(lines,1) if token in l),'unresolved')
    r.update(model_start=blocks[sid],model_start_SID=sid,model_end=blocks['134']+'/Fcn1/Defined_Quotient' if group not in ['pi_d','pi_q'] else blocks['184']+'/Sqrt',
             generated_sv=sv+':'+str(at),evidence=group+'_setup.rpt',mapping_scope='enclosing source block; exact synthesized bit uses DCP name')
with (out/'critical_path_map.csv').open('w',newline='',encoding='utf8') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
for group in maps:
    text=(raw/(group+'_setup.rpt')).read_text()
    pieces=re.split(r'(?=Slack \()',text)
    (out/(group+'_representative.rpt')).write_text(pieces[0]+pieces[1],encoding='utf8')
for name in ['hold.rpt','check_timing.rpt','dsp_registers.csv']:
    shutil.copy2(raw/name,out/name)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
baseline=root/'.runtime/m3_20261024_001'
identity={'baseline_manifest_sha256':sha(baseline/'manifest.json'),'DCP_sha256':sha(baseline/'ooc_001/synth/post_synth.dcp'),
          'source_snapshot':'first generation; current local model differs in layout only',
          'baseline_ooc_manifest_matches':json.loads((baseline/'ooc_001/synth/ooc_result.json').read_text())['manifest_sha256']==sha(baseline/'manifest.json'),
          'paths':len(rows),'classes':list(maps),'raw_reports':str(raw)}
(out/'baseline_identity.json').write_text(json.dumps(identity,indent=2),encoding='utf8')
print(json.dumps(identity))
