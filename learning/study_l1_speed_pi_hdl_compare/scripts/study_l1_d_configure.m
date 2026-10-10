function [m,cfg]=study_l1_d_configure(cfg,implementation,runtime,copydir)
% Build a disposable Study copy from the actual user's saved model.
% Shared blocks retain their original calculations and timing.
s=fileparts(mfilename('fullpath')); study=fileparts(s); root=fileparts(fileparts(study));
addpath(s,fullfile(root,'scripts'),fullfile(root,'simulink模型'));
assert(~isfolder(copydir)); mkdir(copydir);
Simulink.fileGenControl('set','CacheFolder',fullfile(copydir,'cache'),'CodeGenFolder',fullfile(copydir,'codegen'),'createDir',true);
m='study_l1_system_tb'; assert(~bdIsLoaded(m));
dst=fullfile(copydir,[m '.slx']); copyfile(fullfile(root,'simulink模型','PMLSM_ThreeLoop_Simple.slx'),dst);
cd(fullfile(root,'simulink模型')); load_system(dst);
set_param(m,'InitFcn','','StartFcn','','StopFcn',''); mw=get_param(m,'ModelWorkspace'); reload(mw);
frozen=study_l1_init; for n=fieldnames(frozen)', assert(isequal(mw.getVariable(n{1}),frozen.(n{1}))); end
mw.DataSource='Model File'; % Embed only in the disposable copy, never source m/MAT.
before=fingerprint(m); cfg.implementation=implementation;
host=cfg.host; host.PMLSM_Ts_s=cfg.commTs; host.PMLSM_deadtime_s=cfg.deadtime_s; host.PMLSM_deadtime_ratio=cfg.deadtime_s/1e-4; host.Udc=48;
for n=fieldnames(host)', mw.assignin(n{1},host.(n{1})); end
pairs={'CONTROL_BACKEND',1;'FPGA_Cosim_Enable',1;'FPGA_Cosim_Input_Mode',1;'FPGA_Reference_Mode',1;'FPGA_Cosim_Ts_s',cfg.commTs;'STEP7C_Comm_Ts_s',cfg.commTs};
for j=1:size(pairs,1)
 mw.assignin(pairs{j,1},pairs{j,2});
end
% VariantExpression requires its control in the base workspace. This private
% batch process uses the existing 0/1 meaning and selects 1 in all Study cases.
assignin('base','CONTROL_BACKEND',1);
assignin('base','V_Backend_Legacy',Simulink.VariantExpression('CONTROL_BACKEND == 0'));
assignin('base','V_Backend_FPGA',Simulink.VariantExpression('CONTROL_BACKEND == 1'));
% Simulink variant controls are resolved only from base workspace/dictionary.
% Remove private model-workspace shadows; ordinary blocks resolve the same 1.
mw.evalin('clear CONTROL_BACKEND V_Backend_Legacy V_Backend_FPGA');
pairs={'STEP7C_run_gate_ts',1;'STEP7C_id_ref_ts',0;'STEP7C_iq_ref_ts',0};
for j=1:size(pairs,1), mw.assignin(pairs{j,1},timeseries([pairs{j,2};pairs{j,2}],[0;cfg.stopTime])); end
kinds={'speed','load','pwm','reset'}; dest=[1249 941 1247 1257];
for k=1:4
 xy=cfg.signals.(kinds{k}); vn=['STUDY_D_' kinds{k} '_ts']; mw.assignin(vn,timeseries(xy(:,2),xy(:,1)));
 b=add_block('simulink/Sources/From Workspace',[m '/Study_D_' kinds{k}],'VariableName',vn,'SampleTime',num2str(cfg.commTs,17),'Interpolate','off','OutputAfterFinalValue','Holding final value');
 if k==1, set_param(b,'Interpolate','on'); end
 ph=get_param(b,'PortHandles'); dp=get_param(sid(m,dest(k)),'PortHandles'); replaceInput(m,dp.Inport(1),ph.Outport(1)); logPort(b,1,['actual_' kinds{k}]);
