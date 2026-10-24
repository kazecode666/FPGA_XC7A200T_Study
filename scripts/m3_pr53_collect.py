"""Collect bounded candidate evidence without replacing baseline publication."""
import csv,hashlib,json,re,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
RUN=ROOT/'.runtime/pr53_20261025'
OUT=ROOT/'docs/reports/m3_foc_hdl/pr53_pipeline_revision'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def copy(source,target):
    if not source.is_file():return
    target.parent.mkdir(parents=True,exist_ok=True)
    if target.exists():assert sha(source)==sha(target),'Preserve first evidence: '+str(target)
    else:shutil.copyfile(source,target)
def timing(p):
    if not p.is_file():return {}
    text=p.read_text()
    after=text[text.index('WNS(ns)'):]
    row=re.search(r'\n\s*(-?[\d.]+)\s+(-?[\d.]+)\s+(\d+)\s+(\d+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(\d+)\s+(\d+)',after)
    result={}
    if row:
        a=row.groups();result.update(wns_ns=a[0],tns_ns=a[1],setup_fail_endpoints=a[2],whs_ns=a[4],ths_ns=a[5],hold_fail_endpoints=a[6])
    for field,pattern in [('startpoint',r'Source:\s+([^\r\n]+)'),('endpoint',r'Destination:\s+([^\r\n]+)'),('data_path_ns',r'Data Path Delay:\s+([\d.]+)ns')]:
        m=re.search(pattern,text);result[field]=m.group(1) if m else 'unresolved'
    return result
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    rows=[]
    base=ROOT/'docs/reports/m3_foc_hdl/ooc'
    o=read(base/'ooc_result.json');t=timing(base/'timing_summary.rpt')
    rows.append({'candidate_id':'baseline_B3','configuration_sha256':read(RUN.parent/'m3_20261024_001/manifest.json')['build_identity']['configuration_sha256'],
      'manifest_sha256':o['manifest_sha256'],'ooc_manifest_sha256':o['manifest_sha256'],'reason':'immutable original-width failure','output_phase':274,'state_events':'PI5000 AW1',
      'bit_validation':'original full PASS','rtl_validation':'original full PASS','generation':'PASS',**t,
      'LUT':o['used']['LUT'],'FF':o['used']['FF'],'DSP':o['used']['DSP'],'BRAM':0,'deadline':'ideal budget only; physical NOT_PROVEN','decision':'REJECT timing'})
    for id in ['p1','p2','p3']:
        run=RUN/('p3q' if id=='p3' and (RUN/'p3q').is_dir() else id)
        if not run.is_dir():continue
        if not (run/'manifest.json').is_file() and not list(run.glob('*_generate_failure.json')):
            continue  # Never freeze files still being rewritten by makehdltb.
        dest=OUT/'candidates'/id
        copy(run/'candidate.json',dest/'candidate.json')
        copy(RUN/(id+'_matlab.log'),dest/'generation.log') if (run/'manifest.json').is_file() or list(run.glob('*_generate_failure.json')) else None
        failures=list(run.glob('*_generate_failure.json'))
        for file in failures:copy(file,dest/file.name)
        works=list(run.glob('*_generate'))
        if not works and (run/'final_build.json').is_file():works=[Path(read(run/'final_build.json')['work_dir'])]
        if works:
            work=max(works,key=lambda p:p.stat().st_mtime_ns)
            copy(work/'hdl_config_readback.json',dest/'hdl_config_readback.json')
            copy(work/'model/PMLSM_FOC_FixedPoint.slx',dest/'model/PMLSM_FOC_FixedPoint.slx')
            for n in ['gm_PMLSM_FOC_FixedPoint.slx','gm_PMLSM_FOC_FixedPoint_vnl.slx']:
                copy(work/'rtl/PMLSM_FOC_FixedPoint'/n,dest/'generated_models'/n)
            for file in ['PMLSM_FOC_FixedPoint_distributed_pipelining.html','PMLSM_FOC_FixedPoint_delay_balancing.html','FOC_DUT_report.html']:
                copy(work/'rtl/PMLSM_FOC_FixedPoint/html/pages'/file,dest/'generation_reports'/file)
        row={'candidate_id':id,'configuration_sha256':'NOT_RUN','manifest_sha256':'NOT_RUN','ooc_manifest_sha256':'NOT_RUN',
          'reason':read(run/'candidate.json')['hypothesis'],'output_phase':'NOT_RUN','state_events':'NOT_RUN',
          'bit_validation':'NOT_RUN','rtl_validation':'NOT_RUN','generation':'FAIL' if failures else 'IN_PROGRESS',
          'wns_ns':'NOT_RUN','tns_ns':'NOT_RUN','setup_fail_endpoints':'NOT_RUN','whs_ns':'NOT_RUN','ths_ns':'NOT_RUN',
          'hold_fail_endpoints':'NOT_RUN','startpoint':'NOT_RUN','endpoint':'NOT_RUN','data_path_ns':'NOT_RUN',
          'LUT':'NOT_RUN','FF':'NOT_RUN','DSP':'NOT_RUN','BRAM':'NOT_RUN','deadline':'NOT_PROVEN','decision':'REJECT generation' if failures else 'PENDING'}
        if works and (work/'hdl_config_readback.json').is_file():row['configuration_sha256']=sha(work/'hdl_config_readback.json')
        if (run/'manifest.json').is_file():
            m=read(run/'manifest.json');row.update(generation='PASS',manifest_sha256=sha(run/'manifest.json'))
            copy(run/'manifest.json',dest/'build_manifest.json');copy(run/'candidate_contract.json',dest/'candidate_contract.json')
            c=read(run/'candidate_contract.json');row.update(output_phase=c['output_phase_cycles'],state_events=json.dumps(c['state_events']))
        models=list(run.glob('model_result_*.json'))
        if models:
            file=max(models,key=lambda p:p.stat().st_mtime_ns);model=read(file)
            copy(file,dest/'model_result.json')
            for case in model['cases']:
                folder=Path(case['folder']);label=case['name']
                for name in ['case_result.json','source_hex.csv','gm_hex.csv','next_state_hex.csv','next_state_mapping.json','gm_denominator_result.json','validation_denominator_result.json']:
                    copy(folder/name,dest/'model'/label/name)
            row['bit_validation']='full '+model['status'] if model['complete_suites'] else 'directed17 '+model['cases'][0]['status']+'; full NOT_RUN'
        for name in ['rtl_probe_result.json','rtl_result.json']:
            if (run/name).is_file():
                r=read(run/name);copy(run/name,dest/name)
                row['rtl_validation']=('full ' if r.get('complete_suites',True) else 'directed17 ')+r['status']
                for entry in r['cases']:
                    folder=Path(entry['evidence']).parent;label=entry['name']+'_'+entry['mode']
                    for n in ['result.json','scoreboard.json','wrapper_exit.json','xsim.console.log']:
                        copy(folder/n,dest/'rtl'/label/n)
        synth=run/'ooc_001/synth'
        if id=='p3' and run.name=='p3q':
            original=RUN/'p3'
            a=read(original/'manifest.json');b=read(run/'manifest.json')
            assert a['design_files']==b['design_files'] and a['build_identity']==b['build_identity'],'Different hardware cannot reuse diagnostic FAIL'
            copy(run/'state_qualification.json',dest/'state_qualification.json')
            copy(original/'manifest.json',dest/'initial_state_mapping_failure/manifest.json')
            copy(original/'candidate_contract.json',dest/'initial_state_mapping_failure/candidate_contract.json')
            copy(original/'rtl_probe_result.json',dest/'initial_state_mapping_failure/rtl_probe_result.json')
            for folder in original.glob('*_run'):
                if (folder/'scoreboard.json').is_file():
                    for n in ['result.json','scoreboard.json','wrapper_exit.json','xsim.console.log']:
                        copy(folder/n,dest/'initial_state_mapping_failure'/folder.name/n)
            for n in ['ooc_result.json','timing_summary.rpt','utilization.rpt']:
                copy(original/'ooc_001/synth'/n,dest/'initial_state_mapping_failure/ooc'/n)
        if (synth/'ooc_result.json').is_file():
            o=read(synth/'ooc_result.json');row.update(timing(synth/'timing_summary.rpt'))
            row['ooc_manifest_sha256']=o['manifest_sha256']
            row.update(LUT=o['used']['LUT'],FF=o['used']['FF'],DSP=o['used']['DSP'],BRAM=o['used']['BRAM36_equivalent'])
            row['decision']='PENDING full verification' if o['timing_ok'] and o['resources_ok'] else 'REJECT timing'
            if o['timing_ok'] and o['resources_ok'] and row['bit_validation']=='full PASS' and row['rtl_validation']=='full PASS' and (run/'repro_result.json').is_file() and read(run/'repro_result.json')['status']=='PASS':
                row['decision']='KEEP full C/D/E/F PASS'
                row['deadline']='314 core +1 output budget +1 margin <=2500; external IO/routed timing NOT_PROVEN'
            for file in synth.iterdir():
                if file.suffix in ['.rpt','.json','.xdc']:copy(file,dest/'ooc'/file.name)
            copy(run/'ooc_001/result.json',dest/'ooc/wrapper_result.json')
        rows.append(row)
    keys=list(rows[0])
    with (OUT/'candidate_results.csv').open('w',newline='',encoding='utf8') as f:
        w=csv.DictWriter(f,fieldnames=keys);w.writeheader();w.writerows(rows)
    print(json.dumps(rows,ensure_ascii=False))
if __name__=='__main__':main()
