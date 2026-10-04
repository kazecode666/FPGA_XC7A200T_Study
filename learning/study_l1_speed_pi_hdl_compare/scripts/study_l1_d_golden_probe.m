function summary=study_l1_d_golden_probe(reportDir,probeDir)
% Diagnose replay timestamp boundaries with actual B1 Ref/Meas observations.
% Observation and input-carrier settings are in memory only; never save B1.
assert(~isfolder(probeDir),'StudyL1D:ExistingProbe','Use a fresh probe directory.'); mkdir(probeDir);
saved=load(fullfile(reportDir,'raw.mat'),'out','cfg','events');
out=saved.out; cfg=saved.cfg; events=saved.events;
if isfield(events,'control_events'), events=events.control_events; end
study=fileparts(fileparts(mfilename('fullpath'))); p=study_l1_init; Ts=p.Ts;
n=round(cfg.stopTime/Ts); integerTime=(0:n)'*Ts; colonTime=(0:Ts:cfg.stopTime)';
assert(numel(integerTime)==numel(colonTime));
fprintf('D_REPLAY_TIME_COLON_ULP_DIFFERENCES %d max_seconds=%.17g\n',nnz(integerTime~=colonTime),max(abs(integerTime-colonTime)));
inputLog={'D_speed_ref','D_speed_meas','D_speed_enable','D_speed_reset','D_speed_tick','D_speed_angle','D_speed_test'};
inputPort={'v_ref_mmps','v_meas_mmps','enable','reset','sample_tick','angle_init','test_mode'};
values=zeros(n+1,7);
for k=1:7, values(:,k)=observed(out,inputLog{k},integerTime,cfg.commTs); end
eventIndex=find(values(:,5)>0 & [false;values(1:end-1,5)==0]);
assert(numel(eventIndex)==numel(events.speed));
[t,c]=logged(out,'D_speed_result_count'); resultIndex=find(diff(c)==1)+1; resultTime=t(resultIndex);
names={'iq_ref_A','iq_unlimited_A','integrator_A','saturation_active','integrator_next_A', ...
 'previous_excess_A','excess_next_A','hard_reset','int_reset','iq_limited_A','error_mmps','P_A','KiTs_A','AW_A'};
fl=[15 30 30 0 30 30 30 0 0 30 20 30 30 30];
observedRaw=zeros(numel(eventIndex),14);
for k=1:14
 ts=out.logsout.get(['D_hdl_speed_' names{k}]).Values;
 observedRaw(:,k)=holdGrid(double(ts.Time(:)),rawCode(ts.Data(:),fl(k)),resultTime,cfg.commTs);
