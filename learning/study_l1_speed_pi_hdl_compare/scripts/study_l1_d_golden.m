function evidence=study_l1_d_golden(reportDir)
% Replay actual system inputs through the frozen B1 SLX, never a code oracle.
% Source timestamps are matched by actual tick order. Physical RTL completion
% comes from measured clock ordinals; no waveform shift is fitted or applied.
study=fileparts(fileparts(mfilename('fullpath')));
rawFile=fullfile(reportDir,'raw.mat');
jsonFile=fullfile(reportDir,'bit_true.json');
csvFile=fullfile(reportDir,'bit_true.csv');
assert(isfile(rawFile),'StudyL1D:MissingRaw','Missing actual system simulation output.');
assert(~isfile(jsonFile) && ~isfile(csvFile),'StudyL1D:ExistingEvidence','Never overwrite B1 replay evidence.');
saved=load(rawFile,'out','cfg','events'); out=saved.out; cfg=saved.cfg;
events=saved.events; if isfield(events,'control_events'), events=events.control_events; end
assert(isfield(events,'speed') && isfield(cfg,'speed_clock_epoch_s'));
dt=cfg.commTs; frozen=study_l1_init; Ts=frozen.Ts;
assert(abs(Ts-1e-4)<1e-15 && abs(dt-1e-6)<1e-15);
assert(isfield(cfg,'implementation'));
% Match the discrete solver's n*Ts construction exactly. Colon creates a few
% 1-ulp differences, which can select the previous fixed input at a boundary.
% This sets the replay timestamps, not a fitted shift of the observed RTL.
time=(0:round(cfg.stopTime/Ts))'*Ts;
inputLog={'D_speed_ref','D_speed_meas','D_speed_enable','D_speed_reset', ...
 'D_speed_tick','D_speed_angle','D_speed_test'};
inputPort={'v_ref_mmps','v_meas_mmps','enable','reset','sample_tick','angle_init','test_mode'};
values=zeros(numel(time),7);
for k=1:7
 [t,a]=logged(out,inputLog{k}); values(:,k)=holdGrid(t,a,time,dt);
end
assert(all(values(:,3:end)==0 | values(:,3:end)==1,'all'), ...
 'StudyL1D:BooleanInputs','Actual speed control inputs are not Boolean.');
% Trigger memory initially high; a low sample at zero arms the first rise.
assert(values(1,5)==0,'StudyL1D:TickBoot','Real speed tick must be low at boot.');
eventIndex=find(values(:,5)>0 & [false;values(1:end-1,5)==0]);
source=time(eventIndex); actualSource=events.speed(:);
assert(numel(source)==numel(actualSource) && all(abs(source-actualSource)<1e-12), ...
 'StudyL1D:GoldenSourceEvents','B1 replay tick edges differ from actual speed-task executions.');
assert(~isempty(source) && abs(source(1)-.0009)<1e-12 && all(abs(diff(source)-.001)<1e-12), ...
 'StudyL1D:SpeedSchedule','Actual events must start at 0.9 ms, then occur every 1 ms.');
[countTime,count]=logged(out,'D_speed_result_count');
[sourceTime,sourceCount]=logged(out,'D_speed_source_count');
sourceCount=holdGrid(sourceTime,sourceCount,countTime,dt);
assert(count(1)==0 && sourceCount(1)==0 && all(count==fix(count)) && all(sourceCount==fix(sourceCount)));
assert(all(diff(count)==0 | diff(count)==1) && all(diff(sourceCount)==0 | diff(sourceCount)==1), ...
 'StudyL1D:GoldenCounts','Source/result counters skipped or reversed an event.');
resultIndex=find(diff(count)==1)+1; captureIndex=find(diff(sourceCount)==1)+1;
assert(numel(resultIndex)==numel(source) && numel(captureIndex)==numel(source), ...
 'StudyL1D:GoldenCountCoverage','Hardware counters do not cover every real speed event.');
assert(isequal(count(resultIndex),(1:numel(source))') && isequal(sourceCount(captureIndex),(1:numel(source))'));
captureObserved=countTime(captureIndex); resultObserved=countTime(resultIndex);
assert(all(captureObserved-source>=-1e-12 & captureObserved-source<=dt+1e-12));
launchCycle=observed(out,'D_speed_launch_cycle',captureObserved,dt);
resultCycle=observed(out,'D_speed_result_cycle',resultObserved,dt);
assert(all(resultCycle-launchCycle==1),'StudyL1D:GoldenLatency', ...
 'Physical input capture to output commit must be exactly one 50 MHz clock.');
