"""Capture latest tracked bytes and compare model members to prior frozen source."""
from pathlib import Path
import hashlib,json,subprocess,zipfile
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
report={}
for name in ['PMLSM_FOC_FixedPoint.slx','PMLSM_PI_FOC_Float_Baseline.slx']:
 current=root/'simulink模型'/name;previous=root/'.runtime/m3_20261024_001/source'/name
 with zipfile.ZipFile(current) as c,zipfile.ZipFile(previous) as p:
  names=sorted(set(c.namelist())|set(p.namelist()))
  diff=[n for n in names if n not in c.namelist() or n not in p.namelist() or c.read(n)!=p.read(n)]
  report[name]={'current_sha256':sha(current),'previous_sha256':sha(previous),'changed_members':diff}
  for n in diff:
   if n.endswith('.xml'):
    dest=out/'source_diff'/name;npath=dest/n;npath.parent.mkdir(parents=True,exist_ok=True)
    npath.write_bytes(c.read(n))
print(json.dumps(report,ensure_ascii=False,indent=2))
(out/'latest_source_comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
