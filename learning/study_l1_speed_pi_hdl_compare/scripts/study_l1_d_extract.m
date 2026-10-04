function r=study_l1_d_extract(out,cfg,events,implementation,reportDir)
% Extract actual logs through the same Step7D interfaces and acceptance data.
% The standard extraction below is copied from frozen step7d_run_scenario;
% only the run metadata and raw-evidence destination belong to Study-L1 D.
assert(isfolder(reportDir));
assert(isfield(cfg,'effective_config'),'StudyL1D:EffectiveConfig','Supply actual post-InitFcn configuration audit.');
if isfield(events,'control_events'), events=events.control_events; end
commTs=cfg.commTs; backend=cfg.backend; name=cfg.name; rawDir=reportDir;
r=struct('cfg',cfg,'effective_config',cfg.effective_config,'version',version, ...
 'run_id',[cfg.name '_' implementation],'control_events',events,'time_s',(0:1e-4:cfg.stopTime)');
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
  monitorMap={'accepted_id',18;'active_id',19;'active_valid',20;'needs_reset',23;'fault_code',22};
  for mapIndex=1:size(monitorMap,1)
   r.(monitorMap{mapIndex,1})=holdTicks(mt,md(:,monitorMap{mapIndex,2}),t,commTs);
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

% Publish every actual FOC command pairing, including the final in-flight
% command whose active time falls beyond the finite simulation horizon.
study_l1_d_export_commands(r,reportDir);
% New D evidence is observed on the communication grid; count increments
% capture pulses that are shorter than the 1 us observation interval.
[ct,hardwareCount]=logged(out,'D_speed_result_count');
[it,iq]=logged(out,'D_speed_iq');
iq=holdTicks(it,iq,ct,commTs);
[st,sourceCount]=logged(out,'D_speed_source_count');
sourceCount=holdTicks(st,sourceCount,ct,commTs);
hardwareResultIndex=find(diff(hardwareCount)==1)+1; sourceIndex=find(diff(sourceCount)==1)+1;
assert(all(diff(hardwareCount)==0 | diff(hardwareCount)==1) && all(diff(sourceCount)==0 | diff(sourceCount)==1), ...
 'StudyL1D:CountSequence','Source/result counter skipped or reversed an event.');
assert(numel(hardwareResultIndex)==numel(events.speed) && numel(sourceIndex)==numel(events.speed), ...
 'StudyL1D:CounterCoverage','Actual counters do not cover the measured speed events.');
assert(all(hardwareCount<=sourceCount),'StudyL1D:PrematureCompletion','Result completed before its source event.');
source=events.speed(:); hardwareObserved=ct(hardwareResultIndex); sourceObserved=ct(sourceIndex);
assert(all(sourceObserved-source>=-1e-12 & sourceObserved-source<=commTs+1e-12), ...
 'StudyL1D:SourceObservation','Hardware source capture is not aligned with actual speed-task events.');
hardwareLaunchCycle=observedValue(out,'D_speed_launch_cycle',ct(sourceIndex),commTs);
hardwareResultCycle=observedValue(out,'D_speed_result_cycle',hardwareObserved,commTs);
clockEvidence=struct;
if strcmp(implementation,'original')
 % The hardware monitor in this case belongs to an unselected fixed-point
 % shadow. Its later result flag is not the original float PI completion.
 [present,resultIndex]=ismember(round(source/commTs),round(ct/commTs));
 assert(all(present) && all(abs(ct(resultIndex)-source)<1e-12), ...
  'StudyL1D:OriginalEventGrid','Actual Simulink speed executions must lie on the observed grid.');
 count=zeros(size(ct)); count(resultIndex)=1; count=cumsum(count);
 observed=source; latency=0; physical=source;
 launchCycle=zeros(size(source)); resultCycle=zeros(size(source));
 r.speed_shadow=struct('result_count_time_s',ct,'result_count',hardwareCount, ...
  'result_observed_time_s',hardwareObserved,'source_observed_time_s',sourceObserved, ...
  'source_count',sourceCount,'input_acceptance_cycle',hardwareLaunchCycle, ...
  'result_cycle',hardwareResultCycle, ...
  'scope','Unselected fixed-point RTL shadow; these counters are not original Simulink PI result_valid.');
 shadowFile=fullfile(reportDir,'speed_shadow_events.csv');
 assert(~isfile(shadowFile),'StudyL1D:ExistingEvidence','Never overwrite shadow event evidence.');
 shadowData=[source sourceObserved hardwareObserved hardwareLaunchCycle hardwareResultCycle];
 shadowNames={'source_time_s','source_observed_time_s','shadow_result_observed_time_s', ...
  'shadow_input_acceptance_cycle','shadow_result_cycle'};
 writetable(array2table(shadowData,'VariableNames',shadowNames),shadowFile);
 basis='Actual Simulink speed-task execution timestamps; no physical speed RTL pipeline.';
 cycleScope='No original speed RTL pipeline; zero cycle columns are placeholders. Real unselected shadow cycles are stored separately.';
else
 count=hardwareCount; resultIndex=hardwareResultIndex; observed=hardwareObserved;
 launchCycle=hardwareLaunchCycle; resultCycle=hardwareResultCycle;
 cycleLatency=resultCycle-launchCycle;
 assert(all(cycleLatency==1),'StudyL1D:PhysicalLatency','Actual input-acceptance to result counters must differ by one 50 MHz cycle.');
 assert(isfield(cfg,'speed_clock_epoch_s'),'StudyL1D:ClockEpoch','Supply the actual measured fabric counter epoch.');
 [fabricTime,fabricCount]=logged(out,'D_hdl_speed_fabric_cycle');
 running=fabricCount>0;
 assert(any(running) && all(fabricCount(running)==fix(fabricCount(running))), ...
  'StudyL1D:FabricCounter','Invalid actual fabric-cycle counter evidence.');
 firstEdgeNs=observedValue(out,'D_hdl_speed_first_edge_time_ns',fabricTime(running),commTs);
 assert(all(abs(firstEdgeNs*1e-9-20e-9-cfg.speed_clock_epoch_s)<1e-12), ...
  'StudyL1D:ClockEpoch','Supplied epoch must match actual first-posedge $time minus one clock period.');
 % XSI observations need not coincide with a posedge. The observed fabric
 % count denotes the last executed edge, not an edge at the observation time.
 fabricAge=fabricTime(running)-(cfg.speed_clock_epoch_s+fabricCount(running)*20e-9);
 assert(all(fabricAge>=-1e-12 & fabricAge<20e-9+1e-12), ...
  'StudyL1D:ClockEpoch','Observed fabric count must denote an edge within the preceding clock period.');
 assert(all(abs(diff(fabricTime(running))-commTs)<1e-12) && all(diff(fabricCount(running))==50), ...
  'StudyL1D:FabricCounter','Actual fabric counter must advance fifty clocks per 1 us observation.');
 physical=cfg.speed_clock_epoch_s+resultCycle*20e-9;
 measuredAcceptance=cfg.speed_clock_epoch_s+launchCycle*20e-9;
 captureDelay=measuredAcceptance-source;
 assert(all(captureDelay>0 & captureDelay<=20e-9+1e-12), ...
  'StudyL1D:ClockEpoch','Physical input acceptance must follow the source event within one clock period.');
 measuredLatency=physical-source; latency=mean(measuredLatency);
 assert(all(abs(measuredLatency-latency)<1e-12) && all(abs(measuredLatency-captureDelay-20e-9)<1e-12), ...
  'StudyL1D:ClockEpoch','Result must complete one clock after input acceptance with constant physical clock phase.');
 clockEvidence=struct('first_edge_time_ns',firstEdgeNs(1), ...
  'cycle_epoch_s',cfg.speed_clock_epoch_s,'capture_delay_s',mean(captureDelay), ...
  'observation_fabric_age_min_s',min(fabricAge),'observation_fabric_age_max_s',max(fabricAge), ...
  'acceptance_to_result_clocks',1,'fabric_counter_gate_pass',true);
 basis='Actual first-posedge $time minus 20 ns gives cycle-counter epoch; result cycle times 20 ns gives physical result; source-to-capture depends on measured clock phase.';
 cycleScope='Input acceptance, not source launch.';
end
r.speed_pi=struct('implementation',implementation,'latency_s',latency, ...
 'input_event_time_s',source,'physical_result_event_time_s',physical, ...
 'result_event_time_s',observed,'iq_ref_time_s',ct,'iq_ref_A',iq, ...
 'result_count_time_s',ct,'result_count',count,'launch_cycle',launchCycle, ...
 'result_cycle',resultCycle,'source_observed_time_s',sourceObserved, ...
 'physical_timestamp_basis',basis,'launch_cycle_scope',cycleScope,'clock_evidence',clockEvidence);
r.speed_pi_iq_ref_A=holdTicks(ct,iq,t,commTs);
r.speed_result_count=holdTicks(ct,count,t,commTs);
r.speed_new_result=[0;double(diff(r.speed_result_count)>0)];
% Measure transport only when the held PI value changes: equal successive
% values have no distinguishable publication event. Keep Reference_Manager
% and FOC observations separate from the speed core's physical completion.
changed=find(iq(resultIndex)~=[0;iq(resultIndex(1:end-1))]);
publication=zeros(numel(changed),1); firstAccepted=publication; firstActive=publication;
acceptedInside=false(size(publication)); activeInside=acceptedInside;
for k=1:numel(changed)
 j=changed(k); value=iq(resultIndex(j));
 q=find(full.iq_ref_A.t>=physical(j)-1e-12 & full.iq_ref_A.y==value,1);
 assert(~isempty(q),'StudyL1D:ManagedReference','Changed PI result never reached the common Reference_Manager.');
 publication(k)=full.iq_ref_A.t(q);
 a=find(r.command_events.accepted_time_s>=publication(k)-1e-12,1);
 if isempty(a), continue; end % Next FOC transaction can lie beyond stopTime.
 acceptedInside(k)=true;
 assert(abs(r.command_events.accepted_references(a,2)-value)<=2^-16+1e-12, ...
  'StudyL1D:FOCReference','Accepted FOC boundary does not carry the published reference.');
 firstAccepted(k)=r.command_events.accepted_time_s(a);
 id=r.command_events.accepted_id(a);
 v=find(r.command_events.active_id==id,1);
 if ~isempty(v), activeInside(k)=true; firstActive(k)=r.command_events.active_time_s(v); end
end
r.speed_pi.managed_reference_events=struct('changed_result_indices',changed, ...
 'speed_physical_result_time_s',physical(changed),'managed_publish_time_s',publication, ...
 'managed_transport_delay_s',publication-physical(changed), ...
 'first_foc_accepted_time_s',firstAccepted,'first_foc_active_time_s',firstActive, ...
 'accepted_within_horizon',acceptedInside,'active_within_horizon',activeInside, ...
 'scope','Changed PI values only; absent accepted/active times use zero plus a false within_horizon flag; common Reference_Manager and FOC boundary unchanged.');
% Export exact per-event inputs. Quantization matches the frozen B1 model;
% original float case's iq_ref_raw is explicitly its Q15 conversion.
inputNames={'D_speed_ref','D_speed_meas','D_speed_enable','D_speed_reset','D_speed_angle','D_speed_test'};
values=zeros(numel(source),numel(inputNames));
for k=1:numel(inputNames)
 values(:,k)=observedValue(out,inputNames{k},sourceObserved,commTs);
end
F=fimath('RoundingMethod','Convergent','OverflowAction','Saturate');
refRaw=double(storedInteger(fi(values(:,1),true,32,20,F)));
measRaw=double(storedInteger(fi(values(:,2),true,32,20,F)));
actualIQ=iq(resultIndex); iqRaw=double(storedInteger(fi(actualIQ,true,25,15,F)));
assert(all(values(:,3:end)==0 | values(:,3:end)==1,'all'), ...
 'StudyL1D:BooleanInputs','Speed control inputs must be logical values.');
eventData=[source physical observed sourceObserved launchCycle resultCycle refRaw measRaw values(:,3:end) actualIQ iqRaw];
eventNames={'source_time_s','physical_result_time_s','observed_result_time_s','source_observed_time_s', ...
 'input_acceptance_cycle','result_cycle','v_ref_raw','v_meas_raw','enable','pi_reset','angle_init','test_mode','iq_ref_A','iq_ref_raw'};
eventFile=fullfile(reportDir,'speed_events.csv');
assert(~isfile(eventFile),'StudyL1D:ExistingEvidence','Never overwrite speed event evidence.');
writetable(array2table(eventData,'VariableNames',eventNames),eventFile);
trace=[t r.v_ref_mmps r.v_mmps r.speed_pi_iq_ref_A r.iq_A r.speed_result_count r.speed_new_result ...
 r.accepted_id r.active_id r.fault_code r.needs_reset r.x_ref_mm r.x_mm r.iq_ref_A];
traceNames={'time_s','v_ref_mmps','v_mmps','speed_pi_iq_ref_A','iq_A','result_count','new_result', ...
 'accepted_id','active_id','fault_code','needs_reset','x_ref_mm','x_mm','iq_ref_A'};
traceFile=fullfile(reportDir,'trace.csv');
assert(~isfile(traceFile),'StudyL1D:ExistingEvidence','Never overwrite system trace evidence.');
writetable(array2table(trace,'VariableNames',traceNames),traceFile);
% Keep full-rate raw values available to the run validator and local MAT.
r.full_rate=full;
end
function [t,y]=logged(out,name)
ts=out.logsout.get(name).Values;
[t,index]=unique(double(ts.Time(:)),'last'); y=double(ts.Data(:)); y=y(index);
assert(all(isfinite(t)) && all(isfinite(y)),'StudyL1D:NonFiniteLog','Invalid actual log %s',name);
end
function y=observedValue(out,name,q,dt)
[t,x]=logged(out,name); y=holdTicks(t,x,q,dt);
end
function y=holdTicks(t,x,q,dt)
% Unchanged Step7D rule: snap only floating-point noise on the real grid.
it=round(t/dt); iq=round(q/dt);
assert(all(abs(t-it*dt)<1e-12) && all(abs(q-iq*dt)<1e-12),'Step7D:OffTick','Log timestamp is off the communication grid.');
assert(all(diff(it)>0),'Step7D:DuplicateTick','Duplicate source ticks.');
y=interp1(it,x,iq,'previous','extrap');
end
