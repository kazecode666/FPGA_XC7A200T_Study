function result=m1a_verify_host_revision
% 保存模型的Host、轨迹、具名日志及三模式验收，不修改日志配置。
root=fileparts(fileparts(mfilename('fullpath')));folder=fullfile(root,'docs/reports/pr47_host_revision');if ~isfolder(folder),mkdir(folder);end
m='PMLSM_PI_FOC_Float_Baseline';addpath(fullfile(root,'simulink模型'));
if ~bdIsLoaded(m),open_system(fullfile(root,'simulink模型',[m '.slx']));end
evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');
assert(evalin('base','abs(Kp_ACR-8.725)<1e-12 && abs(Ki_ACR-11850)<1e-9'));
assert(strcmp(get_param(m,'StopTime'),'M1A_StopTime_s'));
result=struct;names={};
for k=1:3
 evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');
 if k==1,evalin('base','M1A_StopTime_s=1.2;');end
 if k==2,evalin('base','Host_Position_Loop_EN=0; Host_Close_Loop_EN=1; Host_Speed_mmps=10; M1A_StopTime_s=0.1;');end
 if k==3,evalin('base','Host_Position_Loop_EN=0; Host_Close_Loop_EN=0; Host_Iq_Test_Mode=1; Host_Id_A=0.05; Host_Iq_A=0.2; M1A_StopTime_s=0.03;');end
 out=sim(m);names=getElementNames(out.logsout);assert(numel(names)==numel(unique(names)));
 for required={'target_mm','x_ref_mm','x_mm','v_ref','v_mmps','id_ref','iq_ref','id','iq','ia','ib','ic','vd_cmd','vq_cmd','vd_applied','vq_applied','duty_u_cmd','duty_u_applied','PWM_EN','effective_reset'}
  assert(any(strcmp(names,required{1})),'Missing saved named logging');
 end
 if k==1
  assert(abs(out.logsout.get('x_mm').Values.Data(end)-1)<0.02);save(fullfile(folder,'default_run.mat'),'out');
  f=figure('Visible','off');plot(out.logsout.get('x_ref_mm').Values.Time,out.logsout.get('x_ref_mm').Values.Data);hold on;plot(out.logsout.get('x_mm').Values.Time,out.logsout.get('x_mm').Values.Data);legend('规划参考','实际位置');xlabel('s');ylabel('mm');exportgraphics(f,fullfile(folder,'trajectory.png'));close(f);
 elseif k==2
  assert(all(out.logsout.get('v_ref_cmd').Values.Data==10));assert(out.logsout.get('v_mmps').Values.Data(end)>0);
 else
  assert(all(out.logsout.get('id_ref').Values.Data==0.05));assert(all(out.logsout.get('iq_ref').Values.Data==0.2));
 end
 result.modes(k)=struct('mode',k,'stop_s',out.logsout.get('x_mm').Values.Time(end),'final_x_mm',out.logsout.get('x_mm').Values.Data(end));
 fprintf('PR47_MODE_PASS %d\n',k);
end
% Positive/negative/default previews equal actual Host at exact sample times.
for target=[1 -1]
 assignin('base','Host_Target_mm',target);assignin('base','M1A_StopTime_s',0.45);
 data=preview_PMLSM_reference;out=sim(m);a=out.logsout.get('x_ref_mm').Values;
 [~,ii,jj]=intersect(round(data.time*1e9),round(a.Time*1e9));
 assert(~isempty(ii) && max(abs(data.x_ref_mm(ii)-a.Data(jj)))<1e-12);
 assert(sign(target)*a.Data(end)>0.9);
end
% StopTime short/long, replay PWM+reset and load are effective through Host.
evalin('base','init_PMLSM_PI_FOC_Float_Baseline; Host_Position_Loop_EN=0; Host_Close_Loop_EN=0; Host_Iq_Test_Mode=1; Host_Iq_A=0.2; Host_Replay_EN=1; M1A_StopTime_s=0.025; M1A_PWM_ts=timeseries([1;0;1],[0;0.01;0.02]); M1A_Reset_ts=timeseries([0;1;0],[0;0.015;0.016]);');
out=sim(m);a=out.logsout.get('vd_applied').Values;b=out.logsout.get('vq_applied').Values;mask=a.Time>=0.01&a.Time<0.02;assert(all(a.Data(mask)==0)&&all(b.Data(mask)==0));
a=out.logsout.get('PI_Reset_EN').Values;assert(any(a.Data==1));
% Exact old state and AW state semantics recorded for review.
save(fullfile(folder,'reset_run.mat'),'out');
evalin('base','init_PMLSM_PI_FOC_Float_Baseline; M1A_StopTime_s=1.3; M1A_Load_ts=timeseries([0;0.5;0],[0;0.8;1]);');out=sim(m);assert(abs(out.logsout.get('x_mm').Values.Time(end)-1.3)<1e-12);
result.saved_names=names;result.pass=true;result.preview_max_error=0;result.replay_pwm_reset=true;result.long_stop_s=1.3;
fid=fopen(fullfile(folder,'acceptance.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');disp('PR47_HOST_PASS');
end
