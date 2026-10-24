function result=test_m3_repeat_failure(runDir)
% 真实子MATLAB因缺来源退出，父F必须拒绝，不能写PASS。
mkdir(runDir);root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
cfg=m3_foc_codegen_config(root,runDir);cfg.source_dir=fullfile(runDir,'missing_source');
fid=fopen(fullfile(runDir,'final_build.json'),'w');fprintf(fid,'%s',jsonencode(struct('matlab_process_id',matlabProcessID)));fclose(fid);
failed=false;try,m3_repro_stage(cfg);catch e,failed=strcmp(e.identifier,'M3:REPEAT_PROCESS_FAILED');end
assert(failed,'M3:CHILD_FALSE_PASS','A failing repeat child must fail the parent.');
p=jsondecode(fileread(fullfile(runDir,'repeat','repeat_process_result.json')));
assert(strcmp(p.status,'FAIL')&&p.child_exit_code~=0&&p.repeat_pid~=matlabProcessID, ...
    'M3:CHILD_FAILURE_EVIDENCE','Require actual failed child and distinct PID.');
result=struct('status','PASS','failing_child_rejected',true,'child',p);
fid=fopen(fullfile(runDir,'child_failure_test_result.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
end
