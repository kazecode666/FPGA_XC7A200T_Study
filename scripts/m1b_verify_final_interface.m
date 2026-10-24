function result=m1b_verify_final_interface
% 独立进程：保存模型的正常Run、默认数值、局部标签和操作/日志验收。
root=fileparts(fileparts(mfilename('fullpath')));folder=fullfile(root,'docs/reports/m1b_repeat_moves_alignment');m='PMLSM_PI_FOC_Float_Baseline';addpath(fullfile(root,'simulink模型'));evalin('base','init_PMLSM_PI_FOC_Float_Baseline;Host_Target_mm=1;Host_Traj_Vmax=5;Host_Traj_Amax=50;M1A_StopTime_s=1.2;');load_system(fullfile(root,'simulink模型',[m '.slx']));
out=sim(m);assignin('base','out',out);names=getElementNames(out.logsout);assert(numel(names)==numel(unique(names)));
old=load(fullfile(root,'.runtime/m1b_20261024/baseline/default_1mm_1p2s.mat'),'out');legacy=getElementNames(old.out.logsout);assert(all(ismember(legacy,names)));
compareNames={'id','iq','x_mm','v_mmps','vd_cmd','vq_cmd','duty_u_cmd','duty_v_cmd','duty_w_cmd','x_d','x_q','x_ref_mm'};rows=cell(12,3);
for k=1:12,a=old.out.logsout.get(compareNames{k}).Values;b=out.logsout.get(compareNames{k}).Values;[~,i,j]=intersect(round(a.Time*1e9),round(b.Time*1e9));assert(numel(j)==numel(b.Time));e=max(abs(double(a.Data(i))-double(b.Data(j))));assert(e<1e-12);rows(k,:)={compareNames{k},e,true};end
writetable(cell2table(rows,'VariableNames',{'signal','max_abs_error','pass'}),fullfile(folder,'default_equivalence.csv'));
% Native saved logging metadata plus observed timestamp cadence.
blocks=find_system(m,'LookUnderMasks','all','FollowLinks','off','Type','Block');rows=cell(0,8);for k=1:numel(blocks),p=get_param(blocks{k},'PortHandles');for j=1:numel(p.Outport),if strcmp(get_param(p.Outport(j),'DataLogging'),'on'),n=get_param(p.Outport(j),'DataLoggingName');s=out.logsout.get(n).Values;rows(end+1,:)={n,strrep(blocks{k},newline,' '),j,class(s.Data),get_param(p.Outport(j),'DataLoggingDecimateData'),get_param(p.Outport(j),'DataLoggingDecimation'),median(diff(s.Time)),numel(s.Time)};end;end;end %#ok<AGROW>
writetable(cell2table(rows,'VariableNames',{'name','source','port','type','decimate','decimation','observed_period_s','samples'}),fullfile(folder,'signals.csv'));
g=find_system(m,'LookUnderMasks','all','FollowLinks','off','BlockType','Goto');for k=1:numel(g),assert(strcmp(get_param(g{k},'TagVisibility'),'local'));end
f=find_system(m,'LookUnderMasks','all','FollowLinks','off','BlockType','From');for k=1:numel(f),a=find_system(get_param(f{k},'Parent'),'SearchDepth',1,'BlockType','Goto','GotoTag',get_param(f{k},'GotoTag'));assert(isscalar(a));end
assert(isempty(find_system(m,'LookUnderMasks','all','FollowLinks','off','BlockType','GotoTagVisibility')));
dangling={};eventPorts=0;for k=1:numel(blocks),p=get_param(blocks{k},'PortHandles');active=[p.Inport p.Outport];for field={'Enable','Trigger','Ifaction','Reset'},if isfield(p,field{1}),active=[active p.(field{1})];eventPorts=eventPorts+numel(p.(field{1}));end;end;for q=active,if get_param(q,'Line')==-1,dangling{end+1}=blocks{k};end;end;end %#ok<AGROW>
assert(isempty(dangling),'M1B:DANGLING','Active input/output port is unconnected: %s',strjoin(dangling,' | '));
bind=get_param([m '/S_Curve_Reference_Actual'],'Binding');assert(numel(bind)==2&&bind{1}.OutputPortIndex==1&&bind{2}.OutputPortIndex==6);assert(strcmp(char(bind{1}.BlockPath.getBlock(1)),[m '/Simple_Host'])&&strcmp(char(bind{2}.BlockPath.getBlock(1)),[m '/PMLSM_Plant_Model']));
for n={'Host_Move_Request','Alignment_Enable','Init_Start','Init_Reset'},if strcmp(n{1},'Host_Move_Request'),widget=[m '/Send_Move_Toggle'];target=[m '/Simple_Host/' n{1}];else,widget=[m '/Set_' n{1}];target=[m '/' n{1}];end;b=get_param(widget,'Binding');assert(strcmp(char(b.BlockPath.getBlock(1)),target)&&strcmp(b.ParamName,'Value'));end
% Default preview starts at zero; stopped segment preview uses actual accepted data.
a=preview_PMLSM_reference;b=preview_PMLSM_reference('segment');assert(a.segment_start_mm==0&&a.target_accepted_mm==1&&b.target_accepted_mm==1);close(gcf);close(gcf);
% RED before review fix: reinit changes V5/A50 to local V10/A100, old segment must not change.
evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');history=preview_PMLSM_reference('segment');close(gcf);assert(isequal(b.time,history.time)&&isequal(b.x_ref_mm,history.x_ref_mm)&&isequal(b.planned_speed_mmps,history.planned_speed_mmps),'M1B:HISTORY_CONFIG_CHANGED','Saved segment changed after reinit.');assert(isequal(history.configuration,[5 50 1000 .1 1e-4]));
xr=out.logsout.get('x_ref_mm').Values;[~,ii,jj]=intersect(round(history.time*1e9),round(xr.Time*1e9));assert(max(abs(history.x_ref_mm(ii)-xr.Data(jj)))<1e-12);
evalin('base','Host_Traj_Vmax=5;Host_Traj_Amax=50;');
% Explicit real PWM interruption of an unfinished point segment, no reset of mechanics.
evalin('base','Host_Target_mm=1;M1A_StopTime_s=.25;Host_Replay_EN=1;M1A_PWM_ts=timeseries([1;0],[0;.12]);');interrupted=sim(m);v=interrupted.logsout.get('move_interrupted').Values;assert(v.Data(end)==1);v=interrupted.logsout.get('move_ready').Values;assert(v.Data(end)==0);v=interrupted.logsout.get('vq_applied').Values;assert(all(v.Data(v.Time>=.12)==0));
% Runtime preview reads the display-only Host snapshot including its actual configuration.
evalin('base','init_PMLSM_PI_FOC_Float_Baseline;Host_Target_mm=.1;Host_Traj_Vmax=5;Host_Traj_Amax=50;M1A_StopTime_s=1;');set_param(m,'EnablePacing','on','PacingRate','.25','SimulationCommand','start');wall=tic;
while get_param(m,'SimulationTime')<.12&&toc(wall)<90,drawnow;pause(.01);end
assert(strcmp(get_param(m,'SimulationStatus'),'running'));livePreview=preview_PMLSM_reference;close(gcf);assert(isequal(livePreview.configuration,[5 50 1000 .1 1e-4]));set_param(m,'SimulationCommand','stop');set_param(m,'EnablePacing','off');
result=struct('pass',true,'version',version,'process',matlabProcessID,'unique_saved_names',numel(names),'legacy_names_retained',numel(legacy),'same_parent_local_goto',numel(g),'same_parent_from',numel(f),'unconnected_active_ports',numel(dangling),'connected_event_control_ports',eventPorts,'default_max_error',0,'preview_default_and_saved_segment',true,'saved_preview_stable_after_reinit',true,'runtime_preview_actual_configuration',true,'PWM_point_interrupt',true,'UI_mouse_clicked',false);
fid=fopen(fullfile(folder,'interface_acceptance.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);save(fullfile(root,'.runtime/m1b_20261024/D_default.mat'),'out','interrupted','-v7.3');disp('M1B_FINAL_INTERFACE_PASS');
end
