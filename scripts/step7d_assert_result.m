function metrics=step7d_assert_result(r,cfg)
% Frozen Task7D criteria. Synthetic fixtures only test this evaluator.
required={'time_s','x_ref_mm','x_mm','v_request_mmps','v_ref_mmps','v_mmps','id_ref_A','iq_ref_A', ...
 'id_A','iq_A','ia_A','ib_A','ic_A','theta_rad','we_radps','load_N','pwm_en','pi_reset','bridge_enable','outer_integrator','outer_limit_flags'};
for k=1:numel(required), assert(isfield(r,required{k}),'Step7D:MissingField','Missing %s',required{k}); end
t=r.time_s(:); assert(numel(t)>1 && t(1)==0 && abs(t(end)-cfg.stopTime)<1e-10 && all(diff(t)>0),'Step7D:TimeGrid','Invalid full-duration time grid.');
for k=1:numel(required)
 v=r.(required{k}); assert(isnumeric(v) && numel(v)==numel(t),'Step7D:FieldSize','Bad %s dimensions',required{k});
 assert(all(isfinite(v),'all'),'Step7D:NonFinite','Nonfinite %s',required{k});
end
if cfg.backend==1
 assert(isfield(r,'command_events'),'Step7D:MissingField','Missing command events.');
 ev=r.command_events;
 assert(isfield(ev,'accepted_id') && isfield(ev,'active_id') && ~isempty(ev.accepted_id),'Step7D:CommandSequence','Missing command IDs.');
 assert(all(diff(ev.accepted_id)==1) && all(diff(ev.active_id)==1),'Step7D:CommandSequence','Skipped/repeated command.');
end
metrics=struct('speed',[],'position',[]);
for k=1:size(cfg.windows.speed,1)
 w=cfg.windows.speed(k,:); et=r.control_events.speed; et=et(et>=w(1)-1e-12 & et<w(2)-1e-12);
 assert(numel(et)>=cfg.thresholds.minimumSpeedSamples,'Step7D:EmptyWindow','Insufficient speed samples.');
 vr=holdValue(t,r.v_ref_mmps,et); v=holdValue(t,r.v_mmps,et); e=vr-v;
 vrow=[numel(et),mean(abs(e)),sqrt(mean(e.^2)),max(abs(e)),mean(v),max(vr)-min(vr)]; metrics.speed(k,:)=vrow;
 assert(vrow(6)<=1e-9,'Step7D:UnsettledReference','Reference not steady inside fixed window.');
 assert(vrow(2)<=cfg.thresholds.speedMAE && vrow(3)<=cfg.thresholds.speedRMSE && vrow(4)<=cfg.thresholds.speedMax, ...
  'Step7D:SpeedPerformance','Speed window %d failed: [N MAE RMSE MAX MEAN_V SPAN]=%s',k,mat2str(vrow,8));
 if k==1, assert(vrow(5)>2.5,'Step7D:SpeedDirection','Positive direction failed.'); end
 if k==3, assert(vrow(5)<-2.5,'Step7D:SpeedDirection','Negative direction failed.'); end
end
for k=1:size(cfg.windows.position,1)
 w=cfg.windows.position(k,:); et=r.control_events.position; et=et(et>=w(1)-1e-12 & et<w(2)-1e-12);
 assert(~isempty(et),'Step7D:EmptyWindow','Empty position window.');
 x=holdValue(t,r.x_mm,et); v=holdValue(t,r.v_mmps,et); err=max(abs(cfg.host.Host_Target_mm-x));
 if isfield(r,'window_peaks'), err=max(err,r.window_peaks.position(k,1)); vp=max(abs(v)); vp=max(vp,r.window_peaks.position(k,2)); else, vp=max(abs(v)); end
 metrics.position(k,:)=[numel(et),err,vp];
 assert(err<=cfg.thresholds.positionMax && vp<=cfg.thresholds.positionSpeedMax,'Step7D:PositionPerformance','Position window %d failed.',k);
end
for name={'current','speed','position'}
 et=r.control_events.(name{1}); dt=struct('current',1e-4,'speed',1e-3,'position',1e-2);
 assert(numel(et)>=2 && all(abs(diff(et)-dt.(name{1}))<1e-12),'Step7D:ExecutionTiming','Wrong execution period: %s',name{1});
end
if strcmp(cfg.purpose,'performance') && ~strcmp(cfg.name,'stop_restart_inhibit')
 et=r.control_events.current; et=et(et>=.002 & et<=cfg.stopTime);
 e=holdValue(t,r.iq_ref_A,et)-holdValue(t,r.iq_A,et); metrics.iq_rmse_A=sqrt(mean(e.^2));
 assert(isfinite(metrics.iq_rmse_A) && metrics.iq_rmse_A<=cfg.thresholds.iqRMSE,'Step7D:CurrentPerformance','iq RMSE=%g',metrics.iq_rmse_A);
 assert(r.peaks.id_A<=cfg.thresholds.idMax && r.peaks.iq_A<=1.5 && r.peaks.iq_ref_A<=1+1e-12,'Step7D:CurrentPeak','Current full-rate peak failed.');
 if contains(cfg.name,'position')
  if cfg.host.Host_Target_mm>0, assert(r.peaks.x_max_mm<=1.1,'Step7D:Overshoot','Position overshoot');
  else, assert(r.peaks.x_min_mm>=-1.1,'Step7D:Overshoot','Position overshoot'); end
  assert(all(abs(r.x_ref_mm(t>=.70)-cfg.host.Host_Target_mm)<1e-12),'Step7D:TrajectoryDuration','Host trajectory late.');
 end
end
if cfg.backend==1
 assert(all(r.fault_code==0) && all(r.range_flags==0,'all'),'Step7D:HDLFault','Fault or range flags.');
 if ~strcmp(cfg.name,'stop_restart_inhibit')
  assert(all(r.needs_reset==0),'Step7D:UnexpectedReset','Unexpected needs_reset.');
  assert(all(r.bridge_enable(t>=.001)==1),'Step7D:BridgeInvalid','Normal bridge not valid.');
 end
end
end
function y=holdValue(t,x,q)
% Snap event timestamps onto exact common-grid values within FP tolerance.
dt=t(2)-t(1); index=round(q/dt)+1;
assert(all(index>=1 & index<=numel(t)) && all(abs(t(index)-q)<1e-10),'Step7D:EventGrid','Event outside common grid.');
y=x(index); assert(all(isfinite(y)),'Step7D:NonFinite','Invalid event values.');
end
