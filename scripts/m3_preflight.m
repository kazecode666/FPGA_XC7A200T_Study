function result=m3_preflight(cfg)
% 在独立batch会话执行，不改变用户交互Base Workspace。
assert(isfolder(cfg.source_dir),'M3:SOURCE_SNAPSHOT_MISSING','Freeze local source first.');
folder=[tempname(cfg.run_dir) '_preflight'];mkdir(folder);
files=dir(cfg.source_dir);for k=1:numel(files),if ~files(k).isdir,copyfile(fullfile(cfg.source_dir,files(k).name),fullfile(folder,files(k).name));end;end
oldpwd=pwd;oldpath=path;oldgen=Simulink.fileGenControl('getConfig');
cleanup=onCleanup(@()restore(cfg,oldpwd,oldpath,oldgen)); %#ok<NASGU>
cd(folder);addpath(folder,'-begin');Simulink.fileGenControl('set','CacheFolder',fullfile(folder,'cache'),'CodeGenFolder',fullfile(folder,'code'),'createDir',true);
evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');
m=cfg.model;load_system(fullfile(folder,[m '.slx']));
assert(strcmpi(get_param(m,'FileName'),fullfile(folder,[m '.slx'])));
set_param(m,'FixedStep','Ts_ACR','SampleTimeConstraint','Unconstrained');
inputs=find_system(m,'SearchDepth',1,'BlockType','Inport');
for k=1:numel(inputs),set_param(inputs{k},'SampleTime','Ts_ACR');end
feval(m,[],[],[],'compile');ports=cell(0,6);
for kind={'Inport','Outport'}
    blocks=find_system(m,'SearchDepth',1,'BlockType',kind{1});
    for k=1:numel(blocks)
        t=get_param(blocks{k},'CompiledPortDataTypes');dt=t.Outport;if isempty(dt),dt=t.Inport;end
        ports(end+1,:)={kind{1},get_param(blocks{k},'Port'),get_param(blocks{k},'Name'),dt{1}, ...
            mat2str(get_param(blocks{k},'CompiledSampleTime')),get_param(blocks{k},'OutDataTypeStr')}; %#ok<AGROW>
    end
end
state=cell(0,5);
for sid=[47 78 213 214 215]
    b=Simulink.ID.getFullName(sprintf('%s:%d',m,sid));t=get_param(b,'CompiledPortDataTypes');
    state(end+1,:)={get_param(b,'SID'),b,t.Outport{1},get_param(b,'InitialCondition'),mat2str(get_param(b,'CompiledSampleTime'))}; %#ok<AGROW>
end
feval(m,[],[],[],'term');
writetable(cell2table(ports,'VariableNames',{'direction','index','name','compiled_type','sample_time','declared_type'}),fullfile(folder,'source_ports.csv'));
writetable(cell2table(state,'VariableNames',{'SID','block','compiled_type','initial_condition','sample_time'}),fullfile(folder,'source_states.csv'));
close_system(m,0);
positive=m3_compare_bits(["20000000" "2000000000000001" "800000000000000001"], ...
    ["20000000" "2000000000000001" "800000000000000001"]);
rejected=false;try,m3_compare_bits("20000000","20000001");catch e,rejected=strcmp(e.identifier,'M3:BIT_MISMATCH');end;assert(rejected);
rejected64=false;try,m3_compare_bits("2000000000000001","2000000000000000");catch e,rejected64=strcmp(e.identifier,'M3:BIT_MISMATCH');end;assert(rejected64);
result=struct('stage','preflight','status','PASS','run_dir',cfg.run_dir, ...
    'version',version,'process',matlabProcessID,'HDL_Coder_license',license('test','Simulink_HDL_Coder'), ...
    'bit_positive_words',positive.words,'bit_flip_negative_rejected',rejected, ...
    'wide_low_bit_negative_rejected',rejected64,'evidence',{{fullfile(folder,'source_ports.csv'),fullfile(folder,'source_states.csv')}}, ...
    'failures',{{}});
phaseCfg=cfg;phaseCfg.run_dir=folder;result.pwm=m3_measure_pwm_phase(phaseCfg,folder);
fid=fopen(fullfile(cfg.run_dir,'preflight_result.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
disp('M3_PREFLIGHT_PASS');
end
function restore(cfg,oldpwd,oldpath,oldgen)
for n={cfg.model,'PMLSM_PI_FOC_Float_Baseline'},if bdIsLoaded(n{1}),close_system(n{1},0);end;end
cd(oldpwd);path(oldpath);Simulink.fileGenControl('setConfig','config',oldgen);
end
