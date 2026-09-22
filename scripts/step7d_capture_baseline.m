function step7d_capture_baseline(reportDir)
% Task 1: untouched-controller legacy baselines; temporary high-level sources.
root=fileparts(fileparts(mfilename('fullpath'))); p=pwd; mp=path;
c=onCleanup(@()restore(p,mp)); %#ok<NASGU>
cd(root); addpath(fullfile(root,'simulink模型')); assert(strcmp(version('-release'),'2026b'));
assert(nargin==1 && ~isfolder(reportDir),'Step7D:ExistingReport','Supply a fresh report directory.');
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m),'Step7D:ModelAlreadyLoaded','Save and close the model first.');
gate=library.settingsLookup(); assert(gate.gatePass); mkdir(reportDir);
rawDir=fullfile(root,'.Xil','step7d',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))); mkdir(rawDir);
load_system(m); cm=onCleanup(@()close_system(m,0)); %#ok<NASGU>
model_read(m,'root');
% Only high-level requests: Host_v_cmd and Host_load_cmd local Goto inputs.
% Position mode still uses the original Host trajectory; v_request is unused.
ops={struct('op','add_block','type','FromWorkspace','name','Step7D_TestSpeedRequest','ref','speed', ...
 'params',struct('VariableName','STEP7D_speed_ts','Interpolate','on','SampleTime','0','OutputAfterFinalValue','Holding final value')), ...
 struct('op','connect','target','#speed.y1 -> blk_1249.u1'), ...
 struct('op','add_block','type','FromWorkspace','name','Step7D_TestLoad','ref','load', ...
 'params',struct('VariableName','STEP7D_load_ts','Interpolate','off','SampleTime','0','OutputAfterFinalValue','Holding final value')), ...
 struct('op','connect','target','#load.y1 -> blk_941.u1')};
disp(model_edit(m,'root',jsonencode(ops),'incremental')); model_read(m,'root');
disp(model_check(m,'root','["unconnected_ports","unconnected_lines"]'));
% Logging adds no algorithm or state and is never saved.
spec={505,1,'cmpA';505,2,'cmpB';505,3,'cmpC';771,1,'vd';771,2,'vq'; ...
 191,1,'id';191,2,'iq';191,3,'ia';191,4,'ib';191,5,'ic';191,6,'x';191,7,'v';191,8,'theta';191,9,'we'; ...
 991,1,'id_ref';991,2,'iq_ref';991,3,'v_ref';523,1,'x_ref'; ...
 1228,1,'integrator';1159,1,'iq_limited';1133,1,'iq_unlimited';1189,1,'hard_reset';1189,2,'int_reset'; ...
 523,4,'close_en';523,5,'pos_en';523,6,'pwm_en';1277,1,'pi_reset'; ...
 740,1,'speed_tick';740,2,'position_tick'};
