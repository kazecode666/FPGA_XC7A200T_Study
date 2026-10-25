function result=m3_synth_stage(cfg)
% 同一校验清单的OOC预检；功能状态和资源/时序结论分别报告。
manifest=fullfile(cfg.run_dir,'manifest.json');assert(isfile(manifest),'M3:MANIFEST_MISSING');
folder=fullfile(cfg.run_dir,'ooc_001');
runner=fullfile(cfg.root,'scripts','m3_run_xsim.ps1');
command=sprintf('pwsh -NoProfile -File "%s" -Manifest "%s" -RunDir "%s" -Mode synth -Case foc_ooc',runner,manifest,folder);
file=fullfile(folder,'result.json');
consumed=false;wrapperExit=[];
if isfile(file)
    existing=jsondecode(fileread(file));
    identity=jsondecode(fileread(fullfile(folder,'synth','ooc_result.json')));
    currentHash=m3_sha256(manifest);
    assert(strcmp(existing.manifest_sha256,currentHash)&&strcmp(identity.manifest_sha256,currentHash),'M3:OOC_IDENTITY');
    data=jsondecode(fileread(manifest));
    for k=1:numel(data.design_files),e=data.design_files(k);assert(strcmp(m3_sha256(fullfile(data.root_dir,e.path)),e.sha256),'M3:OOC_SOURCE_HASH');end
    staged=jsondecode(fileread(fullfile(folder,'staged_files.json')));
    for k=1:numel(staged),assert(strcmp(m3_sha256(staged(k).path),staged(k).sha256),'M3:OOC_STAGED_HASH');end
    consumed=true;code=0;console='M3_OOC_CONSUME_EXISTING_HASH_MATCHED_EVIDENCE';
else
    [code,console]=system(command);wrapperExit=code;
end
fprintf('%s\n',console);
file=fullfile(folder,'result.json');assert(isfile(file),'M3:OOC_RESULT_MISSING','Tool exit%d; %s',code,console);
actual=jsondecode(fileread(file));
functionState='NOT_RUN';f=fullfile(cfg.run_dir,'rtl_result.json');
if isfile(f),r=jsondecode(fileread(f));functionState=r.status;end
result=struct('stage','synth','status',actual.status,'run_dir',cfg.run_dir, ...
    'evidence',{{file}},'failures',{actual.failures},'wrapper_exit_code',wrapperExit, ...
    'vivado_native_exit_code',actual.tool_exit_codes.vivado,'consumed_existing_hash_matched_evidence',consumed, ...
    'rtl_verification_status',functionState,'diagnostic_if_function_not_pass',~strcmp(functionState,'PASS'), ...
    'synthesis_completed',actual.completed,'resources_ok',actual.resources_ok,'timing_ok',actual.timing_ok, ...
    'scope','core OOC synthesis estimate; external IO and routed timing unsigned');
if code~=0,result.status='FAIL';end
file=fullfile(cfg.run_dir,'synth_result.json');assert(~isfile(file),'M3:EVIDENCE_EXISTS');
fid=fopen(file,'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
end
