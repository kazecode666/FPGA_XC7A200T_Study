function result=m3_generate_stage(cfg)
% 独立batch内仅配置冻结来源的工作副本；不改正式模型或生成SV。
assert(isfile(fullfile(cfg.run_dir,'preflight_result.json')),'M3:PRECONDITION','Preflight required.');
m3_require_batch_models(cfg);
work=[tempname(cfg.run_dir) '_generate'];mkdir(work);modelFolder=fullfile(work,'model');mkdir(modelFolder);
files=dir(cfg.source_dir);for k=1:numel(files),if ~files(k).isdir,copyfile(fullfile(cfg.source_dir,files(k).name),fullfile(modelFolder,files(k).name));end;end
oldpwd=pwd;oldpath=path;oldgen=Simulink.fileGenControl('getConfig');
cleanup=onCleanup(@()restore(cfg,oldpwd,oldpath,oldgen)); %#ok<NASGU>
cd(modelFolder);addpath(modelFolder,'-begin');Simulink.fileGenControl('set','CacheFolder',fullfile(work,'cache'),'CodeGenFolder',fullfile(work,'code'),'createDir',true);
evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');m=cfg.model;
load_system(fullfile(modelFolder,[m '.slx']));assert(strcmpi(get_param(m,'FileName'),fullfile(modelFolder,[m '.slx'])));
set_param(m,'FixedStep','Ts_ACR','SampleTimeConstraint','Unconstrained','DataTypeOverride','Off','SimulationMode','normal');
inputs=find_system(m,'SearchDepth',1,'BlockType','Inport');for k=1:numel(inputs),set_param(inputs{k},'SampleTime','Ts_ACR','Interpolate','off');end
readback=struct;
for k=1:size(cfg.hdl,1)
    hdlset_param(m,cfg.hdl{k,1},cfg.hdl{k,2});readback.(cfg.hdl{k,1})=hdlget_param(m,cfg.hdl{k,1});
end
writejson(fullfile(work,'hdl_config_readback.json'),readback);
checks=checkhdl(cfg.dut);writejson(fullfile(work,'checkhdl.json'),checks);
assert(~any(strcmpi({checks.level},'Error')),'M3:SV_CHECKHDL','SystemVerilog compatibility errors; retain evidence.');
rtl=fullfile(work,'rtl');mkdir(rtl);
save_system(m,fullfile(modelFolder,[m '.slx']));
makehdl(cfg.dut,'TargetDirectory',rtl);
afterMakehdl=struct('work_dir',work,'model_folder',modelFolder,'rtl_dir',rtl, ...
    'matlab_process_id',matlabProcessID,'matlab_version',version);
writejson(fullfile(work,'makehdl_build.json'),afterMakehdl);
fprintf('M3_MAKEHDL_COMPLETED %s\n',rtl);
% TB is generated from actual fixed stimuli, without DPI/C acceleration.
cases=m3_foc_vectors;u=cases(1).u(1:64,:);
ds=Simulink.SimulationData.Dataset;fixedCfg=evalin('base','FOC_Fixed_Config');
keys={'Current','Current','Current','Angle','Omega','Current','Current','Reset','Bus'};
for k=1:9
    if k==8,data=logical(u(:,k));else,data=fi(u(:,k),fixedCfg.Types.(keys{k}),fixedCfg.Fimath);end
    ds=ds.addElement(setinterpmethod(timeseries(data,(0:size(u,1)-1)'*cfg.data_period_s),'zoh'),sprintf('u%d',k));
end
assignin('base','M3_HDL_Stimulus',ds);
set_param(m,'LoadExternalInput','on','ExternalInput','M3_HDL_Stimulus','StopTime',num2str((size(u,1)-1)*cfg.data_period_s,17));
for k=1:size(cfg.tb,1),hdlset_param(m,cfg.tb{k,1},cfg.tb{k,2});end
save_system(m,fullfile(modelFolder,[m '.slx']));
makehdltb(cfg.dut,'TargetDirectory',rtl);
writejson(fullfile(cfg.run_dir,'final_build.json'),afterMakehdl);
result=struct('stage','generate','status','PASS','run_dir',cfg.run_dir, ...
    'evidence',{{work}},'failures',{{}},'rtl_dir',rtl,'model_folder',modelFolder, ...
    'actual_language',hdlget_param(m,'TargetLanguage'),'readback',readback);
writejson(fullfile(work,'generate_result.json'),result);
locker=fullfile(cfg.root,'scripts','m3_lock_manifest.py');
command=sprintf('python "%s" --build "%s" --output "%s"',locker, ...
    fullfile(cfg.run_dir,'final_build.json'),fullfile(cfg.run_dir,'manifest.json'));
[code,console]=system(command);fprintf('%s',console);
assert(code==0,'M3:MANIFEST_LOCK','Post-TB manifest lock failed; preserve generated files.');
disp('M3_GENERATION_AND_TB_COMPLETE');
end
function restore(cfg,oldpwd,oldpath,oldgen)
models=find_system('type','block_diagram');for k=1:numel(models),n=models{k};owned=strcmp(n,cfg.model)||startsWith(n,['gm_' cfg.model]);if owned&&strcmp(get_param(n,'BlockDiagramType'),'model'),close_system(n,0);end;end
cd(oldpwd);path(oldpath);Simulink.fileGenControl('setConfig','config',oldgen);
end
function writejson(file,value)
assert(~isfile(file),'M3:EVIDENCE_EXISTS','Preserve %s.',file);
fid=fopen(file,'w');fprintf(fid,'%s',jsonencode(value,PrettyPrint=true));fclose(fid);
end
