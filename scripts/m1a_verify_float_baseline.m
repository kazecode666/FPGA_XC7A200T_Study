function result = m1a_verify_float_baseline(stage)
% Verify M1A in an independent MATLAB -batch process; never save a source SLX.
arguments
    stage (1,:) char {mustBeMember(stage,{'structure','init','math','closedloop','all'})}
end
root = fileparts(fileparts(mfilename('fullpath')));
model = 'PMLSM_PI_FOC_Float_Baseline';
file = fullfile(root,'simulink模型',[model '.slx']);
assert(isfile(file),'M1A:MODEL_MISSING','M1A_MODEL_MISSING: %s',file);
addpath(fullfile(root,'simulink模型'));
runtime=fullfile(root,'.runtime','m1a_20261023');
processFolder=fullfile(runtime,sprintf('process_%d',feature('getpid')));
Simulink.fileGenControl('set','CacheFolder',fullfile(processFolder,'cache'), ...
    'CodeGenFolder',fullfile(processFolder,'codegen'),'createDir',true);
assert(~bdIsLoaded(model),'M1A:FRESH_PROCESS','Run in a fresh MATLAB process.');
load_system(file);
cleanup = onCleanup(@() close_system(model,0));
if strcmp(stage,'init')
    % A dirty/foreign base workspace must not satisfy the initialization gate.
    evalin('base','clear PMLSM_M1A_InitVersion');
    assignin('base','Kp_ACR',8.725); assignin('base','Udc',48);
    try
        set_param(model,'SimulationCommand','update');
        error('M1A:MISSING_INIT_ACCEPTED','Uninitialized model compiled.');
    catch exception
        assert(contains(getReport(exception),'init_PMLSM_PI_FOC_Float_Baseline'), ...
            'M1A:INIT_ERROR_UNCLEAR','Expected explicit initialization error, got: %s',exception.message);
    end
    fprintf('M1A_INIT_NEGATIVE_PASS foreign_Kp_Udc_cannot_bypass_marker\n');
    evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');
    assert(isempty(whos(get_param(model,'ModelWorkspace'))));
    probes={'Kp_ACR','Ki_ACR','Udc','Host_Target_mm','PMLSM_Rs_ohm','Ts_ACR','PMLSM_Ts_s'};
    for k=1:numel(probes)
        assert(isequal(slResolve(probes{k},model),evalin('base',probes{k})), ...
            'M1A:SHADOW','Unexpected resolution for %s.',probes{k});
    end
    input=Simulink.SimulationInput(model).setModelParameter('StopTime','0.002');
    first=sim(input);
    evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');
    second=sim(input);
    assert(isequaln(first.logsout,second.logsout), ...
        'M1A:REPEAT','Repeated initialization/simulation differed.');
    initText=fileread(fullfile(root,'simulink模型','init_PMLSM_PI_FOC_Float_Baseline.m'));
    token='Host_Start_s=0.05; Host_Target_mm=1;';
    assert(contains(initText,token));
    sceneText=strrep(initText,token,'Host_Start_s=-1; Host_Target_mm=-1;');
    sceneFile=fullfile(processFolder,'negative_position_init.m');
    fid=fopen(sceneFile,'w','n','UTF-8'); fprintf(fid,'%s',sceneText); fclose(fid);
    evalin('base',sprintf('run(''%s'');',strrep(sceneFile,'\','/')));
    assert(slResolve('Host_Target_mm',model)==-1);
    % Position scheduler's first event is 9.9 ms; cross two position events.
    sceneInput=input.setModelParameter('StopTime','0.025');
    negative=sim(sceneInput);
    reference=negative.logsout.getElement('x_ref_mm').Values.Data;
    position=negative.logsout.getElement('x_mm').Values.Data;
    fprintf('M1A_SCENE ref_min=%.17g ref_max=%.17g x_final_mm=%.17g\n', ...
        min(reference),max(reference),position(end));
    save(fullfile(processFolder,'negative_position_diagnostic.mat'),'negative','reference','position');
    assert(all(reference==-1) && position(end)<0,'M1A:SCENE_NOT_APPLIED', ...
        'Negative reference scene was not applied or position moved in the wrong direction.');
    token='M1A_Load_ts=timeseries([0;0],[0;M1A_StopTime_s]);';
    assert(contains(initText,token));
    sceneText=strrep(initText,token,'M1A_Load_ts=timeseries([0.5;0.5],[0;M1A_StopTime_s]);');
    sceneFile=fullfile(processFolder,'load_init.m');
    fid=fopen(sceneFile,'w','n','UTF-8'); fprintf(fid,'%s',sceneText); fclose(fid);
    evalin('base',sprintf('run(''%s'');',strrep(sceneFile,'\','/')));
    loaded=sim(input);
    position=loaded.logsout.getElement('x_mm').Values.Data;
    assert(position(end)<0,'M1A:LOAD_NOT_APPLIED','Positive opposing load did not move free plant negatively.');
    evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');
    restored=sim(input);
    assert(isequaln(first.logsout,restored.logsout),'M1A:DEFAULT_NOT_RESTORED','Defaults did not reproduce.');
    result=struct('pass',true,'details',struct('stage',stage,'short_run_s',0.002, ...
        'negative_guard',true,'base_resolution',true,'same_process_repeat',true, ...
        'process_id',feature('getpid'),'scene_response',true));
    save(fullfile(processFolder,'init_short_runs.mat'),'first','second','negative','loaded','restored','result');
    fprintf('M1A_INIT_PASS repeat/resolution/external_scenes/default_restore process=%d\n',feature('getpid'));
    return
end
if strcmp(stage,'math')
    result=m1a_check_modulation(model);
    return
end
assert(strcmp(stage,'structure'),'M1A:STAGE_PENDING', ...
    'M1A stage %s has not been implemented or accepted.',stage);
assert(strcmp(get_param(model,'Name'),model));
blocks = find_system(model,'LookUnderMasks','all','FollowLinks','off', ...
    'MatchFilter',@Simulink.match.allVariants,'Type','Block');
for k=1:numel(blocks)
    assert(~contains(blocks{k},{'FPGA_HDL_Cosim','HDL_Cosimulation'}), ...
        'M1A:COSIM_REFERENCE','Residual co-simulation: %s',blocks{k});
    ref = get_param(blocks{k},'ReferenceBlock');
    assert(~contains(lower(ref),{'vivadosimlib','cosim'}), ...
        'M1A:COSIM_LIBRARY','Residual co-simulation library: %s',ref);
end
required = {'PMLSM_Plant_Model','Inverter_DeadTime','FOC_Algorithm', ...
    'Position_Loop','Speed_Loop','Reference_Manager','Scheduler_10k_1k_100', ...
    'Motor_Control_Monitor'};
for k=1:numel(required)
    hits = find_system(model,'LookUnderMasks','all','FollowLinks','off','Name',required{k});
    assert(numel(hits)==1,'M1A:STRUCTURE','Expected one %s.',required{k});
end
assert(strcmp(get_param(model,'Dirty'),'off'),'M1A:DIRTY','Read-only check dirtied model.');
result = struct('pass',true,'details',struct('stage',stage,'blocks',numel(blocks)));
fprintf('M1A_STRUCTURE_PASS blocks=%d Dirty=off\n',numel(blocks));
end
