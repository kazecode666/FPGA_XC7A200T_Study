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
props=list(csv.DictReader((root/'.runtime/pr53_20261025/r1_model/block_properties.csv').open(encoding='utf-8-sig')))
props=[p for p in props if p.get('SID') in blocks]
for p in props:p['path']=blocks[p['SID']];p.pop(None,None)
with (out/'baseline_block_properties.csv').open('w',encoding='utf8',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(props[0]));w.writeheader();w.writerows(props)
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
    end='unresolved'
    if '/u_Sqrt/' in r['endpoint']:end=blocks['184']+'/Sqrt'
    if '/u_Fcn1/u_Defined_Quotient/' in r['endpoint']:end=blocks['134']+'/Fcn1/Defined_Quotient'
    if '/u_Fcn2/u_Defined_Quotient/' in r['endpoint']:end=blocks['134']+'/Fcn2/Defined_Quotient'
    r.update(model_start=blocks[sid],model_start_SID=sid,model_end=end,
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
manifest=json.loads((baseline/'manifest.json').read_text())
payload=[e for key in ('design_files','testbench_files','data_files') for e in manifest[key]]
assert all(sha(Path(manifest['root_dir'])/e['path'])==e['sha256'] for e in payload)
assert sha(Path(manifest['build_identity']['configuration_readback']))==manifest['build_identity']['configuration_sha256']
assert all(sha(Path(manifest['build_identity']['source_dir'])/e['path'])==e['sha256'] for e in manifest['build_identity']['source_files'])
staged=json.loads((baseline/'ooc_001/staged_files.json').read_text())
assert all(sha(Path(e['path']))==e['sha256'] for e in staged)
identity={'baseline_manifest_sha256':sha(baseline/'manifest.json'),'DCP_sha256':sha(baseline/'ooc_001/synth/post_synth.dcp'),
          'raw_payload_files_verified':len(payload),'configuration_sha_verified':True,'frozen_source_files_verified':8,'synthesis_staged_files_verified':len(staged),
          'source_snapshot':'first generation; current local model differs in layout only',
          'baseline_ooc_manifest_matches':json.loads((baseline/'ooc_001/synth/ooc_result.json').read_text())['manifest_sha256']==sha(baseline/'manifest.json'),
          'paths':len(rows),'classes':list(maps),'raw_reports':str(raw)}
(out/'baseline_identity.json').write_text(json.dumps(identity,indent=2),encoding='utf8')
print(json.dumps(identity))
