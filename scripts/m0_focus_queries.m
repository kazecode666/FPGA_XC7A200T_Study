function m0_focus_queries
% Supplemental read-only queries; fresh -batch process, no InitFcn/update/save.
root=fileparts(fileparts(mfilename('fullpath'))); cd(root);
addpath(fullfile(root,'simulink模型')); addpath(fullfile(root,'scripts'));
out=fullfile(root,'.superpowers','m0_20261022');
r=struct;
libs={'mcbeeMathTransformLib','mcbcontrolslib','c2838xlib','c2802xlib', ...
    'c280xlib','svdschedulerlib','vivadosimlib'};
for k=1:numel(libs), r.libraries.(libs{k})=which(libs{k}); end
names={'PMLSM_ControlCore_Block','PMLSM_ThreeLoop_Simple','PMSLM_Close_Loop_MBDL4'};
rows=struct('model',{},'count_all_variants',{},'dirty',{},'transforms',{});
for k=1:numel(names)
    m=names{k}; load_system(fullfile(root,'simulink模型',[m '.slx']));
    if strcmp(m,'PMLSM_ThreeLoop_Simple')
        mw=get_param(m,'ModelWorkspace'); vars=whos(mw); ts=struct;
        for j=1:numel(vars)
            value=mw.getVariable(vars(j).name);
            if isa(value,'timeseries')
                assert(numel(value.Time)<=256,'Unexpected large scenario data.');
                ts.(vars(j).name)=struct('time',value.Time,'data',value.Data);
            end
        end
        r.simple_timeseries=ts; r.base_after_simple_load=struct;
        for variable={'CONTROL_BACKEND','FPGA_Cosim_Enable','FPGA_Reference_Mode', ...
                'FPGA_Cosim_Ts_s','STEP7C_Comm_Ts_s','FPGA_CLK_Period_s','FPGA_TBPRD'}
            r.base_after_simple_load.(variable{1})=evalin('base',variable{1});
        end
        r.interactive_state_empty=isempty(pmlsm_interactive_cosim_state('get'));
    end
    blocks=find_system(m,'FollowLinks','off','LookUnderMasks','all', ...
        'MatchFilter',@Simulink.match.allVariants,'Type','Block');
    row=struct('model',m,'count_all_variants',numel(blocks),'dirty','', 'transforms',[]);
    trs=struct('path',{},'mask_values',{},'lookup',{});
    for j=1:numel(blocks)
        b=blocks{j}; mask=get_param(b,'MaskType');
        if ~any(strcmp(mask,{'Clarke to Park Angle Transform','Park to Clarke Angle Transform'})),continue;end
        t=struct('path',b,'mask_values',{get_param(b,'MaskValues')},'lookup',[]);
        lookups=find_system(b,'FollowLinks','on','LookUnderMasks','all', ...
            'MatchFilter',@Simulink.match.allVariants,'RegExp','on','Name','Sine-Cosine Lookup');
        vals=struct('path',{},'N_points',{},'dlgSett',{});
        for a=1:numel(lookups)
            v=struct('path',lookups{a},'N_points',[],'dlgSett',[]);
            ws=get_param(lookups{a},'MaskWSVariables');
            for x=1:numel(ws)
                if ismember(ws(x).Name,{'N_points','dlgSett'}),v.(ws(x).Name)=ws(x).Value;end
            end
            vals(end+1)=v; %#ok<AGROW>
        end
        t.lookup=vals; trs(end+1)=t; %#ok<AGROW>
    end
    row.transforms=trs; row.dirty=get_param(m,'Dirty'); rows(end+1)=row; %#ok<AGROW>
    fprintf('M0_FOCUS %s all_variants=%d dirty=%s\n',m,numel(blocks),row.dirty);
end
r.models=rows;
r.code_analyzer=struct;
for name={'m0_readonly_model_audit','m0_focus_queries'}
    r.code_analyzer.(name{1})=checkcode(fullfile(root,'scripts',[name{1} '.m']),'-id');
end
f=fopen(fullfile(out,'focus_queries.json'),'w','n','UTF-8');assert(f>=0);
fprintf(f,'%s',jsonencode(r,PrettyPrint=true));fclose(f);
for k=1:numel(names),close_system(names{k},0);end
fprintf('M0_FOCUS_COMPLETE UPDATE=0 SIM=0 BUILD=0 SAVE=0\n');
end
