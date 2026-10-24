function [out,metadata]=m2_run_shared_case(scene,implementation)
% 同一主模型、同一场景；仅内存观测，不保存模型。
root=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(root,'simulink模型'));m='PMLSM_PI_FOC_Float_Baseline';
evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');open_system(fullfile(root,'simulink模型',[m '.slx']));
in=Simulink.SimulationInput(m);stop=1.2;target=1;speed=0;pos=1;closed=1;test=0;iq=0;id=0;align=0;start=0;auto=1;dead=1e-6;
if strcmp(scene,'daily'),stop=5;target=10;else,in=in.setVariable('Host_Traj_Vmax',5).setVariable('Host_Traj_Amax',50);end
if startsWith(scene,'current'),stop=.05;pos=0;closed=0;test=1;iq=.2;if endsWith(scene,'neg'),iq=-iq;end;end
if startsWith(scene,'speed'),stop=.3;pos=0;speed=10;if endsWith(scene,'neg'),speed=-speed;end;end
if strcmp(scene,'position_neg'),target=-1;end
if strcmp(scene,'ideal'),dead=0;end
if strcmp(scene,'load'),stop=1.3;in=in.setVariable('M1A_Load_ts',setinterpmethod(timeseries([0;.5;0],[0;.8;1]),'zoh'));end
if strcmp(scene,'reset'),stop=.05;pos=0;closed=0;test=1;iq=.2;in=in.setVariable('Host_Replay_EN',1).setVariable('M1A_PWM_ts',setinterpmethod(timeseries([1;0;1],[0;.012;.018]),'zoh')).setVariable('M1A_Reset_ts',setinterpmethod(timeseries([0;1;0],[0;.0179;.0181]),'zoh'));end
if strcmp(scene,'alignment'),stop=4.5;align=1;start=1;auto=0;end
in=in.setVariable('FOC_Impl_Select',implementation).setVariable('Host_Target_mm',target).setVariable('Host_Speed_mmps',speed).setVariable('Host_Position_Loop_EN',pos).setVariable('Host_Close_Loop_EN',closed).setVariable('Host_Iq_Test_Mode',test).setVariable('Host_Iq_A',iq).setVariable('Host_Id_A',id).setVariable('Alignment_Enable',align).setVariable('Init_Start',start).setVariable('Host_AutoStart_EN',auto).setVariable('M1A_StopTime_s',stop).setVariable('PMLSM_deadtime_s',dead).setVariable('PMLSM_deadtime_ratio',dead/1e-4);
% Exactly the source FOC's actual selected input ports, not test-command substitutes.
blocks=find_system(m,'LookUnderMasks','all','FollowLinks','off','Type','Block');for k=1:numel(blocks),p=get_param(blocks{k},'PortHandles');for q=p.Outport,if strcmp(get_param(q,'DataLogging'),'on'),set_param(q,'DataLogging','off');end;end;end
f=Simulink.ID.getFullName([m ':546']);b=find_system(f,'SearchDepth',1,'BlockType','Inport');for k=1:numel(b),logport(b{k},1,['in_' get_param(b{k},'Name')],1);end
sid=[191 191 191 191 191 505 505 505 698 698 586 613 727 728 661 662 740 740];port=[1 2 6 7 8 1 2 3 1 2 1 1 1 1 1 1 1 2];names={'id','iq','x_mm','v_mmps','theta_true','duty_u','duty_v','duty_w','vd','vq','x_d','x_q','du_d_z','du_q_z','candidate_T1','candidate_T2','speed_tick','position_tick'};
for k=1:numel(sid),d=1;if sid(k)==191,d=100;end;logport(Simulink.ID.getFullName(sprintf('%s:%d',m,sid(k))),port(k),names{k},d);end
out=sim(in);metadata=struct('scene',scene,'implementation',implementation,'stop_s',stop,'version',version,'process',matlabProcessID,'sample_s',1e-4,'Udc',48,'source_saved',false);close_system(m,0);
end
function logport(b,i,name,d)
p=get_param(b,'PortHandles');set_param(p.Outport(i),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',name,'DataLoggingDecimateData','on','DataLoggingDecimation',num2str(d));
end
