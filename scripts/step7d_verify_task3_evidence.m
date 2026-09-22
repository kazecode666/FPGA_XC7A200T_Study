function step7d_verify_task3_evidence
root=fileparts(fileparts(mfilename('fullpath')));
d=fullfile(root,'docs','reports','step7d');
for n={'normal','canary'}
 txt=fileread(fullfile(d,'task3_verified',n{1},'run_summary.txt'));
 p=regexp(txt,'RAW_DIR=([^\r\n]+)','tokens','once'); a=load(fullfile(p{1},'result.mat'),'r');
 step7d_assert_result(a.r,a.r.cfg);
 if strcmp(n{1},'normal'), normal=a.r; else, canary=a.r; end
end
assert(isequal(normal.adapter_inputs,canary.adapter_inputs) && isequal(normal.command_events,canary.command_events));
assert(canary.effective_config.smoke_iq==-.3 && all(canary.effective_config.unselected_iq_script==.17));
txt=fileread(fullfile(d,'task3_legacy_after','baseline_before.txt')); p=regexp(txt,'RAW_DIR=([^\r\n]+)','tokens','once');
before=fullfile(root,'.Xil','step7d','20260922_113014_967');
files=dir(fullfile(p{1},'*.mat')); assert(numel(files)==3);
for k=1:numel(files)
 a=load(fullfile(before,files(k).name),'r'); b=load(fullfile(p{1},files(k).name),'r');
 assert(isequal(a.r.time_s,b.r.time_s) && isequal(a.r.events,b.r.events));
 names=fieldnames(a.r.signals);
 for j=1:numel(names), assert(max(abs(a.r.signals.(names{j})-b.r.signals.(names{j})))<=1e-10); end
end
disp('STEP7D_LIVE_INTERFACE_PASS'); disp('STEP7D_TIMING_PASS'); disp('STEP7D_LEGACY_EQUIVALENCE_PASS');
end
