function reportDir=step7d_acceptance(beforeRawDir)
% Fresh ordered acceptance under the PR33 revision. No saved model edits.
root=fileparts(fileparts(mfilename('fullpath'))); oldpwd=pwd; c=onCleanup(@()cd(oldpwd)); %#ok<NASGU>
cd(root); assert(strcmp(version('-release'),'2026b'));
assert(~isempty(which('model_read')) && ~isempty(which('model_edit')) && ~isempty(which('model_check')),'Step7D:Toolkit','Initialize the installed R2026b Toolkit first.');
if nargin<1, beforeRawDir=fullfile(root,'.Xil','step7d','20260922_113014_967'); end
assert(isfolder(beforeRawDir),'Step7D:MissingBaseline','Provide original Task1 raw baseline directory.');
runid=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
reportDir=fullfile(root,'docs','reports','step7d',['acceptance_' runid]);
assert(~isfolder(reportDir)); mkdir(reportDir);
[rc,commit]=system('git rev-parse HEAD'); assert(rc==0);
modelFile=fullfile(root,'simulink模型','PMLSM_ThreeLoop_Simple.slx'); modelHash=fileHash(modelFile);
f=fopen(fullfile(reportDir,'tested_revision.txt'),'w');
fprintf(f,'ACCEPTANCE_ID=%s\nCOMMIT=%sMATLAB=%s\nBASELINE=%s\n',runid,commit,version,beforeRawDir); fclose(f);
f=fopen(fullfile(reportDir,'tested_revision.txt'),'a'); fprintf(f,'MODEL_SHA256=%s\n',modelHash); fclose(f);
try
 step7d_test_contracts;
 step7c_generate_foc_cosim(1e-6,true);
 currentDir=fullfile(reportDir,'current_prerequisite'); mkdir(currentDir);
 step7c_run_dynamic('ideal',currentDir); step7c_run_dynamic('deadtime',currentDir);
 step7d_test_live_interface(fullfile(reportDir,'live_interface'));
 names={'speed_ideal','speed_deadtime','position_ideal','position_deadtime','position_negative_deadtime'};
 baseline={'04_speed_ideal_1us.mat','05_speed_deadtime_1us.mat','06_position_ideal_1us.mat','07_position_deadtime_1us.mat','08_position_negative_deadtime_1us.mat'};
 for k=1:numel(names)
  d=fullfile(reportDir,names{k}); step7d_run_scenario(names{k},1,1e-6,d);
  step7d_report_outer_case(d,fullfile(beforeRawDir,baseline{k}));
 end
 step7d_test_outer_limits(fullfile(reportDir,'outer_limits'));
 d=fullfile(reportDir,'stop_restart_inhibit'); step7d_run_scenario('stop_restart_inhibit',1,1e-6,d); step7d_check_stop_run(d);
 step7d_run_scenario('fresh_start',1,1e-6,fullfile(reportDir,'fresh_start'));
 step7d_compare_convergence(fullfile(reportDir,'convergence'));
 step7d_run_regressions(fullfile(reportDir,'regressions'),beforeRawDir);
 files={'current_prerequisite/dynamic_ideal.txt','current_prerequisite/dynamic_deadtime.txt','live_interface/interface_gate.txt', ...
  'outer_limits/outer_limits.txt','stop_restart_inhibit/stop_inhibit.txt','fresh_start/run_summary.txt','convergence/convergence.txt', ...
  'regressions/structure_after.txt','regressions/legacy_after/baseline_before.txt','regressions/timing_1us.txt', ...
  'regressions/dynamic_ideal.txt','regressions/dynamic_deadtime.txt','regressions/dynamic_stop.txt', ...
  'regressions/convergence_1us_vs_0p5us.txt','regressions/minimal_cosim_result.txt','regressions/foc_wrapper_xsim.txt'};
 markers={'STEP7C_DYNAMIC_IDEAL_PASS','STEP7C_DYNAMIC_DEADTIME_PASS','STEP7D_LIVE_INTERFACE_PASS', ...
  'STEP7D_OUTER_LIMIT_RESET_PASS','STEP7D_STOP_INHIBIT_PASS','STEP7D_SCENARIO_GATE_PASS fresh_start','STEP7D_CONVERGENCE_PASS', ...
  'STEP7C_STRUCTURE_PASS','STEP7D_LEGACY_EQUIVALENCE_PASS','STEP7C_1US_TIMING_PASS', ...
  'STEP7C_DYNAMIC_IDEAL_PASS','STEP7C_DYNAMIC_DEADTIME_PASS','STEP7C_DYNAMIC_STOP_PASS', ...
  'STEP7C_CONVERGENCE_PASS','STEP7B_SIMULINK_MINIMAL_COSIM_PASS','STEP7B_FOC_WRAPPER_PASS'};
 for k=1:numel(names)
  files{end+1}=[names{k} '/run_summary.txt']; markers{end+1}=['STEP7D_SCENARIO_GATE_PASS ' names{k} ' purpose=performance']; %#ok<AGROW>
 end
 for k=1:numel(files)
  step7d_require_report(fullfile(reportDir,files{k}),markers{k});
 end
 assert(strcmp(modelHash,fileHash(modelFile)),'Step7D:ConcurrentModelChange','Saved model changed during acceptance.');
 f=fopen(fullfile(reportDir,'acceptance.txt'),'w'); fc=onCleanup(@()fclose(f)); %#ok<NASGU>
 fprintf(f,'ACCEPTANCE_ID=%s\nTESTED_COMMIT=%s',runid,commit);
 for k=1:numel(files), fprintf(f,'%s: %s\n',files{k},markers{k}); end
 fprintf(f,'FULL_STEP6_RERUN=0\nMODEL_SAVED=0\nSTEP7D_FULL_ACCEPTANCE_PASS\n');
 disp('STEP7D_FULL_ACCEPTANCE_PASS');
catch e
 f=fopen(fullfile(reportDir,'failure.txt'),'w'); fprintf(f,'%s\n%s\n',e.identifier,getReport(e,'extended','hyperlinks','off')); fclose(f);
 rethrow(e);
end
end
function value=fileHash(file)
% This R2026b installation intentionally has no Java runtime.
command=sprintf('powershell.exe -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath ''%s'').Hash"',strrep(file,'''',''''''));
[rc,output]=system(command); value=lower(strtrim(output));
assert(rc==0 && ~isempty(regexp(value,'^[0-9a-f]{64}$','once')),'Step7D:ModelHash','Cannot record saved model hash.');
end
