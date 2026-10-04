function study_l1_probe
% Read-only runtime gate in a dedicated R2026b batch process.
disp('STUDY_L1_BATCH_RUNTIME_PROBE'); disp(version); disp(version('-release')); disp(pwd);
disp(ver('simulink')); disp(ver('fixedpoint'));
assert(strcmp(version('-release'),'2026b'));
assert(license('test','Simulink') && license('test','Fixed_Point_Toolbox'));
disp('STUDY_L1_RUNTIME_GATE_PASS');
end
