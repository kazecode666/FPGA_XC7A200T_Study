function cfg=step7d_scenarios(name)
% Frozen requests/windows from the Step7D taskbook; not measured results.
valid={'speed_ideal','speed_deadtime','position_ideal','position_deadtime','position_negative_deadtime','stop_restart_inhibit','convergence_prefix','fresh_start'};
if ~any(strcmp(name,valid)), error('Step7D:UnknownScenario','Unknown scenario: %s',name); end
cfg=struct('name',name,'purpose','performance','backend',1,'commTs',1e-6,'stopTime',1.2,'deadtime_s',0);
cfg.host=struct('Host_Enable_Schedule',[0 1 0 1],'Host_Start_s',.05,'Host_Target_mm',1, ...
 'Host_Traj_Vmax',5,'Host_Traj_Amax',50,'Host_Traj_Jmax',1000,'Host_Speed_Ramp_s',.1, ...
 'Host_Iq_Test_Mode',0,'Host_Id_A',0,'Host_Iq_A',0,'Host_Speed_mmps',0,'Host_Load_N',0,'Host_PI_Reset_EN',0);
cfg.signals=struct('speed',[0 0;.05 0;.15 5;.30 5;.40 0;.50 0;.60 -5;.75 -5;.85 0;1.2 0], ...
 'load',[0 0;.20 .5;.25 0;.90 .5;1.05 0;1.2 0], ...
 'pwm',[0 1;1.2 1],'reset',[0 0;1.2 0], ...
 'speedInterpolation','linear','loadInterpolation','zoh','enableInterpolation','zoh');
cfg.windows=struct('speed',[.27 .30;.44 .49;.65 .74;1 1.04;1.12 1.2],'position',zeros(0,2));
cfg.thresholds=struct('speedMAE',.5,'speedRMSE',.5,'speedMax',2,'minimumSpeedSamples',20, ...
 'positionMax',.05,'positionSpeedMax',1,'positionOvershoot',.1, ...
 'iqRefMax',1,'iqMax',1.5,'idMax',.1,'iqRMSE',.05,'initialExclude_s',.002,'trajectoryEnd_s',.70);
if contains(name,'position') || strcmp(name,'convergence_prefix')
 cfg.host.Host_Enable_Schedule=[0 1 1 1]; cfg.signals.speed=[0 0;1.2 0];
 cfg.signals.load=[0 0;.80 .5;1.0 0;1.2 0];
 cfg.windows.speed=zeros(0,2); cfg.windows.position=[.72 .79;.92 .99;1.1 1.2];
end
if contains(name,'deadtime') || any(strcmp(name,{'stop_restart_inhibit','fresh_start'}))
 cfg.deadtime_s=1e-6; cfg.thresholds.idMax=.5; cfg.thresholds.iqRMSE=.1;
 cfg.thresholds.speedMAE=1.5; cfg.thresholds.speedRMSE=1.5;
end
if strcmp(name,'position_negative_deadtime')
 cfg.host.Host_Target_mm=-1; cfg.signals.load=[0 0;1.2 0]; cfg.windows.position=[1.1 1.2];
elseif strcmp(name,'stop_restart_inhibit')
 cfg.stopTime=.4; cfg.signals.speed=[0 0;.05 0;.15 5;.4 5]; cfg.signals.load=[0 0;.4 0];
 cfg.signals.pwm=[0 1;.25 0;.30 1;.4 1]; cfg.signals.reset=[0 0;.35 1;.352 0;.4 0];
 cfg.windows.speed=zeros(0,2);
elseif strcmp(name,'convergence_prefix')
 cfg.stopTime=.2; cfg.purpose='convergence'; cfg.windows.position=zeros(0,2);
elseif strcmp(name,'fresh_start')
 cfg.stopTime=.02; cfg.purpose='fresh_start'; cfg.signals.speed=[0 0;.02 0]; cfg.signals.load=[0 0;.02 0]; cfg.windows.speed=zeros(0,2);
end
end