capturePhysical=cfg.speed_clock_epoch_s+launchCycle*20e-9;
resultPhysical=cfg.speed_clock_epoch_s+resultCycle*20e-9;
assert(all(capturePhysical-source>=-1e-12 & capturePhysical-source<=20e-9+1e-12), ...
 'StudyL1D:GoldenClockEpoch','Measured physical capture is outside the first clock after the source event.');
assert(all(resultPhysical-source>=20e-9-1e-12 & resultPhysical-source<=40e-9+1e-12), ...
 'StudyL1D:GoldenClockEpoch','Measured output completion is outside the frozen two-boundary carrier.');
assert(all(resultObserved>=resultPhysical-1e-12 & resultObserved-resultPhysical<=dt+1e-12));
% Cross-check the values that were present when hardware accepted its inputs.
% These are the actual source exports, held on the shared 100 us task boundary.
acceptedInputs=zeros(numel(source),7);
for k=1:7
 acceptedInputs(:,k)=observed(out,inputLog{k},captureObserved,dt);
end
assert(isequal(acceptedInputs,values(eventIndex,:)), ...
 'StudyL1D:GoldenInputAlignment','Replay values differ from actual hardware-capture source values.');
F=fimath('RoundingMethod','Convergent','OverflowAction','Saturate');
ds=Simulink.SimulationData.Dataset;
for k=1:7
 a=values(:,k);
 if k<=2, a=fi(a,true,32,20,F); elseif k~=5, a=logical(a); end
 ds=ds.addElement(timeseries(a,time),inputPort{k});
end
gold='speed_pi_fixed'; assert(~bdIsLoaded(gold),'StudyL1D:GoldenAlreadyLoaded','Do not alter an already loaded B1 model.');
cache=fullfile(reportDir,'b1_replay_cache'); assert(~isfolder(cache),'StudyL1D:ExistingCache','Fresh B1 replay cache required.');
oldConfig=Simulink.fileGenControl('getConfig');
restore=onCleanup(@()Simulink.fileGenControl('setConfig','config',oldConfig)); %#ok<NASGU>
Simulink.fileGenControl('set','CacheFolder',cache,'CodeGenFolder',fullfile(cache,'codegen'),'createDir',true);
load_system(fullfile(study,'models',[gold '.slx']));
closeGolden=onCleanup(@()close_system(gold,0)); %#ok<NASGU>
si=Simulink.SimulationInput(gold).setExternalInput(ds);
si=si.setModelParameter('StopTime',num2str(time(end),17),'SaveOutput','on', ...
 'SaveFormat','Dataset','OutputSaveName','yout','ReturnWorkspaceOutputs','on','LimitDataPoints','off');
goldOut=sim(si);
names={'iq_ref_A','iq_unlimited_A','integrator_A','saturation_active', ...
 'integrator_next_A','previous_excess_A','excess_next_A','hard_reset','int_reset', ...
 'iq_limited_A','error_mmps','P_A','KiTs_A','AW_A'};
fl=[15 30 30 0 30 30 30 0 0 30 20 30 30 30];
wl=[25 42 32 1 32 40 40 1 1 42 33 40 40 40];
sg=[1 1 1 0 1 1 1 0 0 1 1 1 1 1];
expected=zeros(numel(source),14); measured=expected; holdChanges=zeros(1,14);
for k=1:14
 g=goldOut.yout.getElement(k).Values;
 assert(numel(g.Time)==numel(time) && all(abs(double(g.Time(:))-time)<1e-12), ...
  'StudyL1D:GoldenGrid','Actual B1 output is not on the replay grid.');
 gr=rawCode(g.Data(:),fl(k)); expected(:,k)=gr(eventIndex);
 [ht,hr]=loggedRaw(out,['D_hdl_speed_' names{k}],fl(k));
 allRows=holdGrid(ht,hr,countTime,dt); measured(:,k)=allRows(resultIndex);
 assert(all(allRows>=-sg(k)*2^(wl(k)-sg(k)) & allRows<=2^(wl(k)-sg(k))-1), ...
  'StudyL1D:GoldenRawRange','Observed %s violates its frozen raw-code range.',names{k});
 holdChanges(k)=nnz(diff(allRows)~=0 & diff(count)==0);
 assert(holdChanges(k)==0,'StudyL1D:GoldenHold','Observed %s changed without a new-result event.',names{k});
