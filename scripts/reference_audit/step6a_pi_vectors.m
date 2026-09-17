function result = step6a_pi_vectors(repo)
% Execute copies of the audited PI blocks. Never save or edit source models.
% No initialization scripts, advanced branches, codegen or hardware are run.
% Output duty columns intentionally retain the source's raw CPU-clock counts.
if nargin == 0, repo = fileparts(fileparts(fileparts(mfilename('fullpath')))); end
source = 'PMLSM_ControlCore_Block';
wasLoaded = bdIsLoaded(source);
load_system(fullfile(repo,'simulink模型',[source '.slx']));
sourceDirty = get_param(source,'Dirty');
foc = [source '/PMLSM_ControlCore/FOC_Algorithm'];
[~,token] = fileparts(tempname);
model = ['s6a_' token];
new_system(model);
cleanup = onCleanup(@() finish_models(model,source,wasLoaded));
set_param(model,'Solver','FixedStepDiscrete','FixedStep','0.0001', ...
    'StopTime','0','ReturnWorkspaceOutputs','on','SignalLogging','off');
mw = get_param(model,'ModelWorkspace');
% Explicit, audited source values. Do not execute scripts containing clear.
params = struct('Ts',1e-4,'Ts_ACR',1e-4,'CPU_Clock',200e6, ...
    'Udc',48,'PMLSM_Ld_H',1.745e-3,'PMLSM_Lq_H',1.745e-3, ...
    'PMLSM_psi_f_Wb',0.141,'Kaw_d',0.2,'Kaw_q',0.2);
names = fieldnames(params);
for i=1:numel(names), assignin(mw,names{i},params.(names{i})); end
copies = {'Clack','Park Transform','Id','Iq','dq_voltage_limiter', ...
    'Inverse Park Transform','SVPWMG'};
for i=1:numel(copies), add_block([foc '/' copies{i}],[model '/' copies{i}]); end
% Source Park output names require exported signal objects. Remove that
% metadata only on the copied ports; numerical blocks are unchanged.
ph = get_param([model '/Park Transform'],'PortHandles');
for i=1:2, set_param(ph.Outport(i),'MustResolveToSignalObject','off'); end
for name={'Id','Iq','dq_voltage_limiter'}
    bs=find_system([model '/' name{1}],'SearchDepth',1,'Type','Block');
    for j=1:numel(bs)
        ph=get_param(bs{j},'PortHandles');
        for k=1:numel(ph.Outport)
            set_param(ph.Outport(k),'MustResolveToSignalObject','off');
        end
    end
end
add_block('simulink/Sources/From Workspace',[model '/samples'], ...
    'VariableName','samples','Interpolate','off','SampleTime','0.0001', ...
    'OutputAfterFinalValue','Holding final value');
add_block('simulink/Signal Routing/Demux',[model '/in'],'Outputs','10');
wire('samples/1','in/1');
% ia ib ic theta id_ref iq_ref we reset uq_zero reserved
for i=1:3, wire(sprintf('in/%d',i),sprintf('Clack/%d',i)); end
wire('Clack/1','Park Transform/1'); wire('Clack/2','Park Transform/2');
wire('in/4','Park Transform/3'); wire('in/4','Inverse Park Transform/3');
wire('in/5','Id/1'); wire('in/6','Iq/1');
wire('Park Transform/1','Id/2'); wire('Park Transform/2','Id/3');
wire('Park Transform/1','Iq/2'); wire('Park Transform/2','Iq/3');
wire('in/7','Id/4'); wire('in/7','Iq/4'); wire('in/9','Iq/6');
add_block('simulink/Signal Routing/Data Store Memory',[model '/reset_store'], ...
    'DataStoreName','PI_Reset_EN_cmd','InitialValue','0');
add_block('simulink/Signal Routing/Data Store Write',[model '/reset_write'], ...
    'DataStoreName','PI_Reset_EN_cmd'); wire('in/8','reset_write/1');
% Pin order so the command write precedes both PI reads in this harness.
set_param([model '/reset_write'],'Priority','1');
set_param([model '/Id'],'Priority','2'); set_param([model '/Iq'],'Priority','3');
wire('Id/1','dq_voltage_limiter/1'); wire('Iq/1','dq_voltage_limiter/2');
wire('dq_voltage_limiter/3','Id/5'); wire('dq_voltage_limiter/4','Iq/5');
wire('dq_voltage_limiter/1','Inverse Park Transform/1');
wire('dq_voltage_limiter/2','Inverse Park Transform/2');
% DeadTime_Comp_Enable=0 bypass, as audited. No compensation is simulated.
wire('Inverse Park Transform/1','SVPWMG/1');
wire('Inverse Park Transform/2','SVPWMG/2');
sv = [model '/SVPWMG'];
for i=1:2
    add_block('simulink/Sinks/Out1',[sv sprintf('/audit_t%d',i)],'Port',num2str(4+i));
    add_line(sv,sprintf('T1T2\nCalculate/%d',i),sprintf('audit_t%d/1',i));
