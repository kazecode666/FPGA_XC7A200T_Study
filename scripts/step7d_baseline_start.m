function step7d_baseline_start(m,cfg)
% Task 1 only: effective configuration and actual block execution callbacks.
global STEP7D_BASELINE_EVENTS STEP7D_BASELINE_LISTENERS STEP7D_BASELINE_EFFECTIVE
STEP7D_BASELINE_EVENTS=struct('current',[],'speed',[],'position',[]);
STEP7D_BASELINE_EFFECTIVE=struct;
checks={'CONTROL_BACKEND',0;'Ts',1e-4;'Ts_ACR',1e-4;'Ts_ASR',1e-3;'Ts_POS',1e-2; ...
 'PMLSM_Ts_s',cfg.commTs;'PMLSM_deadtime_s',cfg.deadtime_s;'PMLSM_deadtime_ratio',cfg.deadtime_s/1e-4; ...
 'Udc',48;'Host_Iq_Test_Mode',cfg.host.Host_Iq_Test_Mode;'Host_Id_A',0; ...
 'Speed_loop_Iq_Limit',1;'Iq_int_limit',.5;'Pos_deadband',.02};
for k=1:size(checks,1)
 v=slResolve(checks{k,1},m); assert(abs(v-checks{k,2})<1e-14,'Step7D:BaselineConfig','Incorrect effective %s',checks{k,1});
 STEP7D_BASELINE_EFFECTIVE.(checks{k,1})=v;
end
assert(abs(str2double(get_param(m,'FixedStep'))-cfg.commTs)<1e-15);
for sid=[207 208 232 234]
 b=Simulink.ID.getFullName(sprintf('%s:%d',m,sid));
 assert(abs(slResolve(get_param(b,'SampleTime'),b)-cfg.commTs)<1e-15);
 assert(strcmp(get_param(b,'LimitOutput'),'off'));
end
for n={'Kp_ASR','Ki_ASR','Kaw_s','Kp_pos','Kp_ACR','Ki_ACR','Host_Enable_Schedule'}
 STEP7D_BASELINE_EFFECTIVE.(n{1})=slResolve(n{1},m);
end
STEP7D_BASELINE_LISTENERS=cell(1,3);
sids=[759 1163 1118]; names={'current','speed','position'};
for k=1:3
 b=Simulink.ID.getFullName(sprintf('%s:%d',m,sids(k))); key=names{k};
 STEP7D_BASELINE_LISTENERS{k}=add_exec_event_listener(b,'PostOutputs',@(blk,ev)recordEvent(key,blk.CurrentTime));
end
end
function recordEvent(name,t)
global STEP7D_BASELINE_EVENTS
STEP7D_BASELINE_EVENTS.(name)(end+1,1)=t;
end
