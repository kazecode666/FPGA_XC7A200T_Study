function step7d_run_regressions(reportDir,beforeRawDir)
% Revised Task7: Step7 regression, deliberately excludes full Step6 suites.
root=fileparts(fileparts(mfilename('fullpath'))); oldpwd=pwd; c=onCleanup(@()cd(oldpwd)); %#ok<NASGU>
cd(root); assert(~isfolder(reportDir),'Step7D:ExistingReport','Use a fresh report directory.'); mkdir(reportDir);
step7c_check_structure(reportDir);
step7d_capture_baseline(fullfile(reportDir,'legacy_after'),beforeRawDir);
step7c_check_timing(reportDir);
for name={'ideal','deadtime','stop'}, step7c_run_dynamic(name{1},reportDir); end
step7c_compare_convergence(reportDir);
step7b_generate_minimal_cosim(true,false);
step7b_run_cosim('minimal',reportDir);
relativeReport=erase(strrep(reportDir,'\','/'),[strrep(root,'\','/') '/']);
[rc,txt]=system(sprintf('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%s" -Mode wrapper -ReportDirectory "%s"',fullfile(root,'scripts','step7b_run_xsim.ps1'),relativeReport));
fprintf('%s\n',txt); assert(rc==0,'Step7D:WrapperRegression','FOC wrapper regression failed.');
disp('STEP7D_REVISED_REGRESSIONS_PASS');
end
