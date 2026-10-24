function m3_pr53_probe(id)
root=fileparts(fileparts(mfilename('fullpath')));runDir=fullfile(root,'.runtime/pr53_20261025',id);
cfg=m3_foc_codegen_config(root,runDir);m3_validate_build(cfg);cfg.model_probe_only=true;
r=m3_model_stage(cfg);
assert(strcmp(r.cases{1}.status,'PASS'),'M3:PROBE_FAILED','Directed candidate source/gm/validation failed.');
fprintf('M3_PR53_PROBE_PASS %s\n',id);
end
