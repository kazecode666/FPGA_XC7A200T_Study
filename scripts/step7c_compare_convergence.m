function delta=step7c_compare_convergence
a=step7c_run_scenario('convergence',1e-6); b=step7c_run_scenario('convergence',.5e-6);
assert(numel(b.time)==2*numel(a.time)-1 && max(abs(a.time-b.time(1:2:end)))<1e-15);
cols=[4 3 9 8]; delta=max(abs(a.data(:,cols)-b.data(1:2:end,cols)),[],1);
assert(all(delta<[.05 .05 2 .02]),'STEP7C_CONVERGENCE_FAILED');
for r={a,b}
    q=r{1}; assert(all(q.rangeFlags==0) && all(q.data(:,22:23)==0,'all'));
    ix=find(diff(q.data(:,18))>0)+1; assert(all(abs(diff(q.time(ix))-1e-4)<1e-12));
end
counts=[max(a.data(:,18:19));max(b.data(:,18:19))]; assert(isequal(counts(1,:),counts(2,:)));
root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'simulink模型'));
m='PMLSM_ThreeLoop_Simple'; load_system(m); c=onCleanup(@() close_system(m,0)); %#ok<NASGU>
h=[m '/FPGA_HDL_Cosim/HDL_Backend_Variant/FPGA_Enabled/HDL_Cosimulation'];
ts=str2num(get_param(h,'PortTimes')); assert(all(abs(ts(12:end)-1e-6)<1e-15)); %#ok<ST2NM>
assert(evalin('base','CONTROL_BACKEND')==0);
f=fopen(fullfile(root,'docs','reports','step7c','convergence_1us_vs_0p5us.txt'),'w'); cf=onCleanup(@() fclose(f)); %#ok<NASGU>
fprintf(f,'horizon=0.012 common_samples=%d interpolation=none\n',numel(a.time));
fprintf(f,'max_delta_iq_A_id_A_v_mmps_x_mm=%s\nlimits=[0.05 0.05 2 0.02]\n',mat2str(delta,17));
fprintf(f,'accepted_active_counts_1us_0p5us=%s\ncontrol_period=0.0001\nSAVED_PORT_TIMES=1e-6 SAVED_DEFAULT_BACKEND=0\nSTEP7C_CONVERGENCE_PASS\n',mat2str(counts));
fprintf('STEP7C_CONVERGENCE_PASS deltas=%s\n',mat2str(delta,10));
end
