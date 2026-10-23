function data=preview_PMLSM_reference
% 只预览当前Base参数的规划轨迹，不运行电机或重新初始化。
names={'Host_Start_s','Host_Target_mm','Host_Traj_Vmax','Host_Traj_Amax','Host_Traj_Jmax','Host_Speed_Ramp_s','M1A_StopTime_s','Ts_ACR'};
v=zeros(1,numel(names));for k=1:numel(names),v(k)=evalin('base',names{k});end
[~,~,duration]=pmlsm_scurve_profile(0,v(2),v(3),v(4),v(5),v(6));
t=(0:v(8):max(v(7),v(1)+duration))';x=zeros(size(t));speed=x;
for k=1:numel(t),[x(k),speed(k)]=pmlsm_scurve_profile(t(k)-v(1),v(2),v(3),v(4),v(5),v(6));end
data=struct('time',t,'x_ref_mm',x,'planned_speed_mmps',speed);
figure('Name','PMLSM参考轨迹');plot(t,x,'LineWidth',1.4);yline(v(2),'--','目标位置');xlabel('时间 / s');ylabel('规划位置 / mm');grid on;
end
