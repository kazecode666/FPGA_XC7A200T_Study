function step7d_compare_convergence(reportDir)
assert(~isfolder(reportDir),'Step7D:ExistingReport','Use a fresh report directory.'); mkdir(reportDir);
a=step7d_run_scenario('convergence_prefix',1,1e-6,fullfile(reportDir,'one_us'));
b=step7d_run_scenario('convergence_prefix',1,.5e-6,fullfile(reportDir,'half_us'));
assert(isequal(a.time_s,b.time_s),'Step7D:ConvergenceGrid','Common performance grids differ.');
names={'iq_A','id_A','v_mmps','x_mm'}; limits=[.01 .01 .25 .005]; delta=zeros(1,4);
for k=1:4, delta(k)=max(abs(a.(names{k})-b.(names{k}))); end
assert(all(isfinite(delta)) && all(delta<=limits),'Step7D:Convergence','Convergence failed: %s',mat2str(delta,17));
for name={'current','speed','position'}
 x=a.control_events.(name{1}); y=b.control_events.(name{1});
 assert(numel(x)==numel(y) && all(abs(x-y)<1e-12),'Step7D:ConvergenceTiming','Outer execution grids differ.');
end
% Compare only commands that became active inside the common horizon.
assert(isequal(a.command_events.active_id,b.command_events.active_id),'Step7D:ConvergenceCommands','Complete command IDs differ.');
assert(numel(a.command_events.accepted_id)==numel(b.command_events.accepted_id),'Step7D:ConvergenceCommands','Accepted counts differ.');
f=fopen(fullfile(reportDir,'convergence.txt'),'w'); fc=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'HORIZON=0.2\nRUNS=%s,%s\nCOMMON_SAMPLES=%d\nDELTA_IQ_ID_V_X=%s\nLIMITS=%s\n',a.run_id,b.run_id,numel(a.time_s),mat2str(delta,17),mat2str(limits,17));
fprintf(f,'COMPLETE_ACTIVE_COMMANDS=%d\nACCEPTED_COMMANDS=%d\nSTEP7D_CONVERGENCE_PASS\n',numel(a.command_events.active_id),numel(a.command_events.accepted_id));
disp('STEP7D_CONVERGENCE_PASS');
end
