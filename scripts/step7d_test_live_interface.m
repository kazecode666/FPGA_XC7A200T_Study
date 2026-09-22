function step7d_test_live_interface(reportDir)
% Real HDL probes and independently loaded, full-rate canary comparison.
assert(~isfolder(reportDir)); mkdir(reportDir);
r=step7d_run_scenario('speed_ideal',1,1e-6,fullfile(reportDir,'normal'),struct('probeOnly',true));
c=step7d_run_scenario('speed_ideal',1,1e-6,fullfile(reportDir,'canary'),struct('probeOnly',true,'canary',true));
assert(isequal(r.adapter_inputs,c.adapter_inputs) && isequal(r.quantized_inputs,c.quantized_inputs));
assert(isequal(r.iq_A,c.iq_A) && isequal(r.command_events,c.command_events));
root=fileparts(fileparts(mfilename('fullpath')));
a=load(fullfile(root,'.Xil','step7d',r.run_id,'simulation_output.mat'),'out');
b=load(fullfile(root,'.Xil','step7d',c.run_id,'simulation_output.mat'),'out');
for n={'ia','ib','ic','theta_e','we','id_ref','iq_ref','pi_reset','run_enable'}
 for p={'Select_','Quantize_'}
  name=[p{1} n{1}]; x=a.out.logsout.get(name).Values; y=b.out.logsout.get(name).Values;
  assert(isequal(x.Time,y.Time) && isequal(x.Data,y.Data),'Step7D:CanaryLeak','Unselected canary changed full-rate %s',name);
 end
end
f=fopen(fullfile(reportDir,'interface_gate.txt'),'w'); fc=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'NORMAL_RUN=%s\nCANARY_RUN=%s\nFULL_RATE_SELECTED_AND_QUANTIZED_EQUAL=1\n',r.run_id,c.run_id);
for n={'current','speed','position'}
 t=r.control_events.(n{1}); fprintf(f,'%s first=%.17g last=%.17g count=%d\n',n{1},t(1),t(end),numel(t));
end
fprintf(f,'ACCEPTED_COUNT=%d ACTIVE_COUNT=%d DELAY_RANGE=%s\n',numel(r.command_events.accepted_id),numel(r.command_events.active_id),mat2str([min(r.command_events.accepted_to_active_s),max(r.command_events.accepted_to_active_s)],17));
fprintf(f,'STEP7D_LIVE_INTERFACE_PASS\nSTEP7D_TIMING_PASS\n');
disp('STEP7D_LIVE_INTERFACE_PASS'); disp('STEP7D_TIMING_PASS');
end
