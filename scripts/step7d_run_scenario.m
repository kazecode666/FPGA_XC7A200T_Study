function r=step7d_run_scenario(name,backend,commTs,reportDir,options)
% One independent simulation; raw data saved before assertions can throw.
if nargin<5, options=struct; end
cfg=step7d_scenarios(name); cfg.backend=backend; cfg.commTs=commTs;
cfg.canaryEnabled=isfield(options,'canary') && options.canary;
if isfield(options,'probeOnly') && options.probeOnly
 assert(strcmp(name,'speed_ideal')); cfg.stopTime=.2; cfg.purpose='convergence';
 cfg.windows.speed=zeros(0,2); cfg.windows.position=zeros(0,2); cfg.diagnosticOnly=true;
end
assert(~isfolder(reportDir),'Step7D:ExistingReport','Use a new run directory.'); mkdir(reportDir);
root=fileparts(fileparts(mfilename('fullpath'))); runid=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
rawDir=fullfile(root,'.Xil','step7d',runid); mkdir(rawDir);
try
 [si,cfg,cleanup]=step7d_configure_model(cfg); %#ok<ASGLU>
 if isfield(options,'canary') && options.canary
  si=si.setVariable('STEP7C_iq_ref_ts',timeseries([.17;.17],[0;cfg.stopTime]));
  si=si.setVariable('STEP7C_id_ref_ts',timeseries([-.09;-.09],[0;cfg.stopTime]));
  for p={'FPGA_Smoke_ia_A',.2;'FPGA_Smoke_ib_A',-.1;'FPGA_Smoke_ic_A',-.1;'FPGA_Smoke_theta_rad',.3;'FPGA_Smoke_we_radps',2;'FPGA_Smoke_iq_ref_A',-.3;'FPGA_Smoke_id_ref_A',.3;'FPGA_Smoke_vdc_V',36}'
   si=si.setVariable(p{1},p{2});
  end
 end
 out=sim(si);
 save(fullfile(rawDir,'simulation_output.mat'),'out','cfg','-v7.3');
 global STEP7D_RUN_EVENTS STEP7D_RUN_EFFECTIVE
 r=struct('cfg',cfg,'effective_config',STEP7D_RUN_EFFECTIVE,'version',version,'run_id',runid, ...
  'control_events',STEP7D_RUN_EVENTS,'time_s',(0:1e-4:cfg.stopTime)');
 t=r.time_s;
 pairs={'x_ref_mm','x_ref_mm';'x_mm','x_mm';'v_ref_mmps','v_ref_mmps';'v_mmps','v_mmps'; ...
 'id_ref_A','id_ref_A';'iq_ref_A','iq_ref_A';'id_A','id_A';'iq_A','iq_A';'ia_A','ia_A';'ib_A','ib_A';'ic_A','ic_A'; ...
 'theta_rad','theta_rad';'we_radps','we_radps';'outer_integrator','outer_integrator';'iq_unlimited','iq_unlimited';'iq_limited','iq_limited'; ...
 'actual_speed','v_request_mmps';'actual_load','load_N';'actual_pwm','pwm_en';'actual_reset','pi_reset';'selected_enable','bridge_enable';'vd','vd';'vq','vq'};
 full=struct;
 for k=1:size(pairs,1)
  ts=out.logsout.get(pairs{k,1}).Values; [tt,idx]=unique(double(ts.Time(:)),'last'); yy=double(ts.Data(:)); yy=yy(idx);
  assert(all(isfinite(yy)),'Step7D:NonFinite','Nonfinite raw %s',pairs{k,1});
  if tt(1)>0
   assert(any(strcmp(pairs{k,1},{'outer_integrator','iq_unlimited','iq_limited'})),'Step7D:InitialOutput','Unknown initial output');
   tt=[0;tt]; yy=[0;yy];
  end
  full.(pairs{k,2})=struct('t',tt,'y',yy);
  r.(pairs{k,2})=holdTicks(tt,yy,t,commTs);
 end
 r.outer_limit_flags=double(abs(r.iq_unlimited-r.iq_limited)>1e-12);
 r.peaks=struct;
 for k={'id_A','iq_A','iq_ref_A','ia_A','ib_A','ic_A','v_mmps'}
  r.peaks.(k{1})=max(abs(full.(k{1}).y));
 end
 r.peaks.x_min_mm=min(full.x_mm.y); r.peaks.x_max_mm=max(full.x_mm.y);
 r.window_peaks.position=zeros(size(cfg.windows.position));
 for k=1:size(cfg.windows.position,1)
  w=cfg.windows.position(k,:); ix=full.x_mm.t>=w(1) & full.x_mm.t<w(2); iv=full.v_mmps.t>=w(1) & full.v_mmps.t<w(2);
  r.window_peaks.position(k,:)=[max(abs(full.x_mm.y(ix)-cfg.host.Host_Target_mm)),max(abs(full.v_mmps.y(iv)))];
 end
 r.adapter_inputs=struct; r.quantized_inputs=struct; r.interface=struct;
 map={'ia','ia_A';'ib','ib_A';'ic','ic_A';'theta_e','theta_rad';'we','we_radps';'id_ref','id_ref_A';'iq_ref','iq_ref_A'};
 for k=1:size(map,1)
  s=out.logsout.get(['Select_' map{k,1}]).Values; q=out.logsout.get(['Quantize_' map{k,1}]).Values;
  st=double(s.Time(:)); sy=double(s.Data(:)); qt=double(q.Time(:)); qy=double(q.Data(:));
  r.adapter_inputs.(map{k,1})=holdTicks(st,sy,t,commTs); r.quantized_inputs.(map{k,1})=holdTicks(qt,qy,t,commTs);
  reference=holdTicks(full.(map{k,2}).t,full.(map{k,2}).y,st,commTs);
  r.interface.([map{k,1} '_max_error'])=max(abs(sy-reference));
  assert(r.interface.([map{k,1} '_max_error'])<=1e-12,'Step7D:LiveSource','Adapter mismatch: %s error=%.17g; raw evidence: %s',map{k,1},r.interface.([map{k,1} '_max_error']),rawDir);
  if any(strcmp(map{k,1},{'id_ref','iq_ref'}))
   qs=holdTicks(st,sy,qt,commTs); err=max(abs(qy-qs));
   assert(err<=2^-16+1e-12,'Step7D:Quantization','Q15 reference error'); r.interface.([map{k,1} '_quant_error'])=err;
  end
 end
 monitor=pmlsm_get_monitor(out,'motor'); mt=double(monitor.Time(:)); md=double(monitor.Data);
 r.cmp_active=holdTicks(mt,md(:,12:14),t,commTs); r.duty_selected=zeros(numel(t),3);
 for k=1:3
  ts=out.logsout.get(sprintf('duty_%d',k)).Values; tt=double(ts.Time(:)); yy=double(ts.Data(:)); r.duty_selected(:,k)=holdTicks(tt,yy,t,commTs);
  if backend==1
   cmp=holdTicks(mt,md(:,11+k),tt,commTs); assert(max(abs(yy-cmp/2500))<=1e-12,'Step7D:DutyBoundary','Duty differs from active CMP/2500');
  end
 end
 r.command_events=struct; r.state_events=struct;
 if backend==1
  for pair={'accepted_id',18;'active_id',19;'active_valid',20;'needs_reset',23;'fault_code',22}'
   r.(pair{1})=holdTicks(mt,md(:,pair{2}),t,commTs);
  end
  ai=find(diff(md(:,18))~=0)+1; vi=find(diff(md(:,19))~=0)+1;
  r.command_events=struct('accepted_time_s',mt(ai),'accepted_id',md(ai,18),'active_time_s',mt(vi),'active_id',md(vi,19));
  r.command_events.accepted_references=md(ai,1:2);
  [matched,idx]=ismember(md(vi,19),md(ai,18)); assert(all(matched),'Step7D:CommandPair','Active command has no accepted ID');
  r.command_events.active_paired_references=r.command_events.accepted_references(idx,:);
  delay=mt(vi)-mt(ai(idx)); assert(all(abs(delay-50e-6)<=commTs+1e-12),'Step7D:CommandDelay','Accepted/active delay');
  assert(all(abs(diff(mt(ai))-1e-4)<=1e-12) || strcmp(name,'stop_restart_inhibit'),'Step7D:CommandPeriod','Transaction period');
  r.command_events.accepted_to_active_s=delay;
  state=any(diff(md(:,[20 21 22 23]),1,1)~=0,2); si_idx=[1;find(state)+1];
  r.state_events=struct('time_s',mt(si_idx),'valid_bridge_fault_needs_reset',md(si_idx,[20 21 22 23]));
  f=pmlsm_get_monitor(out,'fpga'); r.range_flags=max(double(f.Data(:,12:end)),[],1);
  assert(all(md(:,22)==0) && all(r.range_flags==0),'Step7D:HDLFault','Full-rate fault/range flag');
  if ~strcmp(name,'stop_restart_inhibit'), assert(all(md(:,23)==0),'Step7D:UnexpectedReset','Full-rate unexpected reset'); end
 else
  for n={'accepted_id','active_id','active_valid','needs_reset','fault_code','range_flags'}, r.(n{1})=[]; end
 end
 save(fullfile(rawDir,'result.mat'),'r','full','-v7.3');
 f=fopen(fullfile(reportDir,'run_summary.txt'),'w'); cf=onCleanup(@()fclose(f)); %#ok<NASGU>
 fprintf(f,'RUN_ID=%s\nRAW_DIR=%s\nCFG=%s\nEFFECTIVE=%s\nINTERFACE=%s\nPEAKS=%s\n',runid,rawDir,jsonencode(cfg),jsonencode(r.effective_config),jsonencode(r.interface),jsonencode(r.peaks));
 r.metrics=step7d_assert_result(r,r.cfg); fprintf(f,'METRICS=%s\nSTEP7D_SCENARIO_GATE_PASS %s purpose=%s\n',jsonencode(r.metrics),name,cfg.purpose);
 save(fullfile(rawDir,'result.mat'),'r','full','-v7.3');
 fprintf('STEP7D_SCENARIO_GATE_PASS %s purpose=%s\n',name,cfg.purpose);
 clear cleanup
catch e
 f=fopen(fullfile(reportDir,'failure.txt'),'w'); fprintf(f,'%s\n%s\nRAW_DIR=%s\n',e.identifier,getReport(e,'extended','hyperlinks','off'),rawDir); fclose(f);
 rethrow(e)
end
end
function y=holdTicks(t,x,q,dt)
% Triggered and base-rate loggers can encode the same tick differently.
% Only snap within floating-point tolerance; retain every physical delay.
it=round(t/dt); iq=round(q/dt);
assert(all(abs(t-it*dt)<1e-12) && all(abs(q-iq*dt)<1e-12),'Step7D:OffTick','Log timestamp is off the communication grid.');
assert(all(diff(it)>0),'Step7D:DuplicateTick','Duplicate source ticks.');
y=interp1(it,x,iq,'previous','extrap');
end
