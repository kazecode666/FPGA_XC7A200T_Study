function pmlsm_check_name_equivalence(baselineDir,reportDir)
% Compare the same dynamic 0.2 s position-start scenario before/after naming.
root=fileparts(fileparts(mfilename('fullpath')));
f=fopen(fullfile(reportDir,'numeric_equivalence.txt'),'w'); assert(f>0);
c=onCleanup(@()fclose(f)); %#ok<NASGU>
fields={'time_s','x_ref_mm','x_mm','v_ref_mmps','v_mmps','id_ref_A','iq_ref_A', ...
 'id_A','iq_A','ia_A','ib_A','ic_A','theta_rad','we_radps','outer_integrator', ...
 'iq_unlimited','iq_limited','vd','vq','bridge_enable','cmp_active','duty_selected'};
for backend={'legacy','fpga'}
 label=backend{1};
 a=load(fullfile(baselineDir,[label '_before.mat'])); an=fieldnames(a); a=a.(an{1});
 b=load(fullfile(baselineDir,[label '_after.mat'])); bn=fieldnames(b); b=b.(bn{1});
 assert(a.cfg.backend==b.cfg.backend && strcmp(a.cfg.name,b.cfg.name));
 assert(a.time_s(end)==.2 && max(abs(a.x_mm))>0,'Dynamic movement required.');
 for k=1:numel(fields)
  name=fields{k}; x=a.(name); y=b.(name); assert(isequal(size(x),size(y)));
  d=max(abs(double(x(:))-double(y(:)))); assert(isfinite(d) && d<=1e-10);
  fprintf(f,'%s.%s.MAX_ABS_DIFF=%.17g\n',label,name,d);
 end
 old=load(fullfile(root,'.Xil','step7d',a.run_id,'simulation_output.mat'),'out');
 new=load(fullfile(root,'.Xil','step7d',b.run_id,'simulation_output.mat'),'out');
 available=new.out.who;
 assert(all(ismember({'motor_control_monitor','fpga_interface_monitor'},available)));
 assert(~any(ismember({'step7c_monitor','fpga_monitor'},available)));
 for kind={'motor','fpga'}
  x=pmlsm_get_monitor(old.out,kind{1}); y=pmlsm_get_monitor(new.out,kind{1});
  assert(isequal(x.Time,y.Time));
  d=max(abs(double(x.Data(:))-double(y.Data(:)))); assert(isfinite(d) && d<=1e-10);
  fprintf(f,'%s.%s_FULL_RATE_LOG.MAX_ABS_DIFF=%.17g\n',label,kind{1},d);
 end
 fprintf(f,'%s.FORMAL_LOGS_PRESENT=1\n%s.ARCHIVED_LOG_COMPATIBILITY_PASS=1\n',label,label);
end
fprintf(f,'LIMIT=1e-10\nDURATION_s=0.2\nNAME_MIGRATION_NUMERIC_PASS=1\n');
disp('NAME_MIGRATION_NUMERIC_PASS');
end
