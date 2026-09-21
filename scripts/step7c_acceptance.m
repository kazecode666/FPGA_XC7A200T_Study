function step7c_acceptance
% Ordered fresh tests. Any exception prevents writing the final PASS marker.
root=fileparts(fileparts(mfilename('fullpath'))); p=pwd; c=onCleanup(@() cd(p)); %#ok<NASGU>
cd(root); rd=fullfile(root,'docs','reports','step7c');
fprintf('1 structure\n'); step7c_check_structure;
fprintf('2 legacy root/no XSI; 3 numeric comparison\n'); step7c_run_scenario('legacy',1e-6);
fprintf('4 minimal\n'); step7b_run_cosim('minimal',rd);
for mode={'wrapper','d6p0','e6'}
    fprintf('XSim %s\n',mode{1});
    [rc,txt]=system(sprintf('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%s" -Mode %s -ReportDirectory docs/reports/step7c',fullfile(root,'scripts','step7b_run_xsim.ps1'),mode{1}));
    fprintf('%s\n',txt); assert(rc==0,'Required XSim regression failed');
end
fprintf('8 timing\n'); step7c_check_timing;
fprintf('9 ideal\n'); ideal=step7c_run_dynamic('ideal');
fprintf('10 deadtime\n'); dead=step7c_run_dynamic('deadtime');
fprintf('11 stop\n'); step7c_run_dynamic('stop');
fprintf('12 convergence\n'); step7c_compare_convergence;
% Concatenate only current verified results and actual simulator PASS lines.
files={'structure_after.txt','legacy_compare.txt','minimal_cosim_result.txt','foc_wrapper_xsim.txt','step6d_profile0.txt','step6e_regression.txt','timing_1us.txt','dynamic_ideal.txt','dynamic_deadtime.txt','dynamic_stop.txt','convergence_1us_vs_0p5us.txt'};
markers={'STEP7C_STRUCTURE_PASS','STEP7C_LEGACY_EQUIVALENCE_PASS','STEP7B_SIMULINK_MINIMAL_COSIM_PASS','STEP7B_FOC_WRAPPER_PASS','ALL STEP 6D FOC PWM TESTS PASSED profile=0','ALL STEP 6E','STEP7C_1US_TIMING_PASS','STEP7C_DYNAMIC_IDEAL_PASS','STEP7C_DYNAMIC_DEADTIME_PASS','STEP7C_DYNAMIC_STOP_PASS','STEP7C_CONVERGENCE_PASS'};
f=fopen(fullfile(rd,'regression_summary.txt'),'w'); cf=onCleanup(@() fclose(f)); %#ok<NASGU>
for k=1:numel(files)
    txt=fileread(fullfile(rd,files{k})); assert(contains(txt,markers{k}));
    fprintf(f,'--- %s ---\n',files{k});
    if k>=4 && k<=6, lines=splitlines(string(txt)); txt=char(join(lines(contains(lines,markers{k})),newline)); end
    fprintf(f,'%s\n',txt);
end
step7c_plot_results(ideal,dead,rd);
fprintf(f,'STEP7C_FULL_ACCEPTANCE_PASS\n'); fprintf('STEP7C_FULL_ACCEPTANCE_PASS\n');
end
