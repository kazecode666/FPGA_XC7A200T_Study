function result=m3_foc_hdl(stage,runDir)
% M3开发入口；每个run目录拥有来源和证据，普通主模型Run不调用此入口。
arguments
    stage (1,:) char {mustBeMember(stage,{'preflight','generate','model','rtl','synth','repro','all'})}
    runDir (1,:) char = ''
end
root=fileparts(fileparts(mfilename('fullpath')));
if isempty(runDir),runDir=tempname(fullfile(root,'.runtime'));mkdir(runDir);end
if ~isfolder(runDir),mkdir(runDir);end
cfg=m3_foc_codegen_config(root,runDir);
if ~isfolder(cfg.source_dir)
    mkdir(cfg.source_dir);source=fullfile(root,'simulink模型');
    files={'PMLSM_PI_FOC_Float_Baseline.slx','PMLSM_FOC_FixedPoint.slx','init_PMLSM_PI_FOC_Float_Baseline.m', ...
        'm1a_require_float_init.m','pmlsm_foc_fixed_config.m','design_PMLSM_three_loop.m','pmlsm_scurve_profile.m','pmlsm_point_move_step.m'};
    for k=1:numel(files),copyfile(fullfile(source,files{k}),fullfile(cfg.source_dir,files{k}));end
end
if strcmp(stage,'all')
    result=struct('stage','all','status','PASS','run_dir',runDir,'evidence',{{}},'failures',{{}});
    for name={'preflight','generate','model','rtl','synth','repro'}
        item=m3_foc_hdl(name{1},runDir);result.(name{1})=item;
        if ~strcmp(item.status,'PASS'),result.status='FAIL';result.failures{end+1}=item;end
    end
    writejson(fullfile(runDir,'all_result.json'),result);
    assert(strcmp(result.status,'PASS'),'M3:INCOMPLETE','M3 contains failed/blocked stages; see %s.',runDir);return
end
result=struct('stage',stage,'status','NOT_RUN','run_dir',runDir,'evidence',{{}},'failures',{{}});
try
    if strcmp(stage,'preflight')
        file=fullfile(runDir,'preflight_result.json');
        if isfile(file),result=jsondecode(fileread(file));else,result=m3_preflight(cfg);end
    elseif any(strcmp(stage,{'rtl','synth','model','repro'}))&&~isfile(fullfile(runDir,'manifest.json'))
        result.status='BLOCKED';result.failures={struct('identifier','M3:GENERATED_ARTIFACT_MISSING', ...
            'message','Missing final generated manifest; no tool success or evidence may be inferred.')};
        writejson(fullfile(runDir,[stage '_missing_artifact.json']),result);
    else
        implementation=['m3_' stage '_stage'];
        assert(exist(implementation,'file')==2,'M3:STAGE_NOT_IMPLEMENTED','Missing %s.',implementation);
        result=feval(implementation,cfg);
    end
catch exception
    result.status='FAIL';result.failures={struct('identifier',exception.identifier,'message',exception.message)};
    file=[tempname(runDir) '_' stage '_failure.json'];writejson(file,result);
    fprintf(2,'M3_STAGE_FAIL %s %s %s\n',stage,exception.identifier,exception.message);
end
fprintf('M3_STAGE %s %s %s\n',stage,result.status,runDir);
end
function writejson(file,value)
assert(~isfile(file),'M3:EVIDENCE_EXISTS','Refuse to overwrite %s.',file);
fid=fopen(file,'w');fprintf(fid,'%s\n',jsonencode(value,PrettyPrint=true));fclose(fid);
end
