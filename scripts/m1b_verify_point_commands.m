function result=m1b_verify_point_commands(stage)
% M1B独立验收；baseline只采集一次，all不会覆盖修订前证据。
arguments
 stage (1,:) char {mustBeMember(stage,{'baseline','regression','live','all'})}
end
root=fileparts(fileparts(mfilename('fullpath')));runtime=fullfile(root,'.runtime','m1b_20261024');folder=fullfile(root,'docs','reports','m1b_repeat_moves_alignment');
addpath(fullfile(root,'simulink模型'));m='PMLSM_PI_FOC_Float_Baseline';
if strcmp(stage,'baseline')
 output=fullfile(runtime,'baseline');assert(~isfile(fullfile(folder,'baseline_behavior.json')),'M1B:BASELINE_EXISTS','修订前参考不得覆盖。');if ~isfolder(output),mkdir(output);end
 evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');
 evalin('base','Host_Target_mm=1;M1A_StopTime_s=1.2;Host_Traj_Vmax=5;Host_Traj_Amax=50;');
 if ~bdIsLoaded(m),open_system(fullfile(root,'simulink模型',[m '.slx']));end
 if isfile(fullfile(output,'default_1mm_1p2s.mat')),saved=load(fullfile(output,'default_1mm_1p2s.mat'));out=saved.out;parameters=saved.parameters;else
 out=sim(m);parameters=evalin('base','struct(''Kp_ACR'',Kp_ACR,''Ki_ACR'',Ki_ACR,''Kaw_d'',Kaw_d,''Kp_ASR'',Kp_ASR,''Ki_ASR'',Ki_ASR,''Kaw_s'',Kaw_s,''Kp_pos'',Kp_pos,''deadtime'',PMLSM_deadtime_s,''Ts'',Ts_ACR)');
 save(fullfile(output,'default_1mm_1p2s.mat'),'out','parameters','-v7.3');end
 result=struct('version',version,'process',matlabProcessID,'default_x_mm',out.logsout.get('x_mm').Values.Data(end),'parameters',parameters);
 % Two live edits through the real bound Constant, one Run in each condition.
 cases=[0.4,10];events=struct([]);
 for k=1:2
  evalin('base','init_PMLSM_PI_FOC_Float_Baseline;Host_Target_mm=0.2;M1A_StopTime_s=1.4;Host_Traj_Vmax=5;Host_Traj_Amax=50;');
  if isfile(fullfile(output,sprintf('old_live_%d.mat',k))),saved=load(fullfile(output,sprintf('old_live_%d.mat',k)));out=saved.out;submitted=saved.submitted;else
  % Reduce only observation memory for sustained running, never plant step.
  decimate(m,100);set_param(m,'EnablePacing','on','PacingRate','0.25','SimulationCommand','start');
  started=tic;while get_param(m,'SimulationTime')<0.8&&toc(started)<90,drawnow;pause(0.02);end
  assert(strcmp(get_param(m,'SimulationStatus'),'running'),'M1B:LIVE_NOT_RUNNING','旧接口测试必须保持running。');
  submitted=get_param(m,'SimulationTime');bound=[m '/Simple_Host/Host_Target_mm'];set_param(bound,'Value',num2str(cases(k),17));
  while ~strcmp(get_param(m,'SimulationStatus'),'stopped')&&toc(started)<120,drawnow;pause(0.02);end
  assert(strcmp(get_param(m,'SimulationStatus'),'stopped'),'M1B:TIMEOUT','有限基线测试未结束。');
  out=evalin('base','out');save(fullfile(output,sprintf('old_live_%d.mat',k)),'out','submitted');
  end
  target=out.logsout.get('target_mm').Values;ref=out.logsout.get('x_ref_mm').Values;pos=out.logsout.get('x_mm').Values;
  j=find(target.Data>0.2+1e-9,1);assert(~isempty(j),'M1B:TARGET_NOT_RECEIVED','真实入口未收到新值');ri=find(ref.Time>0.7 & abs(ref.Data-0.2)>1e-8,1);time=ref.Time(ri);pii=find(pos.Time<time,1,'last');
  [~,~,duration]=pmlsm_scurve_profile(0,cases(k),5,50,1000,0.1);
  event=struct('requested_mm',cases(k),'call_time_s',submitted,'received_time_s',time,'prior_position_mm',pos.Data(pii),'prior_target_error_mm',abs(pos.Data(pii)-0.2),'reference_before_mm',ref.Data(max(1,ri-1)),'reference_after_mm',ref.Data(ri),'old_global_elapsed_s',time-.05,'new_target_duration_s',duration,'old_clock_past_new_duration',(time-.05)>duration,'correct_new_segment',abs(ref.Data(ri)-0.2)<1e-8);
  if k==1,events=event;else,events(k)=event;end
  set_param([m '/Simple_Host/Host_Target_mm'],'Value','Host_Target_mm');set_param(m,'EnablePacing','off');
 end
 result.old_live=events;result.complete_repeat_moves_supported=all([events.correct_new_segment]);
 fid=fopen(fullfile(folder,'baseline_behavior.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
 fprintf('M1B_BASELINE_CAPTURED repeat_supported=%d\n',result.complete_repeat_moves_supported);return
end
error('M1B:POINT_COMMANDS_PENDING','当前模型尚无已验收的提交/分段合同，保留此RED证据。');
end
function decimate(m,value)
b=find_system(m,'LookUnderMasks','all','FollowLinks','off','Type','Block');
for k=1:numel(b),p=get_param(b{k},'PortHandles');for q=p.Outport,if strcmp(get_param(q,'DataLogging'),'on'),set_param(q,'DataLoggingDecimateData','on','DataLoggingDecimation',num2str(value));end;end;end
end
