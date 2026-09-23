function ts=pmlsm_get_monitor(out,kind)
% Read current formal log names, with compatibility for archived raw results.
switch kind
 case 'motor', names={'motor_control_monitor','step7c_monitor'};
 case 'fpga', names={'fpga_interface_monitor','fpga_monitor'};
 otherwise, error('PMLSM:MonitorKind','Unknown monitor kind: %s',kind);
end
available=out.who;
for k=1:numel(names)
 if any(strcmp(available,names{k})), ts=out.get(names{k}); return; end
end
error('PMLSM:MissingMonitor','Missing monitor: %s',strjoin(names,', '));
end
