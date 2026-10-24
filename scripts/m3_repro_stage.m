function result=m3_repro_stage(cfg)
% 本阶段须由独立batch进程调用；重新生成并以原始文件SHA逐项比较。
m3_require_batch_models(cfg);
repeatDir=[tempname(cfg.run_dir) '_repeat'];mkdir(repeatDir);
repeatCfg=m3_foc_codegen_config(cfg.root,repeatDir);mkdir(repeatCfg.source_dir);
files=dir(cfg.source_dir);for k=1:numel(files),if ~files(k).isdir,copyfile(fullfile(cfg.source_dir,files(k).name),fullfile(repeatCfg.source_dir,files(k).name));end;end
m3_preflight(repeatCfg);
generation=m3_generate_stage(repeatCfg);assert(strcmp(generation.status,'PASS'),'M3:REPEAT_GENERATION');
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
    'raw_file_comparison','exact SHA256 including ordinary TB and data; no exclusions');
file=fullfile(cfg.run_dir,'repro_result.json');assert(~isfile(file),'M3:EVIDENCE_EXISTS');
fid=fopen(file,'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
end
function run(command)
[code,console]=system(command);fprintf('%s',console);assert(code==0,'M3:REPRO_COMMAND','Command failed with exit%d.',code);
end
