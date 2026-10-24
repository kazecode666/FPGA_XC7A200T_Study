function result=m1b_foc_readiness_audit
% 仅临时副本观测与checkhdl，不生成代码、不保存源模型。
root=fileparts(fileparts(mfilename('fullpath')));m='PMLSM_PI_FOC_Float_Baseline';assert(~bdIsLoaded(m),'M1B:FRESH_AUDIT','请在独立MATLAB进程运行，只读审计不替换已打开模型。');
folder=fullfile(root,'docs/reports/m1b_repeat_moves_alignment');runtime=fullfile(root,'.runtime/m1b_20261024',sprintf('foc_audit_%d',matlabProcessID));mkdir(runtime);copyfile(fullfile(root,'simulink模型',[m '.slx']),fullfile(runtime,[m '.slx']));
addpath(fullfile(root,'simulink模型'));evalin('base','init_PMLSM_PI_FOC_Float_Baseline;Host_Target_mm=1;Host_Traj_Vmax=5;Host_Traj_Amax=50;M1A_StopTime_s=1.2;');addpath(runtime,'-begin');load_system(fullfile(runtime,[m '.slx']));clean=onCleanup(@()close_system(m,0)); %#ok<NASGU>
f=[m '/Control_Task_10kHz/FOC_Algorithm'];
feval(m,[],[],[],'compile');compiled=struct;sample=get_param(f,'CompiledSampleTime');compiled.compiled_sample_times=cellfun(@mat2str,sample,'UniformOutput',false);compiled.types=get_param(f,'CompiledPortDataTypes');compiled.execution='inherited function-call; observed arithmetic period100us';feval(m,[],[],[],'term');
fid=fopen(fullfile(folder,'foc_compiled_interface.json'),'w');fprintf(fid,'%s',jsonencode(compiled,PrettyPrint=true));fclose(fid);
direct=find_system(f,'LookUnderMasks','all','FollowLinks','off','Type','Block');blocks=find_system(f,'LookUnderMasks','all','FollowLinks','on','Type','Block');inventory=cell(numel(blocks),6);defs=cell(0,3);
for k=1:numel(blocks)
 b=blocks{k};type=get_param(b,'BlockType');detail='';params=get_param(b,'DialogParameters');for key={'Gain','Value','Inputs','Operator','Expr','InitialCondition','SampleTime','OutDataTypeStr','RoundingMode','SaturateOnIntegerOverflow'},if isfield(params,key{1}),v=get_param(b,key{1});if ischar(v),detail=[detail key{1} '=' strrep(v,newline,' ') '; '];end;end;end %#ok<AGROW>
 inventory(k,:)={strrep(b,newline,' '),Simulink.ID.getSID(b),type,strrep(get_param(b,'ReferenceBlock'),newline,' '),get_param(b,'LinkStatus'),detail};
 p=get_param(b,'PortHandles');if strcmp(b,f)||~any(strcmp(direct,b))||any(strcmp(type,{'Goto','From','If','ActionPort','TriggerPort'})),continue;end
 for j=1:numel(p.Outport),if get_param(p.Outport(j),'Line')==-1,continue;end;name=sprintf('audit_%d_%d',k,j);set_param(p.Outport(j),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',name,'DataLoggingDecimateData','off');defs(end+1,:)={name,b,j};end %#ok<AGROW>
end
writetable(cell2table(inventory,'VariableNames',{'path','sid','type','library','link_status','parameters'}),fullfile(folder,'foc_blocks.csv'));
vars=Simulink.findVars(m,'SearchReferencedModels','off');rows=cell(0,3);for k=1:numel(vars),users=vars(k).Users;if any(startsWith(users,[f '/'])),try,v=evalin('base',vars(k).Name);if isnumeric(v),rows(end+1,:)={vars(k).Name,mat2str(v,17),strrep(strjoin(users,' | '),newline,' ')};end;catch,end;end;end %#ok<AGROW>
writetable(cell2table(rows,'VariableNames',{'name','value','users'}),fullfile(folder,'foc_parameters.csv'));
% Documented output form performs compatibility checks without HDL/report generation.
result=struct('version',version,'process',matlabProcessID,'source_saved',false,'HDL_generated',false,'C_generated',false,'DUT',f,'checkhdl_ran',false,'toolboxes',ver);
try,checks=checkhdl(f);result.checkhdl_ran=true;result.checkhdl=checks;catch err,result.checkhdl_error=struct('identifier',err.identifier,'message',err.message);end
out=sim(m);ranges=cell(size(defs,1),9);
for k=1:size(defs,1),s=out.logsout.get(defs{k,1}).Values;d=double(s.Data(:));finite=d(isfinite(d));if isempty(finite),lo=NaN;hi=NaN;else,lo=min(finite);hi=max(finite);end;delta=diff(s.Time);ranges(k,:)={strrep(defs{k,2},newline,' '),defs{k,3},class(s.Data),lo,hi,median(delta),numel(s.Time),sum(isnan(d)),sum(isinf(d))};end
writetable(cell2table(ranges,'VariableNames',{'path','port','logged_type','observed_min','observed_max','logged_period_s','samples','NaN_count','Inf_count'}),fullfile(folder,'foc_observed_ranges.csv'));
% Representative saved live/alignment inputs/states are observation evidence, not design limits.
rows=cell(0,5);for file={'point_live.mat','aligned_live.mat','alignment_nominal.mat'},p=fullfile(root,'.runtime/m1b_20261024',file{1});a=load(p,'out');names=getElementNames(a.out.logsout);for n={'ia','ib','ic','theta_control_rad','theta_true_rad','we','id_ref','iq_ref','id','iq','vd_cmd','vq_cmd','x_d','x_q','du_d_z','du_q_z'},if any(strcmp(names,n{1})),s=a.out.logsout.get(n{1}).Values;rows(end+1,:)={file{1},n{1},min(double(s.Data(:))),max(double(s.Data(:))),median(diff(s.Time))};end;end;end %#ok<AGROW>
writetable(cell2table(rows,'VariableNames',{'scene','signal','observed_min','observed_max','logged_period_s'}),fullfile(folder,'foc_scene_ranges.csv'));
result.observation_scene='1mm/1.2s V5 A50; live/reverse and nominal alignment separately';result.instrumented_ports=size(defs,1);save(fullfile(runtime,'audit.mat'),'out','result','-v7.3');fid=fopen(fullfile(folder,'foc_audit.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);disp('M1B_FOC_READONLY_AUDIT_DONE');
end
