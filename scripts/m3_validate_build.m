function result=m3_validate_build(cfg)
% 已有run只能消费同源、同数值配置/生成配置的最终清单。
manifest=fullfile(cfg.run_dir,'manifest.json');m=jsondecode(fileread(manifest));
assert(strcmp(m.dut_top,'FOC_DUT')&&strcmp(m.part,cfg.part)&&m.clock_period_ns==cfg.clock_period_ns,'M3:BUILD_CONTRACT');
file=m.build_identity.configuration_readback;
assert(strcmp(m3_sha256(file),m.build_identity.configuration_sha256),'M3:CONFIG_HASH');
readback=jsondecode(fileread(file));
for k=1:size(cfg.hdl,1)
    key=cfg.hdl{k,1};assert(isfield(readback,key),'M3:CONFIG_DRIFT','Missing generated config %s.',key);
    wanted=normalize(cfg.hdl{k,2});actual=normalize(readback.(key));
    assert(strcmp(wanted,actual),'M3:CONFIG_DRIFT','Regenerate for changed %s: %s vs %s.',key,wanted,actual);
end
for k=1:numel(m.build_identity.source_files)
    e=m.build_identity.source_files(k);assert(strcmp(m3_sha256(fullfile(cfg.source_dir,e.path)),e.sha256),'M3:SOURCE_HASH');
end
for kind={'design_files','testbench_files','data_files'}
    entries=m.(kind{1});
    for k=1:numel(entries),e=entries(k);assert(strcmp(m3_sha256(fullfile(m.root_dir,e.path)),e.sha256),'M3:ARTIFACT_HASH');end
end
result=struct('status','PASS','manifest_sha256',m3_sha256(manifest), ...
    'source_files',numel(m.build_identity.source_files),'configuration_fields',size(cfg.hdl,1));
end
function value=normalize(value)
value=lower(char(string(value)));if strcmp(value,'sync'),value='synchronous';end
end