end
outNames = {'i_alpha','i_beta','id','iq','ud_raw','uq_raw','ud_lim','uq_lim', ...
    'v_alpha','v_beta','sector','t1','t2','duty_a','duty_b','duty_c', ...
    'du_d_z','du_q_z','sat_flag_z'};
ports = {'Clack/1','Clack/2','Park Transform/1','Park Transform/2', ...
    'Id/1','Iq/1','dq_voltage_limiter/1','dq_voltage_limiter/2', ...
    'Inverse Park Transform/1','Inverse Park Transform/2','SVPWMG/4', ...
    'SVPWMG/5','SVPWMG/6','SVPWMG/1','SVPWMG/2','SVPWMG/3', ...
    'dq_voltage_limiter/3','dq_voltage_limiter/4','dq_voltage_limiter/5'};
for i=1:numel(outNames)
    add_block('simulink/Sinks/To Workspace',[model '/' outNames{i}], ...
        'VariableName',outNames{i},'SaveFormat','Array');
    wire(ports{i},[outNames{i} '/1']);
end
add_block('simulink/Sinks/Terminator',[model '/unused']); wire('in/10','unused/1');
% Each independent test starts with two reset transactions. Sequential
% saturation/recovery rows deliberately retain state; time and reset are CSV.
u = zeros(0,10); labels = strings(0,1);
append('zero',[0 0 0 0 0 0 0 0 0 0],true);
append('d_current',[1 -.5 -.5 0 0 0 0 0 0 0],true);
append('q_current',[0 sqrt(3)/2 -sqrt(3)/2 0 0 0 0 0 0 0],true);
append('common_mode',[1 1 1 0 0 0 0 0 0 0],true);
for angle=[0 pi/2 pi 3*pi/2 2*pi]
    append(sprintf('angle_%.4f',angle),[.2 -.3 .1 angle .4 -.2 0 0 0 0],true);
end
for angle=(15:60:315)*pi/180
    append(sprintf('sector_%.0f',angle*180/pi),[0 0 0 0 cos(angle) sin(angle) 0 0 0 0],true);
end
% Actual sector predicates use 0.866, not sqrt(3)/2.
for ab=[1 0;1 1.732;-1 1.732;-1 0;-1 -1.732;1 -1.732]'
    append(sprintf('edge_%g_%g',ab),[0 0 0 0 ab' 0 0 0 0],true);
end
append('feedforward',[.2 -.1 -.1 .3 .5 .4 100 0 0 0],true);
append('sat_start',[0 0 0 .2 30 -20 0 0 0 0],true);
for i=1:4, append(sprintf('sat_hold_%d',i),[0 0 0 .2 30 -20 0 0 0 0],false); end
for i=1:4, append(sprintf('recovery_%d',i),zeros(1,10),false); end
append('q_zero',[.1 -.05 -.05 0 1 1 30 0 1 0],false);
append('reset_after_sat',[0 0 0 0 20 20 0 1 0 0],false);
append('release',[0 0 0 0 .2 -.2 0 0 0 0],false);
t = (0:size(u,1)-1)'*params.Ts;
assignin(mw,'samples',[t u]);
set_param(model,'StopTime',sprintf('%.17g',t(end)));
result = table;
profiles = {'real_commissioning','MIL_PI_override'};
for p=1:2
    kp = 2.18125*p; ki = 2962.5*p;
    assignin(mw,'Kp_ACR',kp); assignin(mw,'Ki_ACR',ki);
    simout = sim(model);
    rows = table(repmat(string(profiles{p}),numel(t),1),labels,t, ...
        'VariableNames',{'parameter_profile','case_id','time_s'});
    rows.parameter_profile = repmat(string(profiles{p}),numel(t),1);
    inNames={'ia','ib','ic','theta_e','id_ref','iq_ref','we','pi_reset','uq_zero_en'};
    for i=1:9, rows.(inNames{i})=u(:,i); end
    rows.vdc=repmat(48,numel(t),1);
    for i=1:numel(outNames), rows.(outNames{i})=double(simout.get(outNames{i})); end
    rows.kp=repmat(kp,numel(t),1);rows.ki=repmat(ki,numel(t),1);
    result=[result;rows]; %#ok<AGROW>
end
assert(all(isfinite(result{:,4:end}),'all'),'Nonfinite golden values');
assert(isequal(unique(result.sector)',1:6),'Missing sector coverage');
writetable(result,fullfile(repo,'coordination/reports/step6a_pi_foc_golden_vectors.csv'));
fprintf('STEP6A: %d source-block samples, sectors 1..6, two gain profiles.\n',height(result));
assert(strcmp(get_param(source,'Dirty'),sourceDirty),'Source dirty state changed');
    function wire(a,b), add_line(model,a,b); end
    function append(label,row,resetFirst)
        if resetFirst
            u=[u;zeros(2,10)];u(end-1:end,8)=1;
            labels=[labels;string(label)+"_reset1";string(label)+"_reset2"];
        end
        u=[u;row];labels=[labels;string(label)];
    end
end
function finish_models(model,source,wasLoaded)
if bdIsLoaded(model),close_system(model,0);end
if ~wasLoaded && bdIsLoaded(source),close_system(source,0);end
end
