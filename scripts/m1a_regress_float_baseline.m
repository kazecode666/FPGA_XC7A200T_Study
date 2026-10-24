function result=m1a_regress_float_baseline(outputFolder)
% Finite source backend0 migration and plant-step convergence checks.
root=fileparts(fileparts(mfilename('fullpath')));
folder=fullfile(root,'docs','reports','m1a_float_baseline');
contract=jsondecode(fileread(fullfile(folder,'acceptance_config.json')));
if nargin>0,folder=outputFolder;if ~isfolder(folder),mkdir(folder);end;end
runtime=fullfile(root,'.runtime','m1a_20261023',sprintf('regression_%d',matlabProcessID));
if ~isfolder(runtime),mkdir(runtime);end
scenes=struct('name',{},'kind',{},'sign',{},'stop',{},'deadtime',{},'loadstep',{},'stopreset',{});
scenes(end+1)=scene('current_pos','current',1,0.03,1e-6,false,false);
scenes(end+1)=scene('current_neg','current',-1,0.03,1e-6,false,false);
scenes(end+1)=scene('speed_pos','speed',1,0.25,1e-6,false,false);
scenes(end+1)=scene('speed_neg','speed',-1,0.25,1e-6,false,false);
scenes(end+1)=scene('position_pos','position',1,1.2,1e-6,false,false);
scenes(end+1)=scene('position_neg','position',-1,1.2,1e-6,false,false);
scenes(end+1)=scene('position_ideal','position',1,1.2,0,false,false);
scenes(end+1)=scene('position_load','position',1,1.2,1e-6,true,false);
scenes(end+1)=scene('stop_reset','current',1,0.03,1e-6,false,true);
rows=struct('scenario',{},'comparison',{},'signal',{},'unit',{},'samples',{},'max_abs',{},'rmse',{},'threshold',{},'pass',{});
allPass=true;
for k=1:numel(scenes)
    c=scenes(k);
    old=run_case(root,c,true,1e-6); fprintf('M1A_SOURCE_DONE %s\n',c.name);
    fresh=run_case(root,c,false,1e-6);fprintf('M1A_NEW_DONE %s\n',c.name);
    metrics=compare(c.name,'migration',old,fresh,contract,false);
    rows=[rows metrics]; %#ok<AGROW>
    allPass=allPass&&all([metrics.pass]);
    save(fullfile(runtime,[c.name '.mat']),'old','fresh','metrics');
    fprintf('M1A_SCENE_DONE %s pass=%d\n',c.name,all([metrics.pass]));
    if k==1,coarse=fresh;end
end
fine=run_case(root,scenes(1),false,0.5e-6);
metrics=compare('current_pos','plant_step',coarse,fine,contract,true);
rows=[rows metrics];allPass=allPass&&all([metrics.pass]);
save(fullfile(runtime,'plant_step.mat'),'coarse','fine','metrics');
writetable(struct2table(rows),fullfile(folder,'closedloop_metrics.csv'));
result=struct('pass',allPass,'details',struct('scenes',{scenes},'rows',numel(rows), ...
    'source_backend',0,'original_saved',false,'runtime',runtime));
fid=fopen(fullfile(folder,'closedloop_acceptance.json'),'w');
fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
assert(allPass,'M1A:CLOSEDLOOP_MISMATCH','Frozen migration/convergence thresholds failed; see closedloop_metrics.csv.');
fprintf('M1A_CLOSEDLOOP_PASS scenarios=%d metrics=%d\n',numel(scenes),numel(rows));
end

function c=scene(name,kind,direction,stop,deadtime,loadstep,stopreset)
c=struct('name',name,'kind',kind,'sign',direction,'stop',stop, ...
    'deadtime',deadtime,'loadstep',loadstep,'stopreset',stopreset);
end

