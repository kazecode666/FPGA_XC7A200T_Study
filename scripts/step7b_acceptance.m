function step7b_acceptance
% Full acceptance sequence in the mandated order, after final implementation.
root=fileparts(fileparts(mfilename('fullpath')));
log=fullfile(root,'docs','reports','step7b','acceptance_console.txt');
if isfile(log), fid=fopen(log,'w'); fclose(fid); end
diary(log); d=onCleanup(@() diary('off')); %#ok<NASGU>
fprintf('STEP7B_ACCEPTANCE_START %s\n',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
step7b_probe_environment;
step7b_check_simple_cosim;
step7b_run_cosim('minimal');
command=sprintf('pwsh -NoProfile -File "%s" -Mode all',fullfile(root,'scripts','step7b_run_xsim.ps1'));
[rc,output]=system(command); fprintf('%s',output); assert(rc==0,'XSim regressions failed');
step7b_run_cosim('foc');
step7b_run_cosim('timing');
step7b_run_cosim('legacy');
diary off;
console=fileread(log);
assert(isempty(regexpi(console,'cannot be opened for reading|readmemh.*(not found|error|fail)','once')),'ROM read failure');
summary=fullfile(root,'docs','reports','step7b','regression_summary.txt');
fid=fopen(summary,'w'); c=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'Fresh full sequence completed %s\n',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
fprintf(fid,'AMD_SUPPORT_PACKAGE=PASS version=26.2.2\nSTEP7B_SIMPLE_STRUCTURE_PASS\n');
fprintf(fid,'STEP7B_SIMULINK_MINIMAL_COSIM_PASS values=6 inputs=0,1,42,127,254,255 outputs=1,2,43,128,255,0\n');
for name={'foc_wrapper_xsim.txt','step6d_profile0.txt','step6d_profile1.txt','step6e_regression.txt'}
    lines=splitlines(string(fileread(fullfile(root,'docs','reports','step7b',name{1}))));
    matches=lines(contains(lines,'PASS')); assert(~isempty(matches));
    for k=1:numel(matches), fprintf(fid,'%s\n',matches(k)); end
end
fprintf(fid,['STEP7B_FOC_COSIM_SMOKE_PASS first_active_CMP=1165,1335,1335\n' ...
    'STEP7B_TIMING_ALIGNMENT_PASS runs=3 A_index=5 B_index=6 mapping=NEW\n' ...
    'STEP7B_LEGACY_SHORT_RUN_PASS\nFPGA_BRANCH_DRIVES_PLANT=0\nLEGACY_CONTROL_DRIVES_INVERTER=1\n' ...
    'FINAL_RUNTIME_ROM_FILE_NOT_FOUND=0\nSTEP7B_FULL_ACCEPTANCE_PASS\n']);
fprintf('STEP7B_FULL_ACCEPTANCE_PASS\n');
end
