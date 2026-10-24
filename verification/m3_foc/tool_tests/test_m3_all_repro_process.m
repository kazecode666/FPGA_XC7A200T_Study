function result=test_m3_all_repro_process(runDir,identityFixture)
% 仅隔离替换已单独完整验过的C/D/E；真实all的A/B/F仍实际生成/仿真。
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
if nargin<2,identityFixture='';end
mkdir(runDir);fixture=fullfile(runDir,'orchestration_only_stubs');mkdir(fixture);
if ~isempty(identityFixture)
    % 快速RED仅用已验证包作身份fixture；不是首次/重复FOC生成证据。
    fid=fopen(fullfile(fixture,'m3_generate_stage.m'),'w');
    fprintf(fid,['function r=m3_generate_stage(cfg)\n' ...
        'copyfile(''%s'',fullfile(cfg.run_dir,''manifest.json''));\n' ...
        'b=struct(''matlab_process_id'',matlabProcessID);f=fopen(fullfile(cfg.run_dir,''final_build.json''),''w'');fprintf(f,''%%s'',jsonencode(b));fclose(f);\n' ...
        'r=struct(''stage'',''generate'',''status'',''PASS'',''run_dir'',cfg.run_dir,''evidence'',{{}},''failures'',{{}},''test_only'',true);\nend\n'], ...
        strrep(identityFixture,'''',''''''));fclose(fid);
end
for stage={'model','rtl','synth'}
    file=fullfile(fixture,['m3_' stage{1} '_stage.m']);fid=fopen(file,'w');
    status='PASS';if strcmp(stage{1},'synth'),status='FAIL';end
    fprintf(fid,'function r=m3_%s_stage(cfg)\nr=struct(''stage'',''%s'',''status'',''%s'',''run_dir'',cfg.run_dir,''evidence'',{{}},''failures'',{{}},''test_only'',true);\nend\n',stage{1},stage{1},status);fclose(fid);
end
oldpath=path;cleanup=onCleanup(@()path(oldpath)); %#ok<NASGU>
addpath(fullfile(root,'scripts'));addpath(fixture,'-begin');
failed=false;try,m3_foc_hdl('all',runDir);catch e,failed=strcmp(e.identifier,'M3:INCOMPLETE');end
assert(failed,'M3:ALL_FAILURE','Synthetic E FAIL must make all nonzero after F runs.');
a=jsondecode(fileread(fullfile(runDir,'all_result.json')));
assert(a.model.test_only&&a.rtl.test_only&&a.synth.test_only,'M3:FIXTURE_SCOPE','Only C/D/E may be stubbed.');
assert(strcmp(a.generate.status,'PASS')&&strcmp(a.repro.status,'PASS'),'M3:REAL_GENERATION_REQUIRED','Both real generation stages must pass.');
first=jsondecode(fileread(fullfile(runDir,'final_build.json')));
second=jsondecode(fileread(fullfile(a.repro.repeat_dir,'final_build.json')));
result=struct('status','OBSERVED','first_generation_pid',first.matlab_process_id, ...
    'repeat_generation_pid',second.matlab_process_id,'caller_pid',matlabProcessID, ...
    'real_first_repeat_generation_and_smokes',isempty(identityFixture), ...
    'C_D_E_are_explicit_orchestration_stubs_not_FOC_evidence',true);
fid=fopen(fullfile(runDir,'process_test_observation.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
assert(first.matlab_process_id~=second.matlab_process_id&&second.matlab_process_id~=matlabProcessID, ...
    'M3:REPEAT_SAME_PROCESS','Repeated build must be in a distinct process.');
result.status='PASS';
fid=fopen(fullfile(runDir,'process_test_result.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
end