function result=run_case(root,c,source,plantStep)
evalin('base','init_PMLSM_PI_FOC_Float_Baseline;Host_Traj_Vmax=5;Host_Traj_Amax=50;');
names=evalin('base','who(''Host_*'')');host=struct;
for k=1:numel(names),host.(names{k})=evalin('base',names{k});end
host.Host_Target_mm=c.sign; speed=0;
if strcmp(c.kind,'current')
    host.Host_Enable_Schedule=[0 0 0 1];host.Host_Iq_Test_Mode=1;host.Host_Iq_A=c.sign*0.2;
elseif strcmp(c.kind,'speed')
    host.Host_Enable_Schedule=[0 1 0 1];speed=c.sign*10;
end
signals=struct('speed',[0 speed;c.stop speed],'load',[0 0;c.stop 0], ...
    'pwm',[0 1;c.stop 1],'reset',[0 0;c.stop 0]);
if c.loadstep,signals.load=[0 0;0.8 0.5;1 0;c.stop 0];end
if c.stopreset
    signals.pwm=[0 1;0.012 0;0.018 1;c.stop 1];
    signals.reset=[0 0;0.0179 1;0.0181 0;c.stop 0];
end
if source
    m='PMLSM_ThreeLoop_Simple';load_system(fullfile(root,'simulink模型',[m '.slx']));
    cfg=struct('host',host,'signals',signals,'commTs',plantStep, ...
        'deadtime_s',c.deadtime,'stopTime',c.stop,'backend',0);
    pmlsm_interactive_cosim_state('set',struct('model',m,'cfg',cfg));
    pmlsm_interactive_cosim_init(m);
else
    m='PMLSM_PI_FOC_Float_Baseline';load_system(fullfile(root,'simulink模型',[m '.slx']));
    names=fieldnames(host);
    for k=1:numel(names),assignin('base',names{k},host.(names{k}));end
    assignin('base','Host_Close_Loop_EN',double(~strcmp(c.kind,'current')));
    assignin('base','Host_Position_Loop_EN',double(strcmp(c.kind,'position')));
    assignin('base','Host_Replay_EN',1);
    assignin('base','Ts_Plant',plantStep);assignin('base','PMLSM_Ts_s',plantStep);
    assignin('base','PMLSM_deadtime_s',c.deadtime);
    assignin('base','PMLSM_deadtime_ratio',c.deadtime/1e-4);
    names={'Speed','Load','PWM','Reset'};fields={'speed','load','pwm','reset'};
    for k=1:4
        data=signals.(fields{k});
        assignin('base',['M1A_' names{k} '_ts'],timeseries(data(:,2),data(:,1)));
    end
end
cleanup=onCleanup(@()close_case(m,source));
blocks=find_system(m,'LookUnderMasks','all','FollowLinks','off','MatchFilter',@Simulink.match.allVariants,'Type','Block');
for k=1:numel(blocks)
    p=get_param(blocks{k},'PortHandles');
    for port=p.Outport
        if strcmp(get_param(port,'DataLogging'),'on'),set_param(port,'DataLogging','off');end
    end
end
% SID / port / signal / physical unit / threshold group.
defs={191,1,'id','A','current_A';191,2,'iq','A','current_A'; ...
    191,6,'x','mm','position_mm';191,7,'v','mm/s','speed_mmps'; ...
    698,1,'vd','V','voltage_V';698,2,'vq','V','voltage_V'; ...
    505,1,'cmd_u','ratio','duty';505,2,'cmd_v','ratio','duty';505,3,'cmd_w','ratio','duty'; ...
    866,1,'applied_u','ratio','duty';866,2,'applied_v','ratio','duty';866,3,'applied_w','ratio','duty'; ...
    586,1,'x_d','V','PI_AW_state';613,1,'x_q','V','PI_AW_state'; ...
    727,1,'du_d_z','V','PI_AW_state';728,1,'du_q_z','V','PI_AW_state'; ...
    1228,1,'x_speed','A','PI_AW_state';1166,1,'speed_memory','A','PI_AW_state'; ...
    740,1,'speed_tick','event','event';740,2,'position_tick','event','event'; ...
    756,1,'position_counter','count','event';759,1,'speed_counter','count','event'; ...
    1248,1,'pwm_enable','bool','event';1277,1,'effective_reset','bool','event'};
