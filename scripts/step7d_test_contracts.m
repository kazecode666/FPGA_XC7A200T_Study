function step7d_test_contracts
assert(exist('step7d_assert_result','file')==2 && exist('step7d_check_start','file')==2, ...
 'Step7D:MissingContracts','Step7D result/start contracts are not implemented.');
cfg=step7d_scenarios('speed_ideal'); cfg.backend=0; r=fixture(cfg);
step7d_assert_result(r,cfg);
bad=r; bad=rmfield(bad,'iq_A'); reject(@()step7d_assert_result(bad,cfg),'Step7D:MissingField');
bad=r; bad.v_mmps(10)=NaN; reject(@()step7d_assert_result(bad,cfg),'Step7D:NonFinite');
badcfg=cfg; badcfg.windows.speed=[2 3]; reject(@()step7d_assert_result(r,badcfg),'Step7D:EmptyWindow');
good=r; good.cfg.backend=1; good.fault_code=zeros(size(good.time_s)); good.needs_reset=good.fault_code; good.range_flags=good.fault_code;
good.command_events=struct('accepted_time_s',(.00005+cfg.commTs:1e-4:cfg.stopTime)','accepted_id',(1:12000)', ...
 'active_time_s',(.0001+cfg.commTs:1e-4:cfg.stopTime)','active_id',(1:11999)');
step7d_assert_result(good,good.cfg);
bad=good; bad.command_events.accepted_id(2)=3;
reject(@()step7d_assert_result(bad,bad.cfg),'Step7D:CommandSequence');
bad=good; bad.command_events.active_id=[]; bad.command_events.active_time_s=[];
reject(@()step7d_assert_result(bad,bad.cfg),'Step7D:CommandSequence');
bad=good;
for n=fieldnames(bad.command_events)', bad.command_events.(n{1})=bad.command_events.(n{1})(1:50); end
reject(@()step7d_assert_result(bad,bad.cfg),'Step7D:CommandCoverage');
bad=good; bad.command_events.active_time_s(10)=NaN;
reject(@()step7d_assert_result(bad,bad.cfg),'Step7D:CommandSequence');
bad=good; bad.command_events.active_id=bad.command_events.active_id+1;
reject(@()step7d_assert_result(bad,bad.cfg),'Step7D:CommandPair');
bad=good; bad.command_events.active_time_s=bad.command_events.active_time_s+cfg.commTs*2;
bad.command_events.accepted_time_s=bad.command_events.accepted_time_s+cfg.commTs*2;
reject(@()step7d_assert_result(bad,bad.cfg),'Step7D:CommandCoverage');
% Startup mutations must be read from the actual model, not merely cfg.
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m)); addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))),'simulink模型'));
load_system(m); cm=onCleanup(@()close_system(m,0)); %#ok<NASGU>
mw=get_param(m,'ModelWorkspace'); cfg.backend=1;
reject(@()step7d_check_start(m,cfg),'Step7D:ReferenceMode');
mw.assignin('FPGA_Reference_Mode',1);
reject(@()step7d_check_start(m,cfg),'Step7D:Backend');
mw.assignin('FPGA_Reference_Mode',1); mw.assignin('Ts_ASR',1e-6);
reject(@()step7d_check_start(m,cfg),'Step7D:ControlPeriod');
clear cm
cfg=step7d_scenarios('fresh_start'); cfg.backend=0;
[si,cfg,cleanup]=step7d_configure_model(cfg); %#ok<ASGLU>
assert(strcmpi(strrep(pwd,'\','/'),strrep(fileparts(fileparts(mfilename('fullpath'))),'\','/')),'Step7D:LegacyRuntimeCwd','Legacy entered HDL runtime directory.');
out=sim(si); ts=out.logsout.get('v_mmps').Values; assert(ts.Time(end)>=.02-1e-12); clear cleanup
step7d_test_scenarios;
disp('STEP7D_CONTRACT_TESTS_PASS');
end
function reject(fn,id)
failed=false; try, fn(); catch e, failed=strcmp(e.identifier,id); if ~failed, rethrow(e); end; end
assert(failed,'Step7D:NegativeTestDidNotFail','Expected %s',id);
end
function r=fixture(c)
t=(0:1e-4:c.stopTime)'; n=numel(t); z=zeros(n,1); v=interp1(c.signals.speed(:,1),c.signals.speed(:,2),t);
r=struct('cfg',c,'time_s',t,'v_request_mmps',v,'v_ref_mmps',v,'v_mmps',v,'x_ref_mm',z,'x_mm',z, ...
 'id_ref_A',z,'iq_ref_A',z,'id_A',z,'iq_A',z,'ia_A',z,'ib_A',z,'ic_A',z,'theta_rad',z,'we_radps',z, ...
 'load_N',interp1(c.signals.load(:,1),c.signals.load(:,2),t,'previous'), ...
 'pwm_en',ones(n,1),'pi_reset',z,'bridge_enable',ones(n,1),'outer_integrator',z,'outer_limit_flags',z, ...
 'accepted_id',[],'active_id',[],'active_valid',[],'needs_reset',[],'fault_code',[],'range_flags',[], ...
 'control_events',struct('current',t,'speed',(.0009:.001:1.1999)','position',(.0099:.01:1.1999)'), ...
 'command_events',struct,'peaks',struct('id_A',0,'iq_A',0,'iq_ref_A',0,'x_min_mm',0,'x_max_mm',0));
end
