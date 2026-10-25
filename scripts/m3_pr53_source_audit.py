"""Capture latest tracked bytes and compare model members to prior frozen source."""
from pathlib import Path
import hashlib,json,subprocess,zipfile
import xml.etree.ElementTree as E
root=Path(__file__).resolve().parents[1]
out=root/'.runtime/pr53_20261025'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files=subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
state={n:sha(root/n) if (root/n).is_file() else None for n in files if n}
target=out/'tracked_before.json'
if not target.exists():target.write_text(json.dumps(state,indent=2,ensure_ascii=False),encoding='utf8')
else:
 old=json.loads(target.read_text(encoding='utf8'));changed=[n for n,h in old.items() if state.get(n)!=h]
 print('CHANGED_TRACKED_SINCE_START',json.dumps(changed,ensure_ascii=False))
 allowed={'scripts/'+n for n in ['m3_build_scoreboard.py','m3_foc_codegen_config.m','m3_generate_stage.m','m3_lock_manifest.py',
   'm3_model_stage.m','m3_publish_generated.py','m3_repeat_process.m','m3_validate_build.m','m3_verify_rtl.py']}
 allowed.update(['.gitattributes','verification/m3_foc/m3_foc_scoreboard.sv','docs/FOC_HDL_TIMING_CONTRACT.md','docs/PMLSM_FOC_HDL_GUIDE_ZH.md',
   'coordination/HANDOFF.md','coordination/reports/m3_foc_systemverilog_rtl_verification.md',
   'coordination/tasks/pr53_critical_path_pipeline_revision.md','docs/reports/m3_foc_hdl/acceptance_result.json'])
 allowed.update(['README.md','docs/reports/m3_foc_hdl/cycle_contract.json','docs/reports/m3_foc_hdl/state_mapping.csv','docs/reports/m3_foc_hdl/README.md'])
 unexpected=[n for n in changed if n not in allowed and not n.startswith('generated/m3_foc/')]
 assert not unexpected,'Unrelated tracked bytes changed: '+repr(unexpected)
 (out/'source_protection.json').write_text(json.dumps({'pass':True,'tracked_files_checked':len(old),
   'authorized_changed_files':changed,'unexpected_changes':unexpected},indent=2),encoding='utf8')
report={}
for name in ['PMLSM_FOC_FixedPoint.slx','PMLSM_PI_FOC_Float_Baseline.slx']:
 current=root/'simulink模型'/name;previous=root/'.runtime/m3_20261024_001/source'/name
 with zipfile.ZipFile(current) as c,zipfile.ZipFile(previous) as p:
  names=sorted(set(c.namelist())|set(p.namelist()))
  diff=[n for n in names if n not in c.namelist() or n not in p.namelist() or c.read(n)!=p.read(n)]
  report[name]={'current_sha256':sha(current),'previous_sha256':sha(previous),'changed_members':diff}
  semantic=[]
  for n in diff:
   if n.startswith('simulink/systems/') and n.endswith('.xml'):
    def canonical(data):
     tree=E.fromstring(data)
     for node in tree.iter():
      for child in list(node):
       if child.tag=='P' and child.get('Name') in {'Position','Points'}:node.remove(child)
     return E.tostring(tree)
    # Element text/tail only contains formatting whitespace here; normalize it.
    def normalized(data):return b''.join(canonical(data).split())
    if normalized(c.read(n))!=normalized(p.read(n)):semantic.append(n)
  report[name]['non_graphical_system_differences']=semantic
  for n in diff:
   if n.endswith('.xml'):
    dest=out/'source_diff'/name;npath=dest/n;npath.parent.mkdir(parents=True,exist_ok=True)
    npath.write_bytes(c.read(n))
print(json.dumps(report,ensure_ascii=False,indent=2))
(out/'latest_source_comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