end
different=measured~=expected; maxRawError=max(abs(measured-expected),[],1);
refRaw=double(storedInteger(fi(values(eventIndex,1),true,32,20,F)));
measRaw=double(storedInteger(fi(values(eventIndex,2),true,32,20,F)));
rows=[(1:numel(source))' source capturePhysical resultPhysical captureObserved resultObserved ...
 launchCycle resultCycle refRaw measRaw values(eventIndex,3:7) expected measured];
columns={'event_id','source_time_s','physical_capture_time_s','physical_result_time_s', ...
 'observed_capture_time_s','observed_result_time_s','input_capture_cycle','result_cycle', ...
 'v_ref_raw','v_meas_raw','enable','pi_reset','sample_tick','angle_init','test_mode'};
columns=[columns strcat('golden_',names) strcat('observed_',names)];
writetable(array2table(rows,'VariableNames',columns),csvFile);
scope='Selected RTL speed PI';
if strcmp(cfg.implementation,'original'), scope='Unselected HDL Coder baseline shadow; original floating PI is not claimed bit-exact to B1.'; end
evidence=struct('pass',~any(different,'all'),'scenario',cfg.name,'implementation',cfg.implementation, ...
 'oracle','Actual frozen models/speed_pi_fixed.slx simulated fresh with real system input exports', ...
 'hardware_scope',scope,'event_count',numel(source),'port_count',14,'raw_comparisons',numel(different), ...
 'mismatched_raw_codes',nnz(different),'mismatched_events',nnz(any(different,2)), ...
 'ports',{names},'max_absolute_raw_error',maxRawError,'changes_without_result',holdChanges, ...
 'first_source_event_s',source(1),'speed_period_s',.001,'clock_period_s',20e-9, ...
 'input_capture_to_result_cycles',1,'measured_clock_epoch_s',cfg.speed_clock_epoch_s, ...
 'source_to_capture_s',[min(capturePhysical-source) max(capturePhysical-source)], ...
 'source_to_result_s',[min(resultPhysical-source) max(resultPhysical-source)], ...
 'observation_transport_s',[min(resultObserved-resultPhysical) max(resultObserved-resultPhysical)], ...
 'alignment','Actual source-event order and measured physical clock ordinals; no fitted or arbitrary waveform shift', ...
 'csv','bit_true.csv');
f=fopen(jsonFile,'w'); assert(f>=0); closeFile=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'%s\n',jsonencode(evidence,'PrettyPrint',true));
assert(evidence.pass,'StudyL1D:GoldenMismatch','%d raw-code mismatches against the actual B1 model; see %s.',nnz(different),csvFile);
fprintf('D_B1_BIT_TRUE_PASS %s %s events=%d ports=14 raw_codes=%d\n',cfg.name,cfg.implementation,numel(source),numel(different));
end
function [t,y]=logged(out,name)
ts=out.logsout.get(name).Values;
[t,index]=unique(double(ts.Time(:)),'last'); y=double(ts.Data(:)); y=y(index);
assert(all(isfinite(t)) && all(isfinite(y)),'StudyL1D:GoldenNonFinite','Invalid actual log %s.',name);
end
function [t,y]=loggedRaw(out,name,fl)
ts=out.logsout.get(name).Values;
[t,index]=unique(double(ts.Time(:)),'last'); y=rawCode(ts.Data(:),fl); y=y(index);
assert(all(isfinite(t)) && all(isfinite(y)));
end
function y=rawCode(a,fl)
if isfi(a), y=double(storedInteger(a)); else, y=double(a)*2^fl; end
assert(all(isfinite(y)) && all(y==fix(y)),'StudyL1D:GoldenFractionalRaw','A raw fixed-point code was not an integer.');
end
function y=observed(out,name,q,dt)
[t,x]=logged(out,name); y=holdGrid(t,x,q,dt);
end
function y=holdGrid(t,x,q,dt)
% Snap only representational noise; retain actual communication-grid delays.
it=round(t/dt); iq=round(q/dt);
assert(all(abs(t-it*dt)<1e-12) && all(abs(q-iq*dt)<1e-12), ...
 'StudyL1D:GoldenOffGrid','A timestamp is off the actual communication grid.');
assert(all(diff(it)>0) && it(1)<=min(iq) && it(end)>=max(iq), ...
 'StudyL1D:GoldenCoverage','Actual source log does not cover replay timestamps.');
y=interp1(it,x,iq,'previous');
end