end
% Original speed scheduler and actual PI source inputs are exported unchanged.
ct=sid(m,505); ctph=get_param(ct,'PortHandles');
readNames={'PI_Reset_EN_cmd','Iq_Test_Mode_cmd','Close_Loop_EN_cmd'};
reads=cellfun(@(n)find_system(ct,'SearchDepth',1,'Name',n),readNames,'UniformOutput',false);
assert(all(cellfun(@numel,reads)==1));
for k=1:3
 % The existing named blocks are DataStoreMemory, not signal sources.
 % Read the identical local command stores used by the original reset manager.
 tag=get_param(reads{k}{1},'DataStoreName');
 reads{k}={add_block('simulink/Signal Routing/Data Store Read',[ct '/Study_read_' tag],'DataStoreName',tag)};
end
src={sid(m,1264),[ct '/v_mmps'],reads{3}{1},reads{1}{1},sid(m,740),sid(m,1272),reads{2}{1}};
nm={'ref','meas','enable','reset','tick','angle','test'};
speedsrc=zeros(1,7);
for k=1:7
 ph=get_param(src{k},'PortHandles'); speedsrc(k)=expose(ph.Outport(1),m,['Study_speed_' nm{k}]);
 logHandle(speedsrc(k),['D_speed_' nm{k}]);
end
% A single root XSI block. The old variant boundary retains its 11/8 ports:
% its data inputs are exposed, and its outputs return through global tags.
% This changes the simulation carrier only, not either variant's algorithms.
old=sid(m,1646); ph=get_param(old,'PortHandles'); parent=get_param(old,'Parent'); pos=get_param(old,'Position');
oldIns=zeros(1,11); oldOuts=cell(1,8);
for k=1:11, ln=get_param(ph.Inport(k),'Line'); oldIns(k)=get_param(ln,'SrcPortHandle'); end
for k=1:8, ln=get_param(ph.Outport(k),'Line'); oldOuts{k}=get_param(ln,'DstPortHandle'); end
% Disconnect explicit block lines only in the disposable copy.
for k=1:11, delete_line(get_param(ph.Inport(k),'Line')); end
for k=1:8, delete_line(get_param(ph.Outport(k),'Line')); end
delete_block(old); add_block('built-in/Subsystem',old,'Position',pos);
for k=1:11
 ib=add_block('built-in/Inport',[old '/input_' num2str(k)],'Port',num2str(k)); ibp=get_param(ib,'PortHandles');
 tb=add_block('built-in/Terminator',[old '/unused_' num2str(k)]); tp=get_param(tb,'PortHandles'); add_line(old,ibp.Outport(1),tp.Inport(1));
end
for k=1:8
 fb=add_block('simulink/Signal Routing/From',[old '/return_' num2str(k)],'GotoTag',['Study_D_FOC_' num2str(k)]);
 ob=add_block('built-in/Outport',[old '/output_' num2str(k)],'Port',num2str(k)); fp=get_param(fb,'PortHandles'); op=get_param(ob,'PortHandles'); add_line(old,fp.Outport(1),op.Inport(1));
end
np=get_param(old,'PortHandles');
for k=1:11, add_line(parent,oldIns(k),np.Inport(k)); end
for k=1:8, for dp=oldOuts{k}(:)', add_line(parent,np.Outport(k),dp); end; end
wizard='hdlverifier_wizard_study_l1_system_cosim_top'; load_system(fullfile(runtime,[wizard '.slx']));
wb=find_system(wizard,'SearchDepth',1,'ReferenceBlock','vivadosimlib/HDL Cosimulation');
xb=add_block(wb{1},[m '/Study_D_XSI'],'Position',[1800 900 2080 1500]); close_system(wizard,0);
xp=get_param(xb,'PortHandles'); adapter=sid(m,1453); ap=get_param(adapter,'PortHandles');
for k=1:11
 rp=expose(ap.Outport(k),m,['Study_FOC_input_' num2str(k)]); add_line(m,rp,xp.Inport(k));
