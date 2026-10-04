function study_l1_b_probe
% Read-only product, API and frozen-model compatibility inspection.
fprintf('MATLAB_MCP_OK\n%s\n%s\n%s\n',version,version('-release'),pwd);
disp(ver('hdlcoder')); disp(ver('hdlverifier'));
fprintf('HDL_Coder_license=%d HDL_Verifier_license=%d\n', ...
    license('test','Simulink_HDL_Coder'),license('test','EDA_Simulator_Link'));
assert(strcmp(version('-release'),'2026b'));
assert(license('test','Simulink_HDL_Coder'));
study=fileparts(fileparts(mfilename('fullpath')));
cfg=Simulink.fileGenControl('getConfig');
restore=onCleanup(@()Simulink.fileGenControl('setConfig','config',cfg)); %#ok<NASGU>
Simulink.fileGenControl('set','CacheFolder',fullfile(study,'.runtime/b_probe/cache'), ...
    'CodeGenFolder',fullfile(study,'.runtime/b_probe/codegen'),'createDir',true);
load_system(fullfile(study,'models/speed_pi_fixed.slx'));
cleanup=onCleanup(@()close_system('speed_pi_fixed',0)); %#ok<NASGU>
try
    checks=checkhdl('speed_pi_fixed/PI'); disp(checks);
catch ex
    fprintf('FROZEN_B1_COMPATIBILITY_EXCEPTION\n%s\n',getReport(ex,'extended'));
end
fprintf('HDL_PARAMETER_DEFAULTS\n');
names={'TargetLanguage','TargetFrequency','ResetType','ClockInputPort','ResetInputPort', ...
    'ClockEnableInputPort','GenerateHDLTestBench', ...
    'GenerateValidationModel','Traceability','HDLSubsystem','SynthesisTool', ...
    'SynthesisToolChipFamily','SynthesisToolDeviceName','SynthesisToolPackageName', ...
    'SynthesisToolSpeedValue','TreatRatesAsHardwareRates','Oversampling'};
for n=string(names)
    try, fprintf('%s: ',n); disp(hdlget_param('speed_pi_fixed',char(n)));
    catch ex, fprintf('%s\n',ex.message); end
end
end