delay=find_system(m,'MatchFilter',@Simulink.match.allVariants,'Name','PWM_Update_HalfTs'); assert(numel(delay)==1);
for k=1:3, spec(end+1,:)={str2double(get_param(delay{1},'SID')),k,sprintf('delayed%d',k)}; end
for k=1:size(spec,1)
 b=Simulink.ID.getFullName(sprintf('%s:%d',m,spec{k,1})); ph=get_param(b,'PortHandles');
 set_param(ph.Outport(spec{k,2}),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',spec{k,3});
end
fid=fopen(fullfile(reportDir,'baseline_before.txt'),'w'); cf=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'MODEL_SAVED=0\nHDL_SETUP_CALLED=0\nBACKEND=0\nRAW_DIR=%s\n',rawDir);
fprintf(fid,'Temporary boundary replacements: Simple_Host/7 -> Host_v_cmd becomes TestSpeedRequest; Simple_Host/3 -> Host_load_cmd becomes TestLoad. No outer-controller/plant feedback replacement.\n');
names={'current_native','speed_deadtime','position_deadtime','speed_ideal','speed_deadtime','position_ideal','position_deadtime','position_negative_deadtime'};
steps=[50e-6 50e-6 50e-6 repmat(1e-6,1,5)];
for n=1:numel(names)
 name=names{n};
 if strcmp(name,'current_native')
  cfg=step7d_scenarios('speed_deadtime'); cfg.name=name; cfg.stopTime=.005;
  cfg.host.Host_Iq_Test_Mode=1; cfg.host.Host_Iq_A=.2; cfg.signals.speed=[0 0;.005 0]; cfg.signals.load=[0 0;.005 0];
 else, cfg=step7d_scenarios(name); end
 cfg.backend=0; cfg.commTs=steps(n);
 label=sprintf('%02d_%s_%gus',n,name,cfg.commTs*1e6);
 fprintf('BASELINE_BEGIN %s\n',label);
 si=Simulink.SimulationInput(m);
 si=si.setModelParameter('FixedStep',num2str(cfg.commTs,17),'StopTime',num2str(cfg.stopTime,17), ...
  'ReturnWorkspaceOutputs','on','SignalLogging','on','SignalLoggingName','logsout');
 si=si.setVariable('CONTROL_BACKEND',0).setVariable('STEP7D_BASELINE_CFG',cfg);
 si=si.setVariable('STEP7D_speed_ts',timeseries(cfg.signals.speed(:,2),cfg.signals.speed(:,1)));
 si=si.setVariable('STEP7D_load_ts',timeseries(cfg.signals.load(:,2),cfg.signals.load(:,1)));
 host=cfg.host; host.PMLSM_Ts_s=cfg.commTs; host.PMLSM_deadtime_s=cfg.deadtime_s; host.PMLSM_deadtime_ratio=cfg.deadtime_s/1e-4; host.Udc=48;
 init='mw=get_param(bdroot,''ModelWorkspace'');'; fn=fieldnames(host);
 for k=1:numel(fn), init=[init sprintf('mw.assignin(''%s'',%s);',fn{k},mat2str(host.(fn{k}),17))]; end %#ok<AGROW>
 si=si.setModelParameter('InitFcn',[get_param(m,'InitFcn') newline init], ...
  'StartFcn','step7d_baseline_start(bdroot,slResolve(''STEP7D_BASELINE_CFG'',bdroot));');
 out=sim(si);
 global STEP7D_BASELINE_EVENTS STEP7D_BASELINE_EFFECTIVE
 r=struct('cfg',cfg,'effective_config',STEP7D_BASELINE_EFFECTIVE,'events',STEP7D_BASELINE_EVENTS);
 r.time_s=(0:max(cfg.commTs,1e-4):cfg.stopTime)'; r.signals=struct; r.peaks=struct;
 if cfg.commTs==50e-6, r.time_s=(0:cfg.commTs:cfg.stopTime)'; end
 for k=1:size(spec,1)
  key=spec{k,3}; ts=out.logsout.get(key).Values; t=double(ts.Time(:)); y=double(ts.Data(:));
  assert(all(isfinite(y)),'Step7D:NonFinite','Nonfinite %s',key);
  [lo,il]=min(y); [hi,ih]=max(y); r.peaks.(key)=[lo hi t(il) t(ih)];
  [t,idx]=unique(t,'last'); y=y(idx);
  % Triggered speed blocks first execute at 0.9 ms. Their audited initial
  % output/state is zero before that event; do not extrapolate a future value.
  if t(1)>0
   assert(any(strcmp(key,{'integrator','iq_limited','iq_unlimited','hard_reset','int_reset'})), ...
    'Step7D:UnknownInitialOutput','Unaudited initial output for %s',key);
   t=[0;t]; y=[0;y];
  end
  r.signals.(key)=interp1(t,y,r.time_s,'previous','extrap');
  assert(all(isfinite(r.signals.(key))),'Step7D:NonFiniteNormalized','Invalid normalized %s',key);
  if any(strcmp(key,{'v','x','iq_ref','id','iq'})), r.full.(key)=struct('t',t,'y',y); end
 end
 r.signals.v_request=interp1(cfg.signals.speed(:,1),cfg.signals.speed(:,2),r.time_s,'linear');
 r.signals.load=interp1(cfg.signals.load(:,1),cfg.signals.load(:,2),r.time_s,'previous');
 save(fullfile(rawDir,[label '.mat']),'r','-v7.3');
 fprintf(fid,'\n%s\nCONFIG=%s\nEFFECTIVE=%s\n',label,jsonencode(cfg),jsonencode(r.effective_config));
 fprintf(fid,'EVENT_COUNTS current=%d speed=%d position=%d\n',numel(r.events.current),numel(r.events.speed),numel(r.events.position));
 fprintf(fid,'PEAKS=%s\n',jsonencode(r.peaks));
 if n>3
  issues=evaluateBaseline(r,fid);
  if ~isempty(issues)
   fprintf(fid,'STEP7D_BASELINE_PERFORMANCE_FAIL: %s\n',strjoin(issues,'; '));
   error('Step7D:LegacyPerformance','Untouched legacy %s failed: %s. Evidence: %s',label,strjoin(issues,'; '),reportDir);
  end
 end
 fprintf(fid,'CAPTURE_COMPLETE=%s\n',label); fprintf('BASELINE_CAPTURED %s\n',label);
 clear out r
