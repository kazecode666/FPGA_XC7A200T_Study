function result=m2_check_common_sign_default
% Regression: ordinary test factory must still copy the canonical endogenous model.
root=fileparts(fileparts(mfilename('fullpath')));
canonical=fullfile(root,'simulink模型');
[folder,cleanup]=m2_test_model_files; %#ok<NASGU>
manifest=jsondecode(fileread(fullfile(folder,'provenance.json')));
assert(strcmp(manifest.source_folder,canonical));
paths=m2_bind_test_models(folder);
for sid=[822 837 852]
    block=Simulink.ID.getFullName(sprintf('PMLSM_PI_FOC_Float_Baseline:%d',sid));
    p=get_param(block,'PortHandles');line=get_param(p.Inport(1),'Line');
    source=get_param(line,'SrcBlockHandle');
    assert(strcmp(get_param(source,'BlockType'),'Signum'));
end
rejected=false;
try
    m2_test_model_files(canonical);
catch exception
    assert(strcmp(exception.identifier,'M2:DIAGNOSTIC_TEMPLATE_ONLY'));
    rejected=true;
end
assert(rejected);
result=struct('pass',true,'default_source_is_canonical',true, ...
    'default_three_phase_signs_endogenous',true,'unmarked_override_rejected',true, ...
    'actual_paths',paths,'model_windows_opened',false);
file=fullfile(root,'docs/reports/m2_foc_fixed_point/common_sign_diagnostic/default_isolation.json');
fid=fopen(file,'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
disp('COMMON_SIGN_DEFAULT_ISOLATION_PASS');
end
