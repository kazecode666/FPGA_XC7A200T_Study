function result=step7d_test_interactive_cosim()
% Short repeatable acceptance for Issue #35; ordinary model runs only.
original=struct('pwd',pwd,'path',path,'envPath',getenv('PATH'), ...
 'vivado',getenv('XILINX_VIVADO'));
result=struct('fpga_runs',0,'legacy_runs',0,'duty_error',0);
for backend=[1 0 1]
 s=pmlsm_prepare_interactive_cosim('backend',backend,'scenario','fresh_start');
 cleanup=onCleanup(@pmlsm_end_interactive_cosim);
 assert(abs(str2double(get_param(s.model,'FixedStep'))-1e-6)<1e-15);
 assert(evalin('base','CONTROL_BACKEND')==backend);
 assert(evalin('base','FPGA_Cosim_Enable')==1 && ...
  evalin('base','FPGA_Cosim_Input_Mode')==1 && ...
  evalin('base','FPGA_Reference_Mode')==1);
 if backend==1
  h=find_system(s.model,'MatchFilter',@Simulink.match.allVariants,'Name','HDL_Cosimulation');
  portTimes=str2num(get_param(h{1},'PortTimes')); %#ok<ST2NM>
  assert(numel(portTimes)==19 && all(abs(portTimes(12:end)-1e-6)<1e-15));
 end
 repetitions=1+double(backend==1);
 for run=1:repetitions
  out=sim(s.model); monitor=pmlsm_get_monitor(out,'motor'); data=double(monitor.Data);
  assert(size(data,1)==20001 && all(data(:,22)==0) && all(data(:,23)==0));
  if backend==1
   assert(data(end,20)==1 && data(end,18)>0 && data(end,19)>0);
   for phase=1:3
    signal=out.logsout.get(sprintf('selected_duty_%d',phase));
    ts=signal.Values; ticks=round(double(ts.Time(:))*1e6)+1;
    assert(all(ticks>=1 & ticks<=size(data,1)));
    err=max(abs(double(ts.Data(:))-data(ticks,11+phase)/2500));
    result.duty_error=max(result.duty_error,err);
    assert(err<=1e-12,'PMLSM:DutyMismatch','Plant duty differs from active CMP/2500.');
   end
   result.fpga_runs=result.fpga_runs+1;
  else
   result.legacy_runs=result.legacy_runs+1;
  end
 end
 clear cleanup
 assert(strcmp(pwd,original.pwd) && strcmp(path,original.path) && ...
  strcmp(getenv('PATH'),original.envPath) && strcmp(getenv('XILINX_VIVADO'),original.vivado));
end
fprintf('ISSUE35_INTERACTIVE_PASS fpga_runs=%d legacy_runs=%d duty_error=%.12g\n', ...
 result.fpga_runs,result.legacy_runs,result.duty_error);
end