for k=1:size(defs,1)
    sid=defs{k,1};if source&&sid==866,sid=1613;end
    b=Simulink.ID.getFullName(sprintf('%s:%d',m,sid));p=get_param(b,'PortHandles');port=p.Outport(defs{k,2});
    decimation=1;
    if sid==191||(source&&any(sid==[1248 1277])),decimation=round(1e-4/plantStep);end
    set_param(port,'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',defs{k,3}, ...
        'DataLoggingDecimateData','on','DataLoggingDecimation',num2str(decimation));
end
input=Simulink.SimulationInput(m).setModelParameter('FixedStep',num2str(plantStep,17), ...
    'StopTime',num2str(c.stop,17),'SignalLogging','on','SignalLoggingName','logsout', ...
    'ReturnWorkspaceOutputs','on');
data=sim(input);result=struct;
for k=1:size(defs,1)
    value=data.logsout.getElement(defs{k,3}).Values;
    samples=double(value.Data(:));
    if source&&startsWith(defs{k,3},'cmd_'),samples=1-samples/10000;end
    assert(all(isfinite(samples)),'M1A:NONFINITE','%s %s contains nonfinite values.',c.name,defs{k,3});
    result.(defs{k,3})=struct('time',value.Time,'data',samples,'unit',defs{k,4},'group',defs{k,5});
end
assert(c.sign*result.x.data(end)>0||~strcmp(c.kind,'position'),'M1A:POSITION_DIRECTION','Wrong position direction.');
if strcmp(c.kind,'current'),assert(c.sign*result.iq.data(end)>0,'M1A:CURRENT_DIRECTION','Wrong current direction.');end
if strcmp(c.kind,'speed'),assert(c.sign*result.v.data(end)>0,'M1A:SPEED_DIRECTION','Wrong velocity direction.');end
end

function rows=compare(scenario,comparison,a,b,contract,convergence)
names=fieldnames(a);rows=struct('scenario',{},'comparison',{},'signal',{},'unit',{},'samples',{},'max_abs',{},'rmse',{},'threshold',{},'pass',{});
for k=1:numel(names)
    name=names{k};x=a.(name);y=b.(name);
    assert(numel(x.time)==numel(y.time)&&max(abs(x.time-y.time))<1e-12, ...
        'M1A:TIME_ALIGNMENT','%s %s: sample/event times differ.',scenario,name);
    delta=x.data-y.data;maximum=max(abs(delta));rms=sqrt(mean(delta.^2));
    if strcmp(x.group,'event')
        threshold=0;
    elseif ~convergence
        threshold=contract.migration_max_abs.(x.group);
    elseif strcmp(x.group,'duty')
        threshold=contract.convergence_max_abs.voltage_V/48;
    elseif strcmp(x.group,'PI_AW_state')
        if strcmp(x.unit,'A'),threshold=contract.convergence_max_abs.current_A;else,threshold=contract.convergence_max_abs.voltage_V;end
    else
        threshold=contract.convergence_max_abs.(x.group);
    end
    passed=maximum<=threshold&&rms<=threshold;
    rows(end+1)=struct('scenario',scenario,'comparison',comparison,'signal',name, ...
        'unit',x.unit,'samples',numel(delta),'max_abs',maximum,'rmse',rms,'threshold',threshold,'pass',passed); %#ok<AGROW>
    if ~passed,fprintf('M1A_METRIC_FAIL %s %s max=%.17g threshold=%.17g\n',scenario,name,maximum,threshold);end
end
end
function close_case(model,source)
if bdIsLoaded(model),close_system(model,0);end
if source,pmlsm_interactive_cosim_state('clear');end
end
