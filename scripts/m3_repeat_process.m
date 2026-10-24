function proof=m3_repeat_process(cfg,repeatDir)
% 新进程是验收条件；batch调用本身不能代替进程身份检查。
first=jsondecode(fileread(fullfile(cfg.run_dir,'final_build.json')));
assert(isfield(first,'matlab_process_id'),'M3:FIRST_PROCESS_UNKNOWN','Rebuild in a fresh run directory to record first generation PID.');
caller=matlabProcessID;firstPID=first.matlab_process_id;
launch=fullfile(repeatDir,'m3_repeat_launch.m');fid=fopen(launch,'w');
fprintf(fid,'addpath(''%s'');\nm3_repeat_generate(''%s'',''%s'',''%s'',%d,%d);\n', ...
    quote(fullfile(cfg.root,'scripts')),quote(cfg.root),quote(cfg.source_dir),quote(repeatDir),caller,firstPID);fclose(fid);
logfile=fullfile(repeatDir,'matlab_repeat.log');exe=fullfile(matlabroot,'bin','matlab.exe');
[code,console]=system(sprintf('"%s" -batch "run(''%s'')" -logfile "%s"',exe,quote(launch),logfile));
fid=fopen(fullfile(repeatDir,'repeat_console.log'),'w');fprintf(fid,'%s',console);fclose(fid);
proof=struct('status','FAIL','caller_pid',caller,'first_generation_pid',firstPID, ...
    'repeat_pid',[],'child_exit_code',code,'logfile',logfile);
start=fullfile(repeatDir,'repeat_process_start.json');
if isfile(start),s=jsondecode(fileread(start));proof.repeat_pid=s.repeat_pid;end
if code==0
    child=jsondecode(fileread(fullfile(repeatDir,'repeat_process.json')));
    assert(child.repeat_pid~=caller&&child.repeat_pid~=firstPID&&strcmp(child.status,'PASS'),'M3:REPEAT_SAME_PROCESS','Child process identity invalid.');
    proof.status='PASS';proof.repeat_pid=child.repeat_pid;
end
file=fullfile(repeatDir,'repeat_process_result.json');fid=fopen(file,'w');fprintf(fid,'%s',jsonencode(proof,PrettyPrint=true));fclose(fid);
fprintf('M3_REPEAT_PROCESS %s caller=%d first=%d repeat=%s exit=%d\n',proof.status,caller,firstPID,mat2str(proof.repeat_pid),code);
assert(code==0,'M3:REPEAT_PROCESS_FAILED','Repeat child failed; retain %s.',logfile);
end
function value=quote(value)
value=strrep(value,'''','''''');
end
