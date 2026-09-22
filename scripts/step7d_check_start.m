function effective=step7d_check_start(m,cfg)
% Validate values resolved in the running model after all InitFcn reloads.
if cfg.backend==1
 assert(isequal(slResolve('FPGA_Reference_Mode',m),1),'Step7D:ReferenceMode','FPGA must select the real outer-loop reference.');
end
for p={'Ts',1e-4;'Ts_ACR',1e-4;'Ts_ASR',1e-3;'Ts_POS',1e-2}'
 assert(abs(slResolve(p{1},m)-p{2})<1e-15,'Step7D:ControlPeriod','Incorrect effective %s',p{1});
end
effective=struct;
names={'CONTROL_BACKEND','FPGA_Cosim_Enable','FPGA_Cosim_Input_Mode','FPGA_Reference_Mode'};
for k=1:4, effective.(names{k})=slResolve(names{k},m); end
assert(effective.CONTROL_BACKEND==cfg.backend,'Step7D:Backend','Wrong effective backend.');
if cfg.backend==1
 assert(isequal(cellfun(@(n)effective.(n),names),[1 1 1 1]),'Step7D:Modes','Incorrect live FPGA modes.');
end
checks={'PMLSM_Ts_s',cfg.commTs;'PMLSM_deadtime_s',cfg.deadtime_s; ...
 'PMLSM_deadtime_ratio',cfg.deadtime_s/1e-4;'Ts',1e-4;'Ts_ACR',1e-4;'Ts_ASR',1e-3;'Ts_POS',1e-2; ...
 'Udc',48;'Host_Id_A',0;'Host_Iq_Test_Mode',0;'Speed_loop_Iq_Limit',1;'Iq_int_limit',.5;'Pos_deadband',.02;'STEP7C_PI_PROFILE',0};
for k=1:size(checks,1)
 v=slResolve(checks{k,1},m); assert(abs(v-checks{k,2})<1e-14,'Step7D:EffectiveConfig','Incorrect %s',checks{k,1});
 effective.(checks{k,1})=v;
end
assert(isequal(slResolve('Host_Enable_Schedule',m),cfg.host.Host_Enable_Schedule),'Step7D:EnableMode','Incorrect outer mode.');
assert(abs(str2double(get_param(m,'FixedStep'))-cfg.commTs)<1e-15,'Step7D:PlantStep','Solver step mismatch.');
for sid=[207 208 232 234]
 b=Simulink.ID.getFullName(sprintf('%s:%d',m,sid));
 assert(abs(slResolve(get_param(b,'SampleTime'),b)-cfg.commTs)<1e-15,'Step7D:PlantStep','Integrator step mismatch.');
 assert(strcmp(get_param(b,'ExternalReset'),'none') && strcmp(get_param(b,'LimitOutput'),'off'),'Step7D:PlantLocked','Free plant required.');
end
if cfg.backend==1
 b=find_system(m,'MatchFilter',@Simulink.match.allVariants,'Name','HDL_Cosimulation'); assert(numel(b)==1);
 pt=str2num(get_param(b{1},'PortTimes')); %#ok<ST2NM>
 assert(numel(pt)==19 && all(abs(pt(12:19)-cfg.commTs)<1e-15),'Step7D:HDLTiming','HDL output times mismatch.');
 assert(isequal(str2num(get_param(b{1},'ClockTimes')),[20e-9 200e-9]),'Step7D:HDLTiming','Clock/reset physical times mismatch.'); %#ok<ST2NM>
 assert(str2double(get_param(b{1},'PreRunTime'))==0,'Step7D:HDLTiming','HDL prerun must be zero.');
 effective.unselected_iq_script=double(slResolve('STEP7C_iq_ref_ts',m).Data(:))';
 effective.unselected_id_script=double(slResolve('STEP7C_id_ref_ts',m).Data(:))';
 effective.smoke_iq=slResolve('FPGA_Smoke_iq_ref_A',m);
 if isfield(cfg,'canaryEnabled') && cfg.canaryEnabled
  assert(all(effective.unselected_iq_script==.17) && all(effective.unselected_id_script==-.09) && effective.smoke_iq==-.3,'Step7D:CanaryConfig','Canary overridden before startup.');
 end
 gate=slResolve('STEP7C_run_gate_ts',m);
 assert(all(gate.Data==1) && gate.Time(1)==0 && gate.Time(end)>=cfg.stopTime,'Step7D:RunGate','Normal run gate must cover full duration.');
end
for n={'Kp_ASR','Ki_ASR','Kaw_s','Kp_pos','Kp_ACR','Ki_ACR','Host_Enable_Schedule'}, effective.(n{1})=slResolve(n{1},m); end
end