end
F=fimath('RoundingMethod','Convergent','OverflowAction','Saturate');
refRaw=double(storedInteger(fi(values(eventIndex,1),true,32,20,F)));
measRaw=double(storedInteger(fi(values(eventIndex,2),true,32,20,F)));
gold='speed_pi_fixed'; assert(~bdIsLoaded(gold)); load_system(fullfile(study,'models',[gold '.slx']));
closeGold=onCleanup(@()close_system(gold,0)); %#ok<NASGU>
oldConfig=Simulink.fileGenControl('getConfig');
restore=onCleanup(@()Simulink.fileGenControl('setConfig','config',oldConfig)); %#ok<NASGU>
Simulink.fileGenControl('set','CacheFolder',fullfile(probeDir,'cache'),'CodeGenFolder',fullfile(probeDir,'codegen'),'createDir',true);
for k=1:2
 labels={'Ref','Meas'}; ph=get_param([gold '/PI/' labels{k}],'PortHandles');
 set_param(ph.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',['D_probe_' labels{k}]);
end
inports=find_system(gold,'SearchDepth',1,'BlockType','Inport'); originalInterp=cell(size(inports));
for k=1:numel(inports)
 originalInterp{k}=get_param(inports{k},'Interpolate');
 fprintf('D_ORIGINAL_ROOT_INPUT %s Interpolate=%s SampleTime=%s\n',get_param(inports{k},'Name'),get_param(inports{k},'Interpolate'),get_param(inports{k},'SampleTime'));
end
mode={'colon_default','integer_default','colon_explicit_zoh','integer_explicit_zoh'};
summary=struct('colon_vs_integer_different_timestamps',nnz(integerTime~=colonTime), ...
 'maximum_timestamp_difference_s',max(abs(integerTime-colonTime)),'runs',struct([]));
for m=1:4
 explicit=m>=3; time=colonTime; if m==2 || m==4, time=integerTime; end
 ds=Simulink.SimulationData.Dataset;
 for k=1:7
  a=values(:,k); if k<=2, a=fi(a,true,32,20,F); elseif k~=5, a=logical(a); end
  stream=timeseries(a,time); if explicit, stream=setinterpmethod(stream,'zoh'); end
  ds=ds.addElement(stream,inputPort{k});
 end
 for k=1:numel(inports), if explicit, interp='off'; else, interp=originalInterp{k}; end; set_param(inports{k},'Interpolate',interp); end
 si=Simulink.SimulationInput(gold).setExternalInput(ds);
 si=si.setModelParameter('StopTime',num2str(integerTime(end),17),'SaveOutput','on','SaveFormat','Dataset', ...
  'OutputSaveName','yout','ReturnWorkspaceOutputs','on','LimitDataPoints','off','SignalLogging','on','SignalLoggingName','logsout');
 g=sim(si); expected=zeros(size(observedRaw));
 for k=1:14, a=rawCode(g.yout.getElement(k).Values.Data(:),fl(k)); expected(:,k)=a(eventIndex); end
 observedIngress=zeros(numel(eventIndex),2);
 for k=1:2
  labels={'Ref','Meas'}; z=g.logsout.get(['D_probe_' labels{k}]).Values;
  [tt,index]=unique(double(z.Time(:)),'last'); a=rawCode(z.Data(:),20); a=a(index);
  observedIngress(:,k)=holdGrid(tt,a,integerTime(eventIndex),Ts);
 end
 diffPorts=sum(expected~=observedRaw,1);
 ingressDiff=any(observedIngress~=[refRaw measRaw],2);
 record=struct('name',mode{m},'explicit_zoh',explicit,'raw_mismatches',sum(diffPorts), ...
  'port_mismatch_counts',diffPorts,'ingress_mismatched_events',nnz(ingressDiff), ...
  'ingress_mismatched_event_ids',find(ingressDiff)','pass',all(diffPorts==0));
 summary.runs=[summary.runs record]; %#ok<AGROW>
 data=[(1:numel(eventIndex))' integerTime(eventIndex) time(eventIndex) refRaw measRaw observedIngress ...
  observedRaw(:,11) expected(:,11) expected observedRaw];
 columns={'event_id','solver_source_time_s','dataset_source_time_s','expected_ref_raw','expected_meas_raw', ...
  'actual_B1_ref_raw','actual_B1_meas_raw','RTL_error_raw','B1_error_raw'};
 columns=[columns strcat('B1_',names) strcat('RTL_',names)];
 writetable(array2table(data,'VariableNames',columns),fullfile(probeDir,[mode{m} '.csv']));
 fprintf('D_REPLAY_PROBE %s raw_mismatches=%d ingress_mismatched_events=%d\n',mode{m},record.raw_mismatches,record.ingress_mismatched_events);
end
f=fopen(fullfile(probeDir,'summary.json'),'w'); assert(f>=0); closeFile=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'%s\n',jsonencode(summary,'PrettyPrint',true));
end
function [t,y]=logged(out,name)
ts=out.logsout.get(name).Values; [t,index]=unique(double(ts.Time(:)),'last'); y=double(ts.Data(:)); y=y(index);
end
function y=rawCode(a,fl)
if isfi(a), y=double(storedInteger(a)); else, y=double(a)*2^fl; end
assert(all(y==fix(y)) && all(isfinite(y)));
end
function y=observed(out,name,q,dt)
[t,a]=logged(out,name); y=holdGrid(t,a,q,dt);
end
function y=holdGrid(t,a,q,dt)
it=round(t/dt); iq=round(q/dt); assert(all(abs(t-it*dt)<1e-12) && all(abs(q-iq*dt)<1e-12));
assert(all(diff(it)>0)); y=interp1(it,a,iq,'previous','extrap');
end