end
cb=add_block('simulink/Sources/Constant',[m '/Study_speed_backend'],'Value',num2str(strcmp(implementation,'hand_sv')),'OutDataTypeStr','boolean'); cp=get_param(cb,'PortHandles'); add_line(m,cp.Outport(1),xp.Inport(12));
% Existing FOC casts remain Nearest. Only velocity ingress follows frozen B1.
for k=1:7
 name=['Study_speed_cast_' nm{k}]; dt='boolean'; if k<=2, dt='fixdt(1,32,20)'; end
 b=add_block('simulink/Signal Attributes/Data Type Conversion',[m '/' name],'OutDataTypeStr',dt,'RndMeth','Convergent','SaturateOnIntegerOverflow','on');
 bp=get_param(b,'PortHandles'); add_line(m,speedsrc(k),bp.Inport(1)); add_line(m,bp.Outport(1),xp.Inport(12+k));
end
for k=1:8
 gb=add_block('simulink/Signal Routing/Goto',[m '/Study_FOC_return_' num2str(k)],'GotoTag',['Study_D_FOC_' num2str(k)],'TagVisibility','global'); gp=get_param(gb,'PortHandles'); add_line(m,xp.Outport(k),gp.Inport(1));
end
[~,outs]=study_l1_d_ports;
for k=9:numel(outs), logHandle(xp.Outport(k),['D_hdl_' outs{k}]); end
logHandle(xp.Outport(24),'D_speed_result_count'); logHandle(xp.Outport(25),'D_speed_source_count');
logHandle(xp.Outport(26),'D_speed_result_cycle'); logHandle(xp.Outport(27),'D_speed_launch_cycle');
% Feedback holds have explicit one communication-step transport. The old
% Reference_Manager consumes the latest held value on its 100 us task.
cast=add_block('simulink/Signal Attributes/Data Type Conversion',[m '/Study_speed_double'],'OutDataTypeStr','double'); dp=get_param(cast,'PortHandles'); add_line(m,xp.Outport(9),dp.Inport(1));
delay=add_block('simulink/Discrete/Unit Delay',[m '/Study_speed_feedback_hold'],'SampleTime',num2str(cfg.commTs,17),'InitialCondition','0'); hp=get_param(delay,'PortHandles'); add_line(m,dp.Outport(1),hp.Inport(1));
ib=add_block('built-in/Inport',[ct '/Study_speed_feedback'],'Port','16'); ip=get_param(ib,'PortHandles'); ctp=get_param(ct,'PortHandles'); add_line(m,hp.Outport(1),ctp.Inport(16));
sw=add_block('simulink/Signal Routing/Switch',[ct '/Study_speed_select'],'Threshold','.5'); sp=get_param(sw,'PortHandles');
enable=add_block('simulink/Sources/Constant',[ct '/Study_use_RTL_speed'],'Value',num2str(~strcmp(implementation,'original'))); ep=get_param(enable,'PortHandles');
pi=sid(m,1122); pip=get_param(pi,'PortHandles'); route=sid(m,1261); rp=get_param(route,'PortHandles');
delete_line(get_param(rp.Inport(1),'Line')); add_line(ct,ip.Outport(1),sp.Inport(1)); add_line(ct,ep.Outport(1),sp.Inport(2)); add_line(ct,pip.Outport(1),sp.Inport(3)); add_line(ct,sp.Outport(1),rp.Inport(1));
if strcmp(implementation,'original'), logPort(pi,1,'D_speed_iq'); else, logHandle(dp.Outport(1),'D_speed_iq'); end
spec={191,1,'id_A';191,2,'iq_A';191,3,'ia_A';191,4,'ib_A';191,5,'ic_A';191,6,'x_mm';191,7,'v_mmps';191,8,'theta_rad';191,9,'we_radps';991,1,'id_ref_A';991,2,'iq_ref_A';991,3,'v_ref_mmps';523,1,'x_ref_mm';1228,1,'outer_integrator';1133,1,'iq_unlimited';1159,1,'iq_limited';1189,1,'hard_reset';1189,2,'int_reset';771,1,'vd';771,2,'vq'};
for k=1:size(spec,1), logPort(sid(m,spec{k,1}),spec{k,2},spec{k,3}); end
for kind={'ia','ib','ic','theta_e','we','id_ref','iq_ref','pi_reset','run_enable'}
 for prefix={'Select_','Quantize_'}, b=find_system(adapter,'SearchDepth',1,'Name',[prefix{1} kind{1}]); assert(numel(b)==1); logPort(b{1},1,[prefix{1} kind{1}]); end
