function study_l1_d_start(m)
global STUDY_D_LISTENERS STUDY_D_EVENTS STUDY_D_EFFECTIVE
cfg=slResolve('STUDY_D_CFG',m); STUDY_D_EFFECTIVE=struct;
checks={'CONTROL_BACKEND',1;'FPGA_Cosim_Enable',1;'FPGA_Cosim_Input_Mode',1;'FPGA_Reference_Mode',1;'PMLSM_Ts_s',cfg.commTs;'PMLSM_deadtime_s',cfg.deadtime_s;'PMLSM_deadtime_ratio',cfg.deadtime_s/1e-4;'Ts',1e-4;'Ts_ACR',1e-4;'Ts_ASR',1e-3;'Ts_POS',1e-2;'Udc',48;'Host_Id_A',0;'Host_Iq_Test_Mode',0;'Speed_loop_Iq_Limit',1;'Iq_int_limit',.5;'Pos_deadband',.02;'STEP7C_PI_PROFILE',0};
for k=1:size(checks,1), v=slResolve(checks{k,1},m); assert(abs(v-checks{k,2})<1e-14); STUDY_D_EFFECTIVE.(checks{k,1})=v; end
assert(isequal(slResolve('Host_Enable_Schedule',m),cfg.host.Host_Enable_Schedule));
p=study_l1_init; for n=fieldnames(p)', v=slResolve(n{1},m); assert(isequal(v,p.(n{1}))); STUDY_D_EFFECTIVE.(n{1})=v; end
for n={'Kp_pos','Kp_ACR','Ki_ACR','Host_Enable_Schedule'}
 STUDY_D_EFFECTIVE.(n{1})=slResolve(n{1},m);
end
for sid=[207 208 232 234]
 b=Simulink.ID.getFullName(sprintf('%s:%d',m,sid)); assert(abs(slResolve(get_param(b,'SampleTime'),b)-cfg.commTs)<1e-15);
 assert(strcmp(get_param(b,'ExternalReset'),'none') && strcmp(get_param(b,'LimitOutput'),'off'));
end
b=[m '/Study_D_XSI']; [ins,outs]=study_l1_d_ports; pt=str2num(get_param(b,'PortTimes')); %#ok<ST2NM>
assert(numel(pt)==numel(ins)+numel(outs) && all(abs(pt(numel(ins)+1:end)-cfg.commTs)<1e-15));
assert(isequal(str2num(get_param(b,'ClockTimes')),[20e-9 200e-9]) && str2double(get_param(b,'PreRunTime'))==0); %#ok<ST2NM>
STUDY_D_EVENTS=struct('current',[],'speed',[],'position',[]); STUDY_D_LISTENERS=cell(1,3);
names={'current','speed','position'}; sids=[759 1163 1118];
for j=1:3
 key=names{j}; b=Simulink.ID.getFullName(sprintf('%s:%d',m,sids(j)));
 STUDY_D_LISTENERS{find(strcmp({'current','speed','position'},key))}=add_exec_event_listener(b,'PostOutputs',@(blk,ev)record(key,blk.CurrentTime));
end
end
function record(n,t), global STUDY_D_EVENTS; STUDY_D_EVENTS.(n)(end+1,1)=t; end
