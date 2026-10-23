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
assert(~bdIsLoaded(model),'M1A:FRESH_PROCESS','Run in a fresh MATLAB process.');
load_system(file);
cleanup = onCleanup(@() close_system(model,0));
if strcmp(stage,'init')
    % A dirty/foreign base workspace must not satisfy the initialization gate.
    assignin('base','Kp_ACR',8.725); assignin('base','Udc',48);
    try
        set_param(model,'SimulationCommand','update');
        error('M1A:MISSING_INIT_ACCEPTED','Uninitialized model compiled.');
    catch exception
        assert(contains(getReport(exception),'init_PMLSM_PI_FOC_Float_Baseline'), ...
            'M1A:INIT_ERROR_UNCLEAR','Expected explicit initialization error, got: %s',exception.message);
    end
    error('M1A:INIT_POSITIVE_PENDING','Initialization negative checked; positive checks pending.');
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
