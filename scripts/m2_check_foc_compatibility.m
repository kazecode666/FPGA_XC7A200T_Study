function result=m2_check_foc_compatibility
% 仅兼容性检查和活动编译类型；不生成HDL/C代码。
root=fileparts(fileparts(mfilename('fullpath')));folder=fullfile(root,'docs/reports/m2_foc_fixed_point');addpath(fullfile(root,'simulink模型'));
[modelFolder,modelCleanup]=m2_test_model_files;evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');m2_bind_test_models(modelFolder);m='PMLSM_FOC_FixedPoint';load_system(fullfile(modelFolder,[m '.slx']));assert(strcmp(get_param(m,'DataTypeOverride'),'Off'));
checks=checkhdl([m '/FOC_DUT']);writejson(fullfile(folder,'hdl_checks.json'),checks);
errors=sum(strcmpi({checks.level},'Error'));warnings=sum(strcmpi({checks.level},'Warning'));messages=sum(strcmpi({checks.level},'Message'));
feval(m,[],[],[],'compile');finish=onCleanup(@()feval(m,[],[],[],'term'));blocks=find_system([m '/FOC_DUT'],'LookUnderMasks','all','FollowLinks','on','MatchFilter',@Simulink.match.activeVariants,'Type','Block');rows=cell(0,4);
for k=1:numel(blocks)
 t=get_param(blocks{k},'CompiledPortDataTypes');for key={'Inport','Outport'},if ~isfield(t,key{1}),continue;end;v=t.(key{1});for j=1:numel(v),rows(end+1,:)={strrep(blocks{k},newline,' '),key{1},j,v{j}};assert(~ismember(v{j},{'double','single','half'}),'M2:FLOATING_PATH','%s',blocks{k});end;end %#ok<AGROW>
end
writetable(cell2table(rows,'VariableNames',{'block','direction','port','compiled_type'}),fullfile(folder,'compiled_types.csv'),'QuoteStrings',true);clear finish
% Local tags must resolve uniquely in exactly the same parent.
routeRows=cell(0,4);for model={m,'PMLSM_PI_FOC_Float_Baseline'}
 load_system(fullfile(modelFolder,[model{1} '.slx']));g=find_system(model{1},'LookUnderMasks','all','FollowLinks','off','MatchFilter',@Simulink.match.allVariants,'BlockType','Goto');f=find_system(model{1},'LookUnderMasks','all','FollowLinks','off','MatchFilter',@Simulink.match.allVariants,'BlockType','From');
 for k=1:numel(g),assert(strcmp(get_param(g{k},'TagVisibility'),'local'),'M2:NONLOCAL_ROUTE','%s',g{k});end
 for k=1:numel(f),parent=get_param(f{k},'Parent');tag=get_param(f{k},'GotoTag');match=g(cellfun(@(b)strcmp(get_param(b,'Parent'),parent)&&strcmp(get_param(b,'GotoTag'),tag),g));assert(isscalar(match),'M2:AMBIGUOUS_ROUTE','%s',f{k});routeRows(end+1,:)={model{1},parent,tag,match{1}};end %#ok<AGROW>
 set_param(model{1},'SimulationCommand','update');
end
writetable(cell2table(routeRows,'VariableNames',{'model','parent','tag','goto'}),fullfile(folder,'local_routing.csv'),'QuoteStrings',true);
result=struct('pass',errors==0,'version',version,'process',matlabProcessID,'DUT',[m '/FOC_DUT'],'DataTypeOverride','Off','errors',errors,'warnings',warnings,'messages',messages,'floating_numeric_ports',0,'compiled_port_rows',size(rows,1),'local_from_routes',size(routeRows,1),'algorithm_added_delay_s',0,'sample_s',1e-4,'HDL_target_language',hdlget_param(m,'TargetLanguage'),'synthesis_tool',hdlget_param(m,'SynthesisTool'),'target_frequency_setting',hdlget_param(m,'TargetFrequency'),'HDL_C_generated',false,'Vivado_run',false,'hardware_clock_or_resource_claim',false);
writejson(fullfile(folder,'hdlcheck_acceptance.json'),result);assert(errors==0,'M2:HDL_COMPATIBILITY','存在兼容性Error，见hdl_checks.json。');fprintf('M2_HDLCHECK_PASS errors=%d warnings=%d messages=%d\n',errors,warnings,messages);
end
function writejson(file,value),fid=fopen(file,'w');assert(fid>=0);finish=onCleanup(@()fclose(fid));fprintf(fid,'%s',jsonencode(value,PrettyPrint=true));end
