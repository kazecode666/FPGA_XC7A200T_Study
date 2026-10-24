function result=m3_verify_session_guard(runDir)
% 在现有交互会话验证拒绝路径；函数局部变量不进入用户Base Workspace。
assert(~batchStartupOptionUsed,'M3:EXPECT_INTERACTIVE');
before=struct('cwd',pwd,'path',path,'variables',evalin('base','whos'), ...
    'models',{find_system('type','block_diagram')});
rejected=false;
try,m3_foc_hdl('generate',runDir);catch e,rejected=strcmp(e.identifier,'M3:INDEPENDENT_SESSION_REQUIRED');end
after=struct('cwd',pwd,'path',path,'variables',evalin('base','whos'), ...
    'models',{find_system('type','block_diagram')});
assert(rejected&&isequal(before,after),'M3:SESSION_GUARD','Guard must reject without changing user session.');
result=struct('status','PASS','process_id',matlabProcessID,'batch',batchStartupOptionUsed, ...
    'interactive_generation_rejected',rejected,'base_variable_metadata_path_cwd_models_unchanged',true, ...
    'loaded_model_count',numel(before.models));
file=fullfile(runDir,'interactive_guard_result.json');assert(~isfile(file),'M3:EVIDENCE_EXISTS');
fid=fopen(file,'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
end
