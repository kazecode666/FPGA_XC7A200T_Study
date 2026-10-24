function result=m2_test_foc_interface_cleanup
% One deliberate exception; no user models are closed or saved.
root=fileparts(fileparts(mfilename('fullpath')));
folder=fullfile(root,'docs/reports/m2_foc_fixed_point/pr51_revision');
if ~isfolder(folder),mkdir(folder);end
reference=sprintf('M2_Source_%d',matlabProcessID);
sentinel=sprintf('M2_Cleanup_Sentinel_%d',matlabProcessID);
assert(~bdIsLoaded(reference)&&~bdIsLoaded(sentinel));
new_system(sentinel);sentinelCleanup=onCleanup(@()close_owned(sentinel)); %#ok<NASGU>
set_param(sentinel,'Description','owned unsaved sentinel: keep during interface exception');
before=get_param(sentinel,'Dirty');caught=false;
try
    m2_test_foc_interface(@inject);
catch exception
    assert(strcmp(exception.identifier,'M2:INJECTED_INTERFACE_FAILURE'), ...
        'M2:UNEXPECTED_FAILURE','Unexpected failure: %s',exception.message);
    caught=true;
end
assert(caught&&~bdIsLoaded(reference),'M2:SOURCE_LEAK','Owned reference leaked.');
assert(bdIsLoaded(sentinel)&&strcmp(get_param(sentinel,'Dirty'),before));
assert(strcmp(get_param(sentinel,'Description'), ...
    'owned unsaved sentinel: keep during interface exception'));
% Same process can create and use the exact name the next unit stage needs.
[modelFolder,modelCleanup]=m2_test_model_files; %#ok<NASGU>
reference=m2_make_source_reference(modelFolder);
sourceCleanup=onCleanup(@()close_owned(reference)); %#ok<NASGU>
u=zeros(5,9);u(:,9)=48;u(1,8)=1;
out=m2_run_foc_sequence(reference,u,false);
assert(all(isfinite(out.logsout.get('duty_u').Values.Data)));
result=struct('pass',true,'injected_identifier','M2:INJECTED_INTERFACE_FAILURE', ...
    'reference_closed_after_exception',true,'same_process_name_reused',true, ...
    'following_reference_simulated_samples',5,'unsaved_sentinel_preserved',true, ...
    'closed_all_models',false,'process',matlabProcessID);
fid=fopen(fullfile(folder,'interface_cleanup.json'),'w');
fprintf(fid,'%s\n',jsonencode(result,PrettyPrint=true));fclose(fid);
disp('M2_INTERFACE_CLEANUP_PASS');
end
function inject(reference)
assert(bdIsLoaded(reference));
error('M2:INJECTED_INTERFACE_FAILURE','Deliberate exception after source creation.');
end
function close_owned(model)
if bdIsLoaded(model),close_system(model,0);end
end
