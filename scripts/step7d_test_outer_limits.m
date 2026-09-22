function step7d_test_outer_limits(reportDir)
% In-memory component harness around the ORIGINAL speed PI. Not plant evidence.
assert(~isfolder(reportDir),'Step7D:ExistingReport','Use a fresh report directory.'); mkdir(reportDir);
cfg=step7d_scenarios('fresh_start'); cfg.backend=0; cfg.stopTime=.2;
cfg.signals.reset=[0 0;.08 1;.09 0;.17 1;.172 0;.2 0];
[si,cfg,cleanup]=step7d_configure_model(cfg); %#ok<ASGLU>
m='PMLSM_ThreeLoop_Simple'; model_read(m,'blk_505');
ops={struct('op','add_block','type','FromWorkspace','name','Step7D_Component_Error','ref','err', ...
 'params',struct('VariableName','STEP7D_component_error','SampleTime','-1','Interpolate','off','OutputAfterFinalValue','Holding final value')), ...
 struct('op','add_block','type','Constant','name','Step7D_Component_Zero','ref','zero','params',struct('Value','0')), ...
 struct('op','connect','target','#err.y1 -> blk_1122.u1'),struct('op','connect','target','#zero.y1 -> blk_1122.u2'), ...
 struct('op','add_block','type','Terminator','name','Step7D_Unused_Managed_Reference','ref','unused'), ...
 struct('op','connect','target','blk_1264.y1 -> #unused.u1'), ...
 struct('op','add_block','type','Terminator','name','Step7D_Unused_Plant_Speed','ref','unusedv'), ...
 struct('op','connect','target','blk_510.y1 -> #unusedv.u1')};
disp(model_edit(m,'blk_505',jsonencode(ops),'incremental')); disp(model_read(m,'blk_505'));
check=model_check(m,'blk_505','["unconnected_ports","unconnected_lines"]'); disp(check);
assert(~contains(string(check),'severity: error'),'Step7D:HarnessConnectivity','Component harness has an unconnected port.');
si=si.setVariable('STEP7D_component_error',timeseries([200;-200;0;2;0;0],[0;.04;.08;.09;.13;.2]));
for pair={1163,'component_error';1166,'component_previous_excess';1165,'component_next_integrator';1122,'component_output'}'
 b=Simulink.ID.getFullName(sprintf('%s:%d',m,pair{1})); p=get_param(b,'PortHandles');
 set_param(p.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',pair{2});
end
out=sim(si);
names={'component_error','component_previous_excess','component_next_integrator','component_output', ...
 'outer_integrator','iq_unlimited','iq_limited','hard_reset','int_reset'};
global STEP7D_RUN_EVENTS
t=STEP7D_RUN_EVENTS.speed(:); s=struct;
for k=1:numel(names)
 ts=out.logsout.get(names{k}).Values;
 [ticks,idx]=unique(round(double(ts.Time(:))/cfg.commTs),'last'); values=double(ts.Data(:));
 s.(names{k})=interp1(ticks,values(idx),round(t/cfg.commTs),'previous');
end
root=fileparts(fileparts(mfilename('fullpath'))); raw=fullfile(root,'.Xil','step7d',['outer_limits_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')) '.mat']);
save(raw,'s','t','cfg'); fprintf('COMPONENT_RAW=%s\n',raw);
assert(all(structfun(@(v)numel(v)==numel(t)&&all(isfinite(v)),s)));
expected=max(-.5,min(.5,s.outer_integrator+1.4426779882144898*.001*s.component_error-.08*s.component_previous_excess));
expected(s.int_reset>.5)=0;
assert(max(abs(expected-s.component_next_integrator))<1e-12,'Step7D:Antiwindup','Original integrator update differs.');
assert(max(abs(s.outer_integrator))<=.5+1e-12 && max(abs(s.component_output))<=1+1e-12,'Step7D:OuterLimit','Original PI bounds failed.');
assert(any(s.component_output>.999) && any(s.component_output<-.999),'Step7D:OuterLimit','Both saturation directions must be exercised.');
hold=t>=.14 & t<.16;
assert(any(hold) && all(s.component_error(hold)==0) && all(s.int_reset(hold)==0) && ...
 min(abs(s.outer_integrator(hold)))>1e-4 && max(s.outer_integrator(hold))-min(s.outer_integrator(hold))<1e-12, ...
 'Step7D:IntegralHold','Zero error must retain nonzero integral.');
reset=t>=.17 & t<.172;
assert(any(reset) && all(s.hard_reset(reset)==1) && all(s.component_output(reset)==0) && all(s.component_next_integrator(reset)==0),'Step7D:OuterReset','Explicit reset failed.');
save(raw,'s','t','expected','cfg');
f=fopen(fullfile(reportDir,'outer_limits.txt'),'w'); fc=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'ORIGINAL_SPEED_PI_SID=1122\nCOMPONENT_ONLY_NOT_PLANT_EVIDENCE=1\nMODEL_SAVED=0\nRAW=%s\n',raw);
fprintf(f,'output_min_max=%s integral_min_max=%s\nantiwindup_max_error=%.17g\nzero_error_integral_min_max=%s\n', ...
 mat2str([min(s.component_output) max(s.component_output)],17),mat2str([min(s.outer_integrator) max(s.outer_integrator)],17),max(abs(expected-s.component_next_integrator)),mat2str([min(s.outer_integrator(hold)) max(s.outer_integrator(hold))],17));
fprintf(f,'STEP7D_OUTER_LIMIT_RESET_PASS\n'); disp('STEP7D_OUTER_LIMIT_RESET_PASS');
end