end
inv=sid(m,771); for k=1:3, b=find_system(inv,'SearchDepth',1,'Name',sprintf('Backend_Duty_%d',k)); logPort(b{1},1,sprintf('duty_%d',k)); end
b=find_system(inv,'SearchDepth',1,'Name','Backend_Enable'); logPort(b{1},1,'selected_enable');
after=fingerprint(m); assert(isequal(before,after),'StudyD:SharedGraphChanged','Shared system graph changed');
cfg.shared_fingerprint=before;
set_param(m,'FixedStep',num2str(cfg.commTs,17),'StopTime',num2str(cfg.stopTime,17),'ReturnWorkspaceOutputs','on','SignalLogging','on','SignalLoggingName','logsout','StartFcn','study_l1_d_start(bdroot);');
mw.assignin('STUDY_D_CFG',cfg); cd(runtime);
% Save only this owned, independently named artifact; it is reproducible.
save_system(m,dst);
end
function b=sid(m,n), b=Simulink.ID.getFullName(sprintf('%s:%d',m,n)); end
function replaceInput(parent,dp,sp)
ln=get_param(dp,'Line'); if ln~=-1, delete_line(ln); end; add_line(parent,sp,dp);
end
function rp=expose(sp,root,name)
parent=get_param(get_param(sp,'Parent'),'Parent');
while ~strcmp(parent,root)
 existing=find_system(parent,'SearchDepth',1,'BlockType','Outport'); num=numel(existing)+1;
 ob=add_block('built-in/Outport',[parent '/' name],'Port',num2str(num)); op=get_param(ob,'PortHandles'); add_line(parent,sp,op.Inport(1));
 pp=get_param(parent,'PortHandles'); sp=pp.Outport(num); parent=get_param(parent,'Parent');
end
rp=sp;
end
function logPort(b,n,name), p=get_param(b,'PortHandles'); logHandle(p.Outport(n),name); end
function logHandle(p,name), set_param(p,'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',name); end
function data=fingerprint(m)
% Original Host, Position, scheduler, float PI, manager, plant and inverter.
data=struct;
for n=[523 785 767 546 1122 1109 740 991 191 771 1453]
 b=sid(m,n); blocks=find_system(b,'MatchFilter',@Simulink.match.allVariants,'Type','Block'); item=cell(numel(blocks),1);
 for k=1:numel(blocks)
  q=blocks{k}; pars=get_param(q,'DialogParameters'); vals=struct;
  if ~isstruct(pars), pars=struct; end
  for key=fieldnames(pars)', if ~any(strcmp(key{1},{'Port','GotoTag','DataLogging'})), vals.(key{1})=get_param(q,key{1}); end; end
  item{k}=struct('path',erase(q,[m '/']),'type',get_param(q,'BlockType'),'params',vals);
 end
 lines=find_system(b,'FindAll','on','Type','line'); topology=cell(0,1);
 for k=1:numel(lines)
  sp=get_param(lines(k),'SrcPortHandle'); dp=get_param(lines(k),'DstPortHandle');
  if sp==-1, continue; end
  for target=dp(:)', if target==-1, continue; end
   topology{end+1,1}=sprintf('%s:%d->%s:%d',erase(get_param(sp,'Parent'),[m '/']),get_param(sp,'PortNumber'),erase(get_param(target,'Parent'),[m '/']),get_param(target,'PortNumber')); %#ok<AGROW>
  end
 end
 data.(['sid_' num2str(n)])=struct('blocks',{item},'lines',{sort(topology)});
end
end
