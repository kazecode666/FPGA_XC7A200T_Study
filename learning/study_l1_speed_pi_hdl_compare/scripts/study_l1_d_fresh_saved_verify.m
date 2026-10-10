function study_l1_d_fresh_saved_verify(runPrefix,checkName)
% Fresh process, current evaluator, real saved data from all nine runs.
% Optional names permit reruns without replacing any earlier verification.
if nargin<1, runPrefix='d_final'; end
if nargin<2, checkName='fresh_saved_check'; end
runPrefix=char(runPrefix); checkName=char(checkName);
assert(~isempty(regexp(runPrefix,'^[A-Za-z][A-Za-z0-9_-]*$','once')) && ...
 ~isempty(regexp(checkName,'^[A-Za-z][A-Za-z0-9_-]*$','once')), ...
 'StudyL1D:VerificationNames','Use simple explicit run-prefix and new check names.');
study=fileparts(fileparts(mfilename('fullpath')));
root=fileparts(fileparts(study));
addpath(fullfile(study,'scripts'),fullfile(root,'scripts'));
for implementation={'original','coder_baseline','hand_sv'}
 for scenario={'speed_ideal','speed_deadtime','convergence_prefix'}
  folder=fullfile(study,'.runtime',[runPrefix '_' implementation{1}],scenario{1},implementation{1});
  saved=load(fullfile(folder,'result.mat'),'r'); r=saved.r;
  metrics=step7d_assert_result(r,r.cfg); assert(isequaln(metrics,r.metrics.step7d_acceptance));
  fresh=fullfile(folder,checkName); assert(~isfolder(fresh)); mkdir(fresh);
  checked=study_l1_d_validate(r,fresh); assert(isequaln(checked,r.metrics));
  study_l1_d_export_commands(r,folder);
  b=jsondecode(fileread(fullfile(folder,'bit_true.json'))); assert(b.pass && b.mismatched_raw_codes==0 && b.port_count==14);
  fprintf('D_FRESH_SAVED_VERIFY_PASS %s %s\n',scenario{1},implementation{1});
 end
end
fprintf('D_FRESH_ALL_NINE_SAVED_VERIFY_PASS\n');
end
