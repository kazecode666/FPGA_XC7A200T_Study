function study_l1_audit_runtime
% Read the saved original in a separate process. Never save or simulate it.
study=fileparts(fileparts(mfilename('fullpath'))); root=fileparts(fileparts(study));
source=fullfile(root,'simulink模型'); oldpwd=pwd; cd(source);
cleanup=onCleanup(@()cd(oldpwd)); %#ok<NASGU>
addpath(source); addpath(fullfile(root,'scripts'));
assert(strcmp(version('-release'),'2026b'));
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m));
load_system(fullfile(source,[m '.slx']));
cl=onCleanup(@()close_system(m,0)); %#ok<NASGU>
mw=get_param(m,'ModelWorkspace'); p=study_l1_init;
f=fopen(fullfile(study,'reports/checkpoint_a/runtime_audit.txt'),'w');
cf=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'MATLAB=%s\nSOURCE=%s\nORIGINAL_MODEL_SAVED=0\n',version,get_param(m,'FileName'));
for field=string(fieldnames(p))'
    actual=mw.evalin(char(field));
    assert(isequal(actual,p.(field)),'StudyL1:AsFoundMismatch','Unexpected runtime value %s',field);
    fprintf(f,'%s=%.17g\n',field,actual);
end
for sid=[505 785 767 1122 1128 1228 1166 740 759 760 1167]
    b=Simulink.ID.getFullName(sprintf('%s:%d',m,sid));
    fprintf(f,'SID=%d PATH=%s\n',sid,b);
    params=get_param(b,'ObjectParameters');
    for field={'BlockType','SampleTime','TriggerType','InitialCondition','StatesWhenEnabling','OutputWhenDisabled','Commented','const','relop'}
        if isfield(params,field{1})
            fprintf(f,'  %s=%s\n',field{1},string(get_param(b,field{1})));
        end
    end
end
fprintf(f,'SOURCE_LOADED_AND_PARAMETERS_AUDITED_PASS\n');
disp('SOURCE_LOADED_AND_PARAMETERS_AUDITED_PASS');
end
