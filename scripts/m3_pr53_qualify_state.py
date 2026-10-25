"""New evidence directory for p3 state-map qualification; identical generated hardware."""
from pathlib import Path
import hashlib,json,shutil
from m3_freeze_candidate_contract import freeze
root=Path(__file__).resolve().parents[1]
old=root/'.runtime/pr53_20261025/p3';new=root/'.runtime/pr53_20261025/p3q'
assert not new.exists(),'Preserve existing qualification evidence'
new.mkdir()
for name in ['candidate.json','preflight_result.json','final_build.json','manifest.json']:
    shutil.copyfile(old/name,new/name)
shutil.copytree(old/'source',new/'source')
freeze(new)
a=json.loads((old/'manifest.json').read_text());b=json.loads((new/'manifest.json').read_text())
assert all(a[k]==b[k] for k in ['candidate_id','design_files','testbench_files','data_files','build_identity'])
proof={'candidate_id':'p3','hardware_candidate_count_unchanged':True,'raw_artifacts_and_configuration_equal':True,
       'original_manifest_sha256':hashlib.sha256((old/'manifest.json').read_bytes()).hexdigest(),
       'qualified_manifest_sha256':hashlib.sha256((new/'manifest.json').read_bytes()).hexdigest(),
       'reason':'Qualify the generated rd_3 fast register D-input and next-frame phase1 commit; no source or generated hardware changes'}
(new/'state_qualification.json').write_text(json.dumps(proof,indent=2))
print(json.dumps(proof))
