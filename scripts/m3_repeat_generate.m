function m3_repeat_generate(root,sourceDir,repeatDir,callerPID,firstPID)
% 仅由新的MATLAB -batch进程执行，避免继承首次生成的进程状态。
assert(batchStartupOptionUsed,'M3:REPEAT_BATCH_REQUIRED','Repeat generation requires -batch.');
pid=matlabProcessID;
assert(pid~=callerPID&&pid~=firstPID,'M3:REPEAT_SAME_PROCESS','Repeat PID must differ from initial generation and caller.');
proof=struct('status','STARTED','repeat_pid',pid,'caller_pid',callerPID, ...
    'first_generation_pid',firstPID,'source_dir',sourceDir);
writejson(fullfile(repeatDir,'repeat_process_start.json'),proof);
assert(isfolder(sourceDir),'M3:SOURCE_SNAPSHOT_MISSING','Missing frozen source folder %s.',sourceDir);
cfg=m3_foc_codegen_config(root,repeatDir);mkdir(cfg.source_dir);
files=dir(sourceDir);
for k=1:numel(files),if ~files(k).isdir,copyfile(fullfile(sourceDir,files(k).name),fullfile(cfg.source_dir,files(k).name));end;end
m3_preflight(cfg);generation=m3_generate_stage(cfg);
assert(strcmp(generation.status,'PASS'),'M3:REPEAT_GENERATION','Child generation failed.');
proof.status='PASS';writejson(fullfile(repeatDir,'repeat_process.json'),proof);
end
function writejson(file,value)
assert(~isfile(file),'M3:EVIDENCE_EXISTS','Preserve %s.',file);fid=fopen(file,'w');fprintf(fid,'%s',jsonencode(value,PrettyPrint=true));fclose(fid);
end
