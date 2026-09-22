function step7d_report_descriptive_metrics(reportDir)
% Descriptive full-rate metrics only: no new acceptance thresholds or PASS.
names={'speed_ideal','speed_deadtime','position_ideal','position_deadtime','position_negative_deadtime'};
for k=1:numel(names)
 d=fullfile(reportDir,names{k});
 txt=fileread(fullfile(d,'run_summary.txt')); p=regexp(txt,'RAW_DIR=([^\r\n]+)','tokens','once');
 a=load(fullfile(p{1},'result.mat'),'r','full'); r=a.r; s=a.full;
 f=fopen(fullfile(d,'descriptive_metrics.txt'),'w'); assert(f>=0); c=onCleanup(@()fclose(f));
 fprintf(f,'RUN_ID=%s\nDESCRIPTIVE_ONLY=1\nRAW_DIR=%s\n',r.run_id,p{1});
 fprintf(f,'POSITION_REFERENCE=live Host x_ref_mm; SPEED_REFERENCE=actual managed v_ref_mmps\n');
 pairs={'v_mmps','v_ref_mmps'};
 if startsWith(names{k},'position'), pairs=[{'x_mm','x_ref_mm'};pairs]; end
 for pair=pairs'
  actual=s.(pair{1}); ref=s.(pair{2});
  reference=interp1(ref.t,ref.y,actual.t,'previous','extrap');
  e=reference-actual.y; [peak,ix]=max(abs(e));
  fprintf(f,'%s_FULL_RATE_N=%d INTERVAL_S=[%.17g,%.17g] ERROR_ABS_MAX=%.17g PEAK_TIME_S=%.17g ERROR_RMSE=%.17g\n',pair{1},numel(e),actual.t(1),actual.t(end),peak,actual.t(ix),sqrt(mean(e.^2)));
 end
 for n={'ia_A','ib_A','ic_A','v_mmps'}
  z=s.(n{1}); [peak,ix]=max(abs(z.y));
  fprintf(f,'%s_ABS_PEAK=%.17g PEAK_TIME_S=%.17g N=%d\n',n{1},peak,z.t(ix),numel(z.y));
 end
 tick=r.control_events.speed;
 unlimited=interp1(s.iq_unlimited.t,s.iq_unlimited.y,tick,'previous','extrap');
 limited=interp1(s.iq_limited.t,s.iq_limited.y,tick,'previous','extrap');
 fprintf(f,'IQ_LIMIT_FRACTION_SPEED_TASK_GRID=%.17g N=%d\n',mean(abs(unlimited-limited)>1e-12),numel(tick));
 % Describe recovery using a fixed 0.5 mm/s band, even for deadtime.
 % Each interval starts at ramp completion or load transition and ends at
 % the next request/load event. Recovery is the first full-rate sample after
 % the last band violation; NaN means no sustained recovery in that interval.
 if startsWith(names{k},'speed')
  windows=[.15 .20;.20 .25;.25 .30;.40 .50;.60 .75;.85 .90;.90 1.05;1.05 1.20];
  v=s.v_mmps; reference=interp1(s.v_ref_mmps.t,s.v_ref_mmps.y,v.t,'previous','extrap');
  ticks=round(v.t/r.cfg.commTs);
  assert(all(abs(v.t-ticks*r.cfg.commTs)<1e-12));
  err=abs(reference-v.y);
  fprintf(f,'RECOVERY_BAND_MMPS=0.5; measured after last violation until next event; NaN=not recovered; no acceptance gate\n');
  for j=1:size(windows,1)
   w=windows(j,:); edges=round(w/r.cfg.commTs); ix=find(ticks>=edges(1) & ticks<edges(2)); bad=find(err(ix)>.5,1,'last');
   if isempty(bad), elapsed=(ticks(ix(1))-edges(1))*r.cfg.commTs;
   elseif bad==numel(ix), elapsed=NaN;
   else, elapsed=(ticks(ix(bad+1))-edges(1))*r.cfg.commTs; end
   fprintf(f,'RECOVERY_INTERVAL_S=%s RECOVERY_S=%.17g SPEED_ERROR_PEAK_MMPS=%.17g N=%d\n',mat2str(w),elapsed,max(err(ix)),numel(ix));
  end
 end
 clear c
end
disp('STEP7D_DESCRIPTIVE_METRICS_WRITTEN');
end
