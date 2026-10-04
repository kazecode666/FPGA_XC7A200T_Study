function study_l1_c_csd(runDir)
% Exactly one HDL option at one block: AW ConstMultiplierOptimization none->csd.
study=fileparts(fileparts(mfilename('fullpath')));
assert(~isfolder(runDir)); mkdir(runDir);
diary(fullfile(runDir,'matlab_run.txt')); z=onCleanup(@()diary('off')); %#ok<NASGU>
assert(strcmp(version('-release'),'2026b') && license('test','Simulink_HDL_Coder'));
cfg=Simulink.fileGenControl('getConfig');
restore=onCleanup(@()Simulink.fileGenControl('setConfig','config',cfg)); %#ok<NASGU>
Simulink.fileGenControl('set','CacheFolder',fullfile(runDir,'cache'), ...
    'CodeGenFolder',fullfile(runDir,'codegen'),'createDir',true);
model='speed_pi_hdl'; core=[model '/HDLCore'];
assert(~bdIsLoaded(model));
copyfile(fullfile(study,'models',[model '.slx']),fullfile(runDir,[model '.slx']));
load_system(fullfile(runDir,[model '.slx']));
c=onCleanup(@()close_system(model,0)); %#ok<NASGU>
baseline=jsondecode(fileread(fullfile(study,'reports/checkpoint_b/generator_config.json')));
opts=baseline.global_options;
for k=1:2:numel(opts)
    value=hdlget_param(model,opts{k});
    fprintf('GLOBAL_READBACK %s actual=%s baseline=%s\n',opts{k},string(value),string(opts{k+1}));
    assert(strcmpi(string(value),string(opts{k+1})),'Baseline global HDL setting drift: %s',opts{k});
end
assert(hdlget_param(core,'InputPipeline')==1 && hdlget_param(core,'OutputPipeline')==1);
assert(strcmp(hdlget_param([core '/PI/AW'],'ConstMultiplierOptimization'),'none'));
before=fingerprint([core '/PI']);
% Sole experimental mutation. No coefficient, type, carrier or solver change.
hdlset_param([core '/PI/AW'],'ConstMultiplierOptimization','csd');
assert(isequal(before,fingerprint([core '/PI'])));
assert(strcmp(hdlget_param([core '/PI/P'],'ConstMultiplierOptimization'),'none'));
assert(strcmp(hdlget_param([core '/PI/KiTs'],'ConstMultiplierOptimization'),'none'));
for k=1:2:numel(opts)
    assert(strcmpi(string(hdlget_param(model,opts{k})),string(opts{k+1})));
end
record=struct('only_option','ConstMultiplierOptimization','block',[core '/PI/AW'], ...
    'baseline','none','experiment','csd','other_gain_options','none', ...
    'InputPipeline',1,'OutputPipeline',1,'global_options',{opts}, ...
    'numerical_block_parameters_and_wiring_identical',true,'target_part','xc7a200tfbg484-2');
write(fullfile(runDir,'single_option_config.json'),jsonencode(record,PrettyPrint=true));
write(fullfile(runDir,'pi_semantic_fingerprint.json'),jsonencode(before,PrettyPrint=true));
checks=checkhdl(core); disp(checks);
assert(isempty(checks) || ~any(strcmp({checks.level},'Error')));
write(fullfile(runDir,'compatibility.json'),jsonencode(checks,PrettyPrint=true));
save_system(model,fullfile(runDir,[model '.slx']));
fprintf('SINGLE_OPTION_PREFLIGHT_PASS AW ConstMultiplierOptimization none -> csd\n');
makehdl(core,'TargetDirectory',fullfile(runDir,'generated'));
fprintf('STUDY_L1_C_CSD_GENERATION_PASS\n');
end

function out=fingerprint(system)
paths=sort(find_system(system,'SearchDepth',1,'Type','Block')); paths=paths(~strcmp(paths,system));
blocks=struct;
for j=1:numel(paths)
    path=paths{j}; names=sort(fieldnames(get_param(path,'DialogParameters'))); params=struct;
    for k=1:numel(names), params.(names{k})=get_param(path,names{k}); end
    blocks.(get_param(path,'Name'))=struct('type',get_param(path,'BlockType'),'parameters',params);
end
connections={}; lines=find_system(system,'SearchDepth',1,'FindAll','on','Type','line');
for line=reshape(lines,1,[])
    src=get_param(line,'SrcPortHandle'); dst=get_param(line,'DstPortHandle');
    if src<0, continue; end
    for d=reshape(dst,1,[])
        connections{end+1}=sprintf('%s/%s:%d -> %s/%s:%d', ...
            get_param(get_param(src,'Parent'),'Name'),get_param(src,'PortType'),get_param(src,'PortNumber'), ...
            get_param(get_param(d,'Parent'),'Name'),get_param(d,'PortType'),get_param(d,'PortNumber')); %#ok<AGROW>
    end
end
out=struct('blocks',blocks,'connections',{sort(unique(connections))});
end
function write(path,txt)
f=fopen(path,'w','n','UTF-8'); c=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'%s\n',txt);
end
