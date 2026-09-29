function step7d_check_stop_run(reportDir)
% Full communication-rate stop/restart checks on this run's saved evidence.
txt=fileread(fullfile(reportDir,'run_summary.txt')); p=regexp(txt,'RAW_DIR=([^\r\n]+)','tokens','once');
a=load(fullfile(p{1},'result.mat'),'r'); r=a.r;
assert(strcmp(r.cfg.name,'stop_restart_inhibit'));
a=load(fullfile(p{1},'simulation_output.mat'),'out'); out=a.out;
ts=pmlsm_get_monitor(out,'motor'); t=double(ts.Time(:)); d=double(ts.Data);
post=t>=.25+r.cfg.commTs-1e-12; pre=find(t<.25,1,'last');
assert(any(post) && t(end)>=.4-1e-12 && abs(d(pre,9))>2.5 && abs(d(pre,8))>.1,'Step7D:StopNotMoving','Stop must interrupt actual motion.');
assert(all(isfinite(d),'all') && all(d(post,20:21)==0,'all') && all(d(post,23)==1) && all(d(:,22)==0), ...
 'Step7D:StopInhibit','Bridge/valid/reset latch/fault failed after stop or attempted restart.');
assert(all(abs(d(post,24:25))<1e-12,'all'),'Step7D:StopVoltage','Selected voltage not zero after stop.');
en=out.logsout.get('selected_enable').Values; assert(all(en.Data(en.Time>=.25+r.cfg.commTs-1e-12)==0),'Step7D:StopInhibit','Selected enable recovered.');
reset=out.logsout.get('Select_pi_reset').Values; ix=reset.Time>=.35 & reset.Time<.352;
assert(any(ix) && any(reset.Data(ix)~=0),'Step7D:ResetPulseMissing','No actual Adapter PI reset request.');
resetTimes=reset.Time(reset.Data~=0);
for at=[.25 .30 .35]
 k=find(t>=at-1e-12,1); assert(k>1);
 assert(abs(d(k,8)-d(k-1,8))<.001 && abs(d(k,9)-d(k-1,9))<.1,'Step7D:PlantReset','Discontinuous plant state at control transition.');
end
assert(max(abs(r.outer_integrator))<=.5+1e-12,'Step7D:OuterLimit','Stop outer integrator unbounded.');
f=fopen(fullfile(reportDir,'stop_inhibit.txt'),'w'); fc=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'RUN_ID=%s\nRAW_DIR=%s\nOBSERVATION_START=%.17g\nPOST_SAMPLES=%d\n',r.run_id,p{1},t(find(post,1)),sum(post));
fprintf(f,'PRE_STOP_X_MM_V_MMPS=%s\nFINAL_X_MM_V_MMPS=%s\n',mat2str(d(pre,[8 9]),17),mat2str(d(end,[8 9]),17));
fprintf(f,'ADAPTER_PI_RESET_NONZERO_FIRST_LAST=%s\nINTEGRATOR_MIN_MAX=%s\n',mat2str([resetTimes(1) resetTimes(end)],17),mat2str([min(r.outer_integrator) max(r.outer_integrator)],17));
fprintf(f,'POST_VALID=0 POST_BRIDGE=0 POST_VDQ=0 NEEDS_RESET=1 FAULT=0\nPLANT_RESET=0\nNOT_A_HOT_RESTART_TEST=1\nSTEP7D_STOP_INHIBIT_PASS\n');
disp('STEP7D_STOP_INHIBIT_PASS');
end
