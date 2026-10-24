function out=m2_run_foc_sequence(model,inputs,fixed)
% 独立同拍FOC输入，无电机；观测改变不保存SLX。
assert(size(inputs,2)==9&&all(isfinite(inputs(:))),'M2:FINITE_INPUT','输入必须是9列有限物理量。');assert(all(inputs(:,9)>0),'M2:INVALID_BUS','母线必须为正。');
root=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(root,'simulink模型'));if ~bdIsLoaded(model),open_system(model);end
blocks=find_system(model,'LookUnderMasks','all','FollowLinks','off','Type','Block');for k=1:numel(blocks),p=get_param(blocks{k},'PortHandles');for q=p.Outport,set_param(q,'DataLogging','off');end;end
d=[model '/FOC_DUT'];log(d,1,'duty_u');log(d,2,'duty_v');log(d,3,'duty_w');log([d '/dq_voltage_limiter'],1,'vd');log([d '/dq_voltage_limiter'],2,'vq');log([d '/Id/x_d_z'],1,'x_d');log([d '/Iq/x_q_z'],1,'x_q');log([d '/dq_voltage_limiter/Unit Delay'],1,'du_d_z');log([d '/dq_voltage_limiter/Unit Delay1'],1,'du_q_z');log([d '/Park'],1,'park_d');log([d '/Park'],2,'park_q');log([d '/Id'],1,'vd_raw');log([d '/Iq'],1,'vq_raw');
% Every arithmetic branch of the adapted/fixed implementation must be defined.
for pth={'SVPWMG/T1T2','SVPWMG/XYZ'},b=find_system(d,'SearchDepth',2,'BlockType','SubSystem');idx=find(startsWith(erase(b,[d '/']),pth{1}));for k=idx',leaves=find_system(b{k},'LookUnderMasks','all','FollowLinks','off','Type','Block');for j=1:numel(leaves),typ=get_param(leaves{j},'BlockType');if any(strcmp(typ,{'Sum','Product','Fcn','Math','Sqrt'})),p=get_param(leaves{j},'PortHandles');for q=1:numel(p.Outport),log(leaves{j},q,['branch_' get_param(leaves{j},'SID')]);end;end;end;end;end
Ts=evalin('base','Ts_ACR');time=(0:size(inputs,1)-1)'*Ts;ds=Simulink.SimulationData.Dataset;
for k=1:9,x=inputs(:,k);if k==8,x=logical(x);elseif fixed,cfg=evalin('base','FOC_Fixed_Config');key={'Current','Current','Current','Angle','Omega','Current','Current','Reset','Bus'};x=fi(x,cfg.Types.(key{k}),cfg.Fimath);end;ds=ds.addElement(timeseries(x,time),sprintf('u%d',k));end
in=Simulink.SimulationInput(model).setExternalInput(ds).setModelParameter('StopTime',num2str(time(end),17),'SaveOutput','off','SaveTime','off');out=sim(in);
end
function log(b,i,n)
p=get_param(b,'PortHandles');set_param(p.Outport(i),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',n,'DataLoggingDecimateData','off');
end
