function result=m2_test_foc_isolation
% 回归：当前目录是正式模型目录时，也只能加载本场景副本。
root=fileparts(fileparts(mfilename('fullpath')));oldpwd=pwd;restorepwd=onCleanup(@()cd(oldpwd));cd(fullfile(root,'simulink模型'));evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');[folder,cleanup]=m2_test_model_files;
paths=m2_bind_test_models(folder);
for name={'PMLSM_PI_FOC_Float_Baseline','PMLSM_FOC_FixedPoint'},expected=fullfile(folder,[name{1} '.slx']);actual=get_param(name{1},'FileName');assert(strcmpi(actual,expected),'M2:ISOLATION_PATH','%s 实际加载%s，应为%s。',name{1},actual,expected);end
clear cleanup;assert(strcmpi(pwd,fullfile(root,'simulink模型')));cd(oldpwd);clear restorepwd
result=struct('pass',true,'cwd_was_canonical_model_folder',true,'actual_loaded_paths',paths,'cwd_restored',true,'model_windows_opened',false);fid=fopen(fullfile(root,'docs/reports/m2_foc_fixed_point/isolation_acceptance.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);disp('M2_ISOLATION_PASS');
end