end
fprintf(fid,'STEP7D_BASELINE_BEFORE_PASS\n'); disp('STEP7D_BASELINE_BEFORE_PASS');
end
function issues=evaluateBaseline(r,f)
c=r.cfg; s=r.signals; t=r.time_s; issues={};
assert(numel(t)==round(c.stopTime/1e-4)+1 && abs(t(end)-c.stopTime)<1e-12 && all(abs(diff(t)-1e-4)<1e-12), ...
 'Step7D:BadBaselineGrid','Full-length 100us performance grid required.');
for name={'current','speed','position'}
 ev=r.events.(name{1}); expected=struct('current',1e-4,'speed',1e-3,'position',1e-2);
 if numel(ev)<2 || any(abs(diff(ev)-expected.(name{1}))>1e-12), issues{end+1}=['execution interval ' name{1}]; end %#ok<AGROW>
 fprintf(f,'EVENT_%s first=%.17g last=%.17g count=%d\n',name{1},ev(1),ev(end),numel(ev));
end
for k=1:size(c.windows.speed,1)
 w=c.windows.speed(k,:); ev=r.events.speed; ev=ev(ev>=w(1)-1e-12 & ev<w(2)-1e-12);
 vr=interp1(t,s.v_ref,ev,'previous'); v=interp1(r.full.v.t,r.full.v.y,ev,'previous'); e=vr-v;
 assert(all(isfinite([vr;v;e])),'Step7D:NonFiniteMetrics','Invalid speed metric inputs.');
 vals=[numel(ev),mean(abs(e)),sqrt(mean(e.^2)),max(abs(e)),mean(v),max(vr)-min(vr)];
 fprintf(f,'SPEED_WINDOW %s [N MAE RMSE MAX MEAN_V REF_SPAN]=%s\n',mat2str(w),mat2str(vals,17));
 if vals(1)<20 || vals(2)>.5 || vals(3)>.5 || vals(4)>2 || vals(6)>1e-9, issues{end+1}=sprintf('speed window %d',k); end %#ok<AGROW>
 if k==1 && mean(v)<=2.5 || k==3 && mean(v)>=-2.5, issues{end+1}='speed direction'; end %#ok<AGROW>
end
for k=1:size(c.windows.position,1)
 w=c.windows.position(k,:); ev=r.events.position; ev=ev(ev>=w(1)-1e-12 & ev<w(2)-1e-12);
 x=interp1(r.full.x.t,r.full.x.y,ev,'previous'); v=interp1(r.full.v.t,r.full.v.y,ev,'previous');
 sel=r.full.x.t>=w(1) & r.full.x.t<w(2); err=max(abs(c.host.Host_Target_mm-r.full.x.y(sel)));
 fprintf(f,'POSITION_WINDOW %s N=%d event_max_err=%g full_max_err=%g event_max_v=%g\n',mat2str(w),numel(ev),max(abs(c.host.Host_Target_mm-x)),err,max(abs(v)));
 if isempty(ev)||err>.05||max(abs(v))>1, issues{end+1}=sprintf('position window %d',k); end %#ok<AGROW>
end
if contains(c.name,'position')
 at=r.full.x.t; final=c.host.Host_Target_mm;
 if final>0 && r.peaks.x(2)>1.1 || final<0 && r.peaks.x(1)<-1.1, issues{end+1}='position overshoot'; end
 idx=t>=.70; if any(abs(s.x_ref(idx)-final)>1e-12), issues{end+1}='Host trajectory duration'; end
 fprintf(f,'POSITION_REFERENCE_HOLD_FROM_0P70=%d\n',all(abs(s.x_ref(idx)-final)<1e-12)); %#ok<NASGU>
end
ev=r.events.current; ev=ev(ev>=.002 & ev<=c.stopTime);
ir=interp1(t,s.iq_ref,ev,'previous'); iq=interp1(r.full.iq.t,r.full.iq.y,ev,'previous'); rms=sqrt(mean((ir-iq).^2));
assert(isfinite(rms),'Step7D:NonFiniteMetrics','Invalid current metric inputs.');
fprintf(f,'CURRENT_RMSE_A=%.17g N=%d\n',rms,numel(ev));
if rms>c.thresholds.iqRMSE, issues{end+1}='iq tracking RMSE'; end
if max(abs(r.peaks.id(1:2)))>c.thresholds.idMax, issues{end+1}='id full peak'; end
if max(abs(r.peaks.iq(1:2)))>1.5, issues{end+1}='iq full peak'; end
if max(abs(r.peaks.iq_ref(1:2)))>1+1e-12, issues{end+1}='iq_ref full peak'; end
end
function restore(p,mp)
global STEP7D_BASELINE_EVENTS STEP7D_BASELINE_LISTENERS STEP7D_BASELINE_EFFECTIVE
STEP7D_BASELINE_LISTENERS=[]; STEP7D_BASELINE_EVENTS=[]; STEP7D_BASELINE_EFFECTIVE=[];
cd(p); path(mp);
end
