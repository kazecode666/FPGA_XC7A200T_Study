function data=preview_PMLSM_reference(mode)
% 默认预览首段；运行时读当前锁存段；segment读取停止后out的最后一段。
arguments
 mode (1,:) char {mustBeMember(mode,{'auto','segment'})}='auto'
end
m='PMLSM_PI_FOC_Float_Baseline';start=0;t0=0;target=0;source='默认首段（草稿目标）';savedConfiguration=[];
if bdIsLoaded(m)&&any(strcmp(get_param(m,'SimulationStatus'),{'running','paused'}))
 r=get_param([m '/Simple_Host/Move_Info_Live_State'],'RuntimeObject');values=double(r.Dwork(1).Data);start=values(1);target=values(2);t0=values(3);savedConfiguration=reshape(values(4:8),1,[]);source='本次运行已锁存段';
elseif strcmp(mode,'segment')
 assert(evalin('base','exist(''out'',''var'')==1'),'M1B:PREVIEW_NO_LOG','需要本模型仿真结果out；默认首段请不带参数调用。');
 out=evalin('base','out');assert(strcmp(out.SimulationMetadata.ModelInfo.ModelName,m),'M1B:PREVIEW_WRONG_MODEL','out来自其他模型。');
 start=out.logsout.get('segment_start_mm').Values.Data(end);target=out.logsout.get('target_accepted_mm').Values.Data(end);t0=out.logsout.get('segment_start_s').Values.Data(end);source='已保存的最后锁存段';
 names=getElementNames(out.logsout);assert(any(strcmp(names,'trajectory_config')),'M1B:PREVIEW_CONFIG_MISSING','此旧out未记录轨迹配置，不能用当前参数重建历史段；请保留旧数据并用新模型运行。');
 configuration=out.logsout.get('trajectory_config').Values;index=find(configuration.Time<=t0+1e-9,1,'last');assert(~isempty(index));savedConfiguration=reshape(getdatasamples(configuration,index),1,[]);assert(numel(savedConfiguration)==5&&all(isfinite(savedConfiguration))&&all(savedConfiguration>0));
else
 t0=evalin('base','Host_Start_s');target=evalin('base','Host_Target_mm');
end
if isempty(savedConfiguration)
 names={'Host_Traj_Vmax','Host_Traj_Amax','Host_Traj_Jmax','Host_Speed_Ramp_s','Ts_ACR'};v=zeros(1,5);for k=1:5,v(k)=evalin('base',names{k});end
else
 v=savedConfiguration;
end
[~,~,duration]=pmlsm_scurve_profile(0,target-start,v(1),v(2),v(3),v(4));
t=(t0:v(5):t0+max(duration,v(5))+v(5))';x=zeros(size(t));speed=x;
for k=1:numel(t),[delta,speed(k)]=pmlsm_scurve_profile(t(k)-t0,target-start,v(1),v(2),v(3),v(4));x(k)=start+delta;end
data=struct('time',t,'x_ref_mm',x,'planned_speed_mmps',speed,'segment_start_mm',start,'target_accepted_mm',target,'segment_start_s',t0,'source',source,'configuration',v);
figure('Name',['PMLSM参考轨迹 - ' source]);tiledlayout(2,1);nexttile;plot(t,x,'LineWidth',1.4);yline(target,'--','目标');ylabel('位置 / mm');grid on;title(source);nexttile;plot(t,speed,'LineWidth',1.4);xlabel('仿真时间 / s');ylabel('规划速度 / (mm/s)');grid on;
end
