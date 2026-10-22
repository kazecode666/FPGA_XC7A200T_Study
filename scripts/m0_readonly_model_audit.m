function m0_readonly_model_audit
% M0 isolated-process audit. No update, simulation, build, hardware or save.
% Invoke only in a fresh MATLAB -batch process after static callback review.
root=fileparts(fileparts(mfilename('fullpath')));
out=fullfile(root,'.superpowers','m0_20261022');
assert(isfolder(out),'Run the static audit first.');
addpath(fullfile(root,'simulink模型')); addpath(fullfile(root,'scripts'));
cd(root);
env=struct('version',version,'release',version('-release'),'matlabroot',matlabroot, ...
    'products',ver,'addons',table2struct(matlab.addons.installedAddons), ...
    'loaded_on_entry',{find_system('type','block_diagram')}, ...
    'execution','load/query/parameter scripts only; no update/sim/build/save');
assert(isempty(env.loaded_on_entry),'Use an independent batch process.');
writejson(fullfile(out,'environment.json'),env);
models={'PMLSM_MIL_ControlCore_Sim','PMLSM_ControlCore_Block', ...
    'PMLSM_ThreeLoop_Simple','PMSLM_Close_Loop_MBDL4'};
for n=1:numel(models)
    m=models{n}; result=struct('model',m,'loaded',false,'error','','blocks',[], ...
        'config',struct,'workspace',struct,'resolved',struct,'dirty_after_load','');
    try
        load_system(fullfile(root,'simulink模型',[m '.slx']));
        result.loaded=true; result.dirty_after_load=get_param(m,'Dirty');
        fields={'FileName','InitFcn','PreLoadFcn','PostLoadFcn','StartFcn','StopFcn', ...
            'SolverType','Solver','FixedStep','StartTime','StopTime','SystemTargetFile', ...
            'HardwareBoard','DataDictionary','ModelVersion'};
        for k=1:numel(fields)
            try, result.config.(fields{k})=get_param(m,fields{k}); catch, end
        end
        mw=get_param(m,'ModelWorkspace');
        result.workspace.datasource=mw.DataSource;
        try, result.workspace.filename=mw.FileName; catch, end
        result.workspace.variables=whos(mw);
        result.workspace.numeric=struct;
        for k=1:numel(result.workspace.variables)
            name=result.workspace.variables(k).name;
            v=mw.getVariable(name);
            if isa(v,'Simulink.Parameter'), v=v.Value; end
            if (isnumeric(v)||islogical(v)) && numel(v)<40
                result.workspace.numeric.(name)=v;
            end
        end
        blocks=find_system(m,'FollowLinks','off','LookUnderMasks','all', ...
            'MatchFilter',@Simulink.match.allVariants,'Type','Block');
        rows=repmat(struct('path','','sid','','type','','link','','reference','', ...
            'parameters',struct,'inputs',[]),numel(blocks),1);
        keys={'SampleTime','Value','Gain','InitialCondition','UpperLimit','LowerLimit', ...
            'Threshold','Criteria','GotoTag','TagVisibility','DataStoreName','ModelName', ...
            'ModelNameDialog','VariantControl','VariantControlMode','MaskType','MaskInitialization', ...
            'MaskNames','MaskValues','FunctionName','DelayLength','Port','Operator','Inputs'};
        for k=1:numel(blocks)
            b=blocks{k}; rows(k).path=b; rows(k).sid=Simulink.ID.getSID(b);
            rows(k).type=get_param(b,'BlockType');
            try, rows(k).link=get_param(b,'LinkStatus'); rows(k).reference=get_param(b,'ReferenceBlock'); catch, end
            for j=1:numel(keys)
                try, rows(k).parameters.(keys{j})=get_param(b,keys{j}); catch, end
            end
            try
                ph=get_param(b,'PortHandles'); ins=cell(1,numel(ph.Inport));
                for j=1:numel(ph.Inport)
                    line=get_param(ph.Inport(j),'Line');
                    if line<0, ins{j}='DISCONNECTED'; continue; end
                    src=get_param(line,'SrcPortHandle');
                    if src<0, ins{j}='UNRESOLVED'; continue; end
                    ins{j}=sprintf('%s#out:%g',get_param(src,'Parent'),get_param(src,'PortNumber'));
                end
                rows(k).inputs=ins;
            catch
            end
        end
        result.blocks=rows; result.dirty_after_query=get_param(m,'Dirty');
    catch ME
        result.error=getReport(ME,'extended','hyperlinks','off');
    end
    writejson(fullfile(out,[m '_runtime.json']),result);
    fprintf('M0_MODEL %s loaded=%d dirty=%s blocks=%d error=%s\n',m,result.loaded,result.dirty_after_load,numel(result.blocks),result.error);
end
% Explicitly run the reviewed parameter chain, never the model InitFcn.
evalin('base','PMSLM_Init_Params_MBDL4;');
stages=struct('DSP',basevalues());
evalin('base','init_PMLSM_control_params; init_PMLSM_plant_params; init_PMLSM_mil_test_params;');
stages.MIL=basevalues();
if bdIsLoaded('PMLSM_ThreeLoop_Simple')
    m='PMLSM_ThreeLoop_Simple'; mw=get_param(m,'ModelWorkspace');
    vars=whos(mw); numeric=struct;
    for k=1:numel(vars)
        v=mw.getVariable(vars(k).name);
        if isa(v,'Simulink.Parameter'),v=v.Value;end
        if (isnumeric(v)||islogical(v)) && numel(v)<40,numeric.(vars(k).name)=v;end
    end
    stages.SimpleModelWorkspace=numeric;
    probes={'Kp_ACR','Ki_ACR','Ts_ACR','Kp_ASR','Ki_ASR','Ts_ASR','Kp_pos', ...
        'Kaw_d','Kaw_q','Kaw_s','Udc','PMLSM_pwm_period_counts','PMLSM_Ts_s'};
    resolved=struct;
    for k=1:numel(probes)
        try,resolved.(probes{k})=slResolve(probes{k},[m '/Control_Task_10kHz']);catch ME,resolved.(probes{k})=ME.message;end
    end
    stages.SimpleResolutionAfterMILBase=resolved;
end
writejson(fullfile(out,'parameter_stages.json'),stages);
% No save_system: discard only models belonging to this fresh process.
for n=1:numel(models)
    if bdIsLoaded(models{n})
        fprintf('M0_CLOSE %s dirty=%s save=0\n',models{n},get_param(models{n},'Dirty'));
        close_system(models{n},0);
    end
end
fprintf('M0_READONLY_QUERY_COMPLETE UPDATE=0 SIM=0 BUILD=0 SAVE=0\n');
end

function values=basevalues
vars=evalin('base','whos'); values=struct;
for k=1:numel(vars)
    v=evalin('base',vars(k).name);
    if isa(v,'Simulink.Parameter'),v=v.Value;end
    if (isnumeric(v)||islogical(v)) && numel(v)<40
        values.(vars(k).name)=v;
    end
end
end

function writejson(file,value)
f=fopen(file,'w','n','UTF-8'); assert(f>=0); c=onCleanup(@()fclose(f)); %#ok<NASGU>
fwrite(f,jsonencode(value,PrettyPrint=true),'char');
end
