function result=m3_repro_stage(cfg)
% 即使由all调用，也在新的batch子进程重新生成；不继承首次生成状态。
m3_require_batch_models(cfg);
repeatDir=fullfile(cfg.run_dir,'repeat');assert(~isfolder(repeatDir),'M3:EVIDENCE_EXISTS','Use a fresh run directory.');mkdir(repeatDir);
process=m3_repeat_process(cfg,repeatDir);
manifest=fullfile(cfg.run_dir,'manifest.json');other=fullfile(repeatDir,'manifest.json');
comparison=fullfile(repeatDir,'repeat_identity.json');
helper=fullfile(cfg.root,'scripts','m3_publish_generated.py');
run(sprintf('python "%s" compare --first "%s" --repeat "%s" --output "%s"',helper,manifest,other,comparison));
runner=fullfile(cfg.root,'scripts','m3_run_xsim.ps1');
smoke=[tempname(cfg.run_dir) '_repeat_smoke'];
run(sprintf('pwsh -NoProfile -File "%s" -Manifest "%s" -RunDir "%s" -Case repeat_generated_smoke',runner,other,smoke));
release=[tempname(cfg.run_dir) '_release'];
run(sprintf('python "%s" publish --manifest "%s" --destination "%s"',helper,manifest,release));
relocated=[tempname(cfg.run_dir) '_relocated_smoke'];
run(sprintf('pwsh -NoProfile -File "%s" -Manifest "%s" -RunDir "%s" -Case relocated_generated_smoke',runner,fullfile(release,'manifest.json'),relocated));
result=struct('stage','repro','status','PASS','run_dir',cfg.run_dir, ...
    'evidence',{{comparison,fullfile(smoke,'result.json'),fullfile(relocated,'result.json')}}, ...
    'failures',{{}},'repeat_dir',repeatDir,'release_dir',release, ...
    'process_identity',process, ...
    'raw_file_comparison','exact SHA256 including ordinary TB and data; no exclusions');
file=fullfile(cfg.run_dir,'repro_result.json');assert(~isfile(file),'M3:EVIDENCE_EXISTS');
fid=fopen(file,'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
end
function run(command)
[code,console]=system(command);fprintf('%s',console);assert(code==0,'M3:REPRO_COMMAND','Command failed with exit%d.',code);
end
