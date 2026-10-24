function result=m2_test_foc_moves(mode)
arguments
 mode (1,:) char {mustBeMember(mode,{'paired','live'})}
end
root=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(root,'simulink模型'));folder=fullfile(root,'docs/reports/m2_foc_fixed_point');
if strcmp(mode,'live')
 result=run_fixed_live(root);result.fixed_implementation=true;fid=fopen(fullfile(folder,'live_acceptance.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);disp('M2_FIXED_LIVE_PASS');return
end
planFile=fullfile(folder,'paired_command_plan.json');if isfile(planFile),plan=jsondecode(fileread(planFile));else,plan=freeze_float_plan(root);fid=fopen(planFile,'w');fprintf(fid,'%s',jsonencode(plan,PrettyPrint=true));fclose(fid);end
[a,ma]=m2_run_shared_case('repeat',0,plan);[b,mb]=m2_run_shared_case('repeat',1,plan);save(fullfile(root,'.runtime/m2_20261024/paired_moves.mat'),'a','b','ma','mb','plan','-v7.3');rows=cell(0,5);
for n={'id','iq','x_mm','v_mmps'},x=a.logsout.get(n{1}).Values;y=b.logsout.get(n{1}).Values;assert(isequal(x.Time,y.Time));delta=double(x.Data(:))-double(y.Data(:));lim=.005;rmsLim=.001;if strcmp(n{1},'v_mmps'),lim=.1;rmsLim=.02;end;err=max(abs(delta));rmse=sqrt(mean(delta.^2));rows(end+1,:)={n{1},err,rmse,lim,err<=lim&&rmse<=rmsLim};end
readyTimes=cell(1,2);for j=1:2,if j==1,out=a;else,out=b;end;v=out.logsout.get('accepted_count').Values;assert(max(v.Data)==4);v=out.logsout.get('rejected_count').Values;assert(max(v.Data)==1);rd=out.logsout.get('move_ready').Values;readyTimes{j}=rd.Time([false;diff(rd.Data)>0]);for t=plan.times(3:5)',k=find(rd.Time<t,1,'last');margin=rd.Time>=t-.02&rd.Time<t;assert(rd.Data(k)==1&&all(rd.Data(margin)==1),'M2:SHARED_COMMAND_MARGIN','预定提交前双方必须Ready，不移动事件追求通过。');end;end
for n={'target_accepted_mm','segment_start_s','accepted_count','rejected_count','command_status'},x=a.logsout.get(n{1}).Values;y=b.logsout.get(n{1}).Values;assert(isequal(x.Time,y.Time)&&isequal(x.Data,y.Data));end
writetable(cell2table(rows,'VariableNames',{'signal','max_abs','rmse','max_budget','pass'}),fullfile(folder,'paired_move_metrics.csv'));result=struct('pass',all(cell2mat(rows(:,5))),'same_command_times_s',plan.times(2:5)','accepted_targets_mm',[.1 .2 -.1 -.09],'busy_rejection_count',1,'ready_times_float_s',readyTimes{1},'ready_times_fixed_s',readyTimes{2},'same_command_events',true,'automatic_sequence_is_live_evidence',false);fid=fopen(fullfile(folder,'paired_moves_acceptance.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);assert(result.pass,'M2:REPEAT_BUDGET','连续点位闭环差超预算。');disp('M2_PAIRED_MOVES_PASS');
end
function plan=freeze_float_plan(root)
% Only the original float pilot chooses the schedule, before fixed comparison.
[modelFolder,modelCleanup]=m2_test_model_files;m='PMLSM_PI_FOC_Float_Baseline';evalin('base','init_PMLSM_PI_FOC_Float_Baseline;Host_Target_mm=.1;Host_Traj_Vmax=5;Host_Traj_Amax=50;M1A_StopTime_s=20;');load_system(fullfile(modelFolder,[m '.slx']));set_param(m,'EnablePacing','on','PacingRate','.5');set_param(m,'SimulationCommand','start');clock=tic;while get_param(m,'SimulationTime')<.12&&toc(clock)<120,drawnow;pause(.01);end
set_param([m '/Simple_Host/Host_Target_mm'],'Value','10');set_param([m '/Simple_Host/Host_Move_Request'],'Value','1');bit=1;
for target=[.2 -.1 -.09]
 readySince=NaN;while toc(clock)<600,drawnow;pause(.005);assert(strcmp(get_param(m,'SimulationStatus'),'running'));r=get_param([m '/Simple_Host/Move_Ready_Live_State'],'RuntimeObject');t=get_param(m,'SimulationTime');if double(r.Dwork(1).Data)==1,if isnan(readySince),readySince=t;end;if t-readySince>=.03,break;end;else,readySince=NaN;end;end
 assert(~isnan(readySince)&&t-readySince>=.03,'M2:PILOT_READY','浮点预演没有取得Ready余量。');set_param([m '/Simple_Host/Host_Target_mm'],'Value',num2str(target,17));bit=1-bit;set_param([m '/Simple_Host/Host_Move_Request'],'Value',num2str(bit));wait_ready(m,0,clock);wait_ready(m,1,clock);
end
advance(m,.08,clock);set_param(m,'SimulationCommand','stop');out=evalin('base','out');save(fullfile(root,'.runtime/m2_20261024/paired_float_pilot.mat'),'out','-v7.3');ta=out.logsout.get('target_accepted_mm').Values;times=zeros(3,1);targets=[.2 -.1 -.09];for k=1:3,j=find(abs(ta.Data-targets(k))<1e-10,1);assert(~isempty(j));times(k)=round(ta.Time(j)/1e-4)*1e-4;end
plan=struct('times',[0;.12;times;ceil(times(end)+1)],'targets',[.1;10;.2;-.1;-.09;-.09],'requests',[0;1;0;1;0;0],'pilot','original float; continuously Ready for30ms before API send; actual acceptance times frozen before both replays','comparison_adjusted',false);close_system(m,0);disp('M2_PAIRED_PLAN_FROZEN');
end
function result=run_fixed_live(root)
[modelFolder,modelCleanup]=m2_test_model_files;m='PMLSM_PI_FOC_Float_Baseline';evalin('base','init_PMLSM_PI_FOC_Float_Baseline;Host_Target_mm=0.1;M1A_StopTime_s=20;Host_Traj_Vmax=5;Host_Traj_Amax=50;');
assignin('base','FOC_Impl_Select',1);
m2_bind_test_models(modelFolder);
set_param(m,'EnablePacing','on','PacingRate','0.5');set_param(m,'SimulationCommand','start');startWall=tic;events=struct([]);bit=0;
% Busy request is consumed through the same physical Host submit inlet.
while get_param(m,'SimulationTime')<.12 && toc(startWall)<120,drawnow;pause(.01);end
set_param([m '/Simple_Host/Host_Target_mm'],'Value','10');bit=1;set_param([m '/Simple_Host/Host_Move_Request'],'Value','1');
targets=[.2 -.1];
for k=1:numel(targets)
 wait_ready(m,1,startWall);assert(strcmp(get_param(m,'SimulationStatus'),'running'));
 set_param([m '/Simple_Host/Host_Target_mm'],'Value',num2str(targets(k),17));bit=1-bit;t0=get_param(m,'SimulationTime');set_param([m '/Simple_Host/Host_Move_Request'],'Value',num2str(bit));
 event=struct('target_mm',targets(k),'submit_sim_s',t0,'running',true,'request_bit',bit);if k==1,events=event;else,events(k)=event;end
 wait_ready(m,0,startWall);wait_ready(m,1,startWall);
 fprintf('M2_LIVE_TARGET_DONE %.6g at %.9g\n',targets(k),get_param(m,'SimulationTime'));
end
% Draft edit alone does not submit. Repeat is ACK; nonfinite target is rejected.
set_param([m '/Simple_Host/Host_Target_mm'],'Value','99');advance(m,.02,startWall);
wait_ready(m,1,startWall);set_param([m '/Simple_Host/Host_Target_mm'],'Value',num2str(targets(end),17));bit=1-bit;repeatTime=get_param(m,'SimulationTime');set_param([m '/Simple_Host/Host_Move_Request'],'Value',num2str(bit));advance(m,.02,startWall);
set_param([m '/Simple_Host/Host_Target_mm'],'Value','NaN');bit=1-bit;set_param([m '/Simple_Host/Host_Move_Request'],'Value',num2str(bit));advance(m,.02,startWall);
set_param(m,'SimulationCommand','pause');while ~strcmp(get_param(m,'SimulationStatus'),'paused')&&toc(startWall)<600,drawnow;pause(.01);end;assert(strcmp(get_param(m,'SimulationStatus'),'paused'));pausedTime=get_param(m,'SimulationTime');pause(.05);assert(get_param(m,'SimulationTime')==pausedTime);set_param(m,'SimulationCommand','continue');advance(m,.02,startWall);
finishTime=get_param(m,'SimulationTime');assert(finishTime>events(end).submit_sim_s);set_param(m,'SimulationCommand','stop');
out=evalin('base','out');folder=fullfile(root,'.runtime','m2_20261024');name='fixed_live';save(fullfile(folder,[name '.mat']),'out','events','finishTime','-v7.3');
accepted=out.logsout.get('accepted_count').Values;expected=numel(targets)+1;assert(max(accepted.Data)==expected);rejected=out.logsout.get('rejected_count').Values;status=out.logsout.get('command_status').Values;rd=out.logsout.get('move_ready').Values;jr=find(status.Time>=repeatTime & (status.Data==5|status.Data==3),1);assert(~isempty(jr));repeatStatus=status.Data(jr);assert((repeatStatus==5&&rd.Data(jr)==1)||(repeatStatus==3&&rd.Data(jr)==0));assert(max(rejected.Data)==2+double(repeatStatus==3));assert(any(status.Data==4));ta=out.logsout.get('target_accepted_mm').Values;assert(~any(ta.Data==10)&&~any(ta.Data==99));
latencies=zeros(size(events));acceptedTimes=[];
for k=1:numel(events)
 v=out.logsout.get('target_accepted_mm').Values;j=find(v.Time>=events(k).submit_sim_s & abs(v.Data-targets(k))<1e-10,1);assert(~isempty(j));latencies(k)=v.Time(j)-events(k).submit_sim_s;acceptedTimes(k)=v.Time(j);assert(latencies(k)>=-1e-9&&latencies(k)<=1e-4+1e-9);events(k).accepted_sim_s=v.Time(j);
 ss=out.logsout.get('segment_start_mm').Values;st=out.logsout.get('segment_start_s').Values;rd=out.logsout.get('move_ready').Values;dn=out.logsout.get('trajectory_done').Values;pos=out.logsout.get('x_mm').Values;
 events(k).segment_start_mm=ss.Data(j);events(k).segment_start_s=st.Data(j);jdone=find(dn.Time>=v.Time(j)&dn.Data==1,1);jready=find(rd.Time>=v.Time(j)&rd.Data==1,1);assert(~isempty(jdone)&&~isempty(jready));events(k).trajectory_done_s=dn.Time(jdone);events(k).ready_s=rd.Time(jready);events(k).error_at_ready_mm=abs(interp1(pos.Time,pos.Data,rd.Time(jready))-targets(k));assert(events(k).error_at_ready_mm<=.02+1e-9);
end
for n={'x_mm','x_ref_mm','segment_start_mm','segment_start_s','target_accepted_mm','move_ready'},v=out.logsout.get(n{1}).Values;assert(all(isfinite(v.Data(:))));end
% Formula check uses exactly logged segment time, not global simulation time.
xr=out.logsout.get('x_ref_mm').Values;ss=out.logsout.get('segment_start_mm').Values;tt=out.logsout.get('segment_start_s').Values;ta=out.logsout.get('target_accepted_mm').Values;
assert(isequal(xr.Time,ss.Time)&&isequal(xr.Time,tt.Time)&&isequal(xr.Time,ta.Time));maximum=0;
for j=1:10:numel(xr.Time),expected=ss.Data(j)+pmlsm_scurve_profile(xr.Time(j)-tt.Data(j),ta.Data(j)-ss.Data(j),5,50,1000,.1);maximum=max(maximum,abs(xr.Data(j)-expected));end
assert(maximum<1e-10);
result=struct('pass',true,'single_start_count',1,'process',matlabProcessID,'events',events,'accepted_times',acceptedTimes,'max_latency_s',max(latencies),'max_formula_error_mm',maximum,'finish_sim_s',finishTime,'UI_mouse_clicked',false,'draft_edit_only_ignored',true,'busy_or_alignment_consumed',true,'repeat_ack',repeatStatus==5,'repeat_at_event_status',repeatStatus,'repeat_at_event_ready',rd.Data(jr),'NaN_rejected',true,'pause_continue',true,'ready_observer','saved Host display-only DataStore at100us');
csvName='live_commands.csv';writetable(struct2table(events),fullfile(root,'docs/reports/m2_foc_fixed_point',csvName));
set_param([m '/Simple_Host/Host_Target_mm'],'Value','Host_Target_mm');set_param([m '/Simple_Host/Host_Move_Request'],'Value','Host_Move_Request');set_param(m,'EnablePacing','off');
end
function advance(m,delta,startWall)
t=get_param(m,'SimulationTime');while get_param(m,'SimulationTime')<t+delta&&toc(startWall)<600,drawnow;pause(.01);assert(strcmp(get_param(m,'SimulationStatus'),'running'));end
end
function wait_ready(m,wanted,startWall)
path=[m '/Simple_Host/Move_Ready_Live_State'];
while toc(startWall)<600
 drawnow;pause(.01);assert(strcmp(get_param(m,'SimulationStatus'),'running'),'M2:LIVE_STOPPED','等待Ready时仿真提前停止。');
 r=get_param(path,'RuntimeObject');value=double(r.Dwork(1).Data);if value==wanted,return;end
end
error('M2:LIVE_TIMEOUT','Ready等待超过有限600s，未宣称通过。');
end
