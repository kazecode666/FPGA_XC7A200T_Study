function result=m1a_fresh_float_baseline
% Invoke ONLY in a fresh -batch process. Runs a five-file isolated closure.
root=fileparts(fileparts(mfilename('fullpath')));
assert(~evalin('base','exist(''PMLSM_M1A_InitVersion'',''var'')==1'), ...
    'M1A:FRESH_REQUIRED','Use a fresh MATLAB -batch process.');
folder=fullfile(root,'.runtime','m1a_20261023',sprintf('fresh_closure_%d',matlabProcessID));
assert(~isfolder(folder),'M1A:OUTPUT_EXISTS','Do not overwrite an earlier fresh run.');
mkdir(folder);
files={'PMLSM_PI_FOC_Float_Baseline.slx','init_PMLSM_PI_FOC_Float_Baseline.m', ...
    'm1a_require_float_init.m','design_PMLSM_three_loop.m','pmlsm_scurve_profile.m'};
for k=1:numel(files),copyfile(fullfile(root,'simulink模型',files{k}),fullfile(folder,files{k}));end
assert(isempty(dir(fullfile(folder,'*.mat'))));
oldpwd=pwd;oldPath=path;
cleanup=onCleanup(@()finish(oldpwd,oldPath));
% Keep the fresh model from resolving any other file in this checkout.
parts=strsplit(path,pathsep);project=lower(strrep(root,'\','/'));
for k=1:numel(parts)
    candidate=lower(strrep(parts{k},'\','/'));
    if strcmp(candidate,project)||startsWith(candidate,[project '/']),rmpath(parts{k});end
end
cd(folder);addpath(folder,'-begin');
Simulink.fileGenControl('set','CacheFolder',fullfile(folder,'cache'), ...
    'CodeGenFolder',fullfile(folder,'codegen'),'createDir',true);
assert(strcmp(which('init_PMLSM_PI_FOC_Float_Baseline'),fullfile(folder,files{2})));
for k=3:numel(files)
    [~,name]=fileparts(files{k});
    assert(strcmp(which(name),fullfile(folder,files{k})), ...
        'M1A:DEPENDENCY_RESOLUTION','Helper resolved outside isolated folder: %s',name);
end
evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');
for name={'CONTROL_BACKEND','FPGA_Cosim_Enable','CPU_Clock','PMLSM_pwm_period_counts'}
    assert(~evalin('base',sprintf('exist(''%s'',''var'')==1',name{1})), ...
        'M1A:LEGACY_VARIABLE','Unexpected legacy variable %s.',name{1});
end
m='PMLSM_PI_FOC_Float_Baseline';load_system(fullfile(folder,files{1}));
assert(isempty(whos(get_param(m,'ModelWorkspace'))));
blocks=find_system(m,'LookUnderMasks','all','FollowLinks','off','Type','Block');
for k=1:numel(blocks)
    p=get_param(blocks{k},'PortHandles');
    for port=p.Outport
        if strcmp(get_param(port,'DataLogging'),'on'),set_param(port,'DataLogging','off');end
    end
end
defs={191,1,'id';191,2,'iq';191,6,'x';191,7,'v';505,1,'cmd_u';505,2,'cmd_v';505,3,'cmd_w'; ...
    586,1,'x_d';613,1,'x_q';740,1,'speed_tick';740,2,'position_tick'};
for k=1:size(defs,1)
    p=get_param(Simulink.ID.getFullName(sprintf('%s:%d',m,defs{k,1})),'PortHandles');
    decimation=1;if defs{k,1}==191,decimation=100;end
    set_param(p.Outport(defs{k,2}),'DataLogging','on','DataLoggingNameMode','Custom', ...
        'DataLoggingName',defs{k,3},'DataLoggingDecimateData','on','DataLoggingDecimation',num2str(decimation));
end
data=sim(Simulink.SimulationInput(m));
signals=struct;
for k=1:size(defs,1)
    value=data.logsout.getElement(defs{k,3}).Values;
    assert(all(isfinite(value.Data)));
    signals.(defs{k,3})=struct('time',value.Time,'data',value.Data);
end
assert(abs(signals.x.data(end)-1)<0.02,'M1A:DEFAULT_RESPONSE','Default 1 mm position scene did not settle near target.');
result=struct('pass',true,'process_id',matlabProcessID,'version',version, ...
    'source_files',{files},'stop_s',signals.x.time(end),'x_final_mm',signals.x.data(end), ...
    'old_mat_present',false,'legacy_variables_present',false, ...
    'other_repository_paths_excluded',true,'helper_resolution_checked',true);
save(fullfile(folder,'fresh_result.mat'),'result','signals');
fid=fopen(fullfile(folder,'fresh_result.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
fprintf('M1A_FRESH_PASS pid=%d stop=%.17g x_final_mm=%.17g\n', ...
    result.process_id,result.stop_s,result.x_final_mm);
end
function finish(oldpwd,oldPath)
if bdIsLoaded('PMLSM_PI_FOC_Float_Baseline'),close_system('PMLSM_PI_FOC_Float_Baseline',0);end
cd(oldpwd);
path(oldPath);
end
