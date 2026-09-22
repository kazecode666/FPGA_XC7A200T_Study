function step7d_verify_blocker
% Saved-data regression: the real failure must remain a failure.
root=fileparts(fileparts(mfilename('fullpath'))); d=fullfile(root,'docs','reports','step7d');
for n={'speed_ideal','speed_deadtime'}
 txt=fileread(fullfile(d,['task4_' n{1}],'run_summary.txt'));
 p=regexp(txt,'RAW_DIR=([^\r\n]+)','tokens','once'); a=load(fullfile(p{1},'result.mat'),'r');
 if strcmp(n{1},'speed_ideal')
  step7d_assert_result(a.r,a.r.cfg); disp('STEP7D_SPEED_IDEAL_PASS');
 else
  caught=false;
  try, step7d_assert_result(a.r,a.r.cfg);
  catch e
   if ~strcmp(e.identifier,'Step7D:SpeedPerformance'), rethrow(e); end
   caught=true; fprintf('RECORDED_FAILURE=%s\n',e.message);
  end
  assert(caught,'Step7D:MissingExpectedFailure','Recorded deadtime case unexpectedly passed.');
  assert(isequal(a.r.effective_config.Host_Enable_Schedule,[0 1 0 1]));
  assert(a.r.effective_config.PMLSM_deadtime_s==1e-6);
  disp('STEP7D_TASK4_BLOCKER_REPRODUCED');
 end
end
disp('NOT_STEP7D_ACCEPTANCE_PASS');
end
