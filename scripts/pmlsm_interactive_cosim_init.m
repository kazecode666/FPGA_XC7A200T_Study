function pmlsm_interactive_cosim_init(model)
% Reapply transient values after the saved InitFcn reloads the model workspace.
s=pmlsm_interactive_cosim_state('get');
assert(~isempty(s) && strcmp(model,s.model),'PMLSM:InteractiveNotPrepared','Run pmlsm_prepare_interactive_cosim first.');
cfg=s.cfg; mw=get_param(model,'ModelWorkspace');
host=cfg.host; host.PMLSM_Ts_s=cfg.commTs;
host.PMLSM_deadtime_s=cfg.deadtime_s;
host.PMLSM_deadtime_ratio=cfg.deadtime_s/1e-4; host.Udc=48;
names=fieldnames(host);
for k=1:numel(names), mw.assignin(names{k},host.(names{k})); end
kinds={'speed','load','pwm','reset'};
for k=1:numel(kinds)
 xy=cfg.signals.(kinds{k});
 mw.assignin(['STEP7D_' kinds{k} '_ts'],timeseries(xy(:,2),xy(:,1)));
end
mw.assignin('STEP7C_run_gate_ts',timeseries([1;1],[0;cfg.stopTime]));
mw.assignin('STEP7C_id_ref_ts',timeseries([0;0],[0;cfg.stopTime]));
mw.assignin('STEP7C_iq_ref_ts',timeseries([0;0],[0;cfg.stopTime]));
values=struct('CONTROL_BACKEND',cfg.backend,'FPGA_Cosim_Enable',1, ...
 'FPGA_Cosim_Input_Mode',1,'FPGA_Reference_Mode',1, ...
 'FPGA_Cosim_Ts_s',cfg.commTs,'STEP7C_Comm_Ts_s',cfg.commTs);
names=fieldnames(values);
for k=1:numel(names), assignin('base',names{k},values.(names{k})); end
end
