function test_m3_candidate_config(runDir)
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));addpath(fullfile(root,'scripts'));
cfg=m3_foc_codegen_config(root,runDir);m3_validate_build(cfg);
bad=cfg;bad.candidate.candidate_id='p3';reject(bad,'M3:CANDIDATE_ID');
bad=cfg;bad.candidate.settings(1).value='off';reject(bad,'M3:CANDIDATE_CONFIG');
fprintf('M3_CANDIDATE_CONFIG_TEST_PASS 3\n');
end
function reject(cfg,id)
rejected=false;try,m3_validate_build(cfg);catch e,rejected=strcmp(e.identifier,id);end
assert(rejected,'M3:TEST_EXPECTED_REJECTION','Expected %s.',id);
end
