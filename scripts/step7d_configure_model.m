function [si,cfg,cleanup]=step7d_configure_model(cfg)
% Non-persistent scenario configuration. Caller must keep cleanup alive.
root=fileparts(fileparts(mfilename('fullpath'))); oldpwd=pwd; oldpath=path; ep=getenv('PATH'); ev=getenv('XILINX_VIVADO');
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m),'Step7D:ModelAlreadyLoaded','Save and close the model first.');
assert(any(cfg.backend==[0 1]) && any(abs(cfg.commTs-[1e-6 .5e-6])<1e-15),'Step7D:Config','Invalid backend/step.');
assert(any(strcmp(cfg.purpose,{'performance','convergence','fresh_start'})),'Step7D:Config','Invalid purpose.');
cleanup=onCleanup(@()restore(m,oldpwd,oldpath,ep,ev));
cd(root); addpath(fullfile(root,'simulink模型')); assert(strcmp(version('-release'),'2026b'));
gate=library.settingsLookup(); assert(gate.gatePass);
if cfg.backend==1
 hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');
 cd(fullfile(root,'.Xil','step7c_foc_cosim'));
end
load_system(m); model_read(m,'root');
ops={}; kinds={'speed','load','pwm','reset'}; dest=[1249 941 1247 1257];
for k=1:4
 mode='off'; if k==1, mode='on'; end
 ops{end+1}=struct('op','add_block','type','FromWorkspace','name',['Step7D_Test_' kinds{k}],'ref',kinds{k}, ...
  'params',struct('VariableName',['STEP7D_' kinds{k} '_ts'],'Interpolate',mode,'SampleTime',num2str(cfg.commTs,17),'OutputAfterFinalValue','Holding final value')); %#ok<AGROW>
 ops{end+1}=struct('op','connect','target',sprintf('#%s.y1 -> blk_%d.u1',kinds{k},dest(k))); %#ok<AGROW>
end
result=model_edit(m,'root',jsonencode(ops),'incremental'); disp(result); model_read(m,'root'); disp(model_check(m,'root','["unconnected_ports","unconnected_lines"]'));
% Standard logged outputs, queried by actual SID. No extra controller copy.
spec={191,1,'id_A';191,2,'iq_A';191,3,'ia_A';191,4,'ib_A';191,5,'ic_A';191,6,'x_mm';191,7,'v_mmps';191,8,'theta_rad';191,9,'we_radps'; ...
 991,1,'id_ref_A';991,2,'iq_ref_A';991,3,'v_ref_mmps';523,1,'x_ref_mm';1228,1,'outer_integrator'; ...
 1133,1,'iq_unlimited';1159,1,'iq_limited';1189,1,'hard_reset';1189,2,'int_reset';771,1,'vd';771,2,'vq'};
for k=1:size(spec,1)
 b=Simulink.ID.getFullName(sprintf('%s:%d',m,spec{k,1})); logPort(b,spec{k,2},spec{k,3});
end
for k=1:4, b=find_system(m,'SearchDepth',1,'Name',['Step7D_Test_' kinds{k}]); logPort(b{1},1,['actual_' kinds{k}]); end
adapter=Simulink.ID.getFullName([m ':1453']);
for kind={'ia','ib','ic','theta_e','we','id_ref','iq_ref','pi_reset','run_enable'}
 for prefix={'Select_','Quantize_'}
  b=find_system(adapter,'SearchDepth',1,'Name',[prefix{1} kind{1}]); assert(numel(b)==1);
  logPort(b{1},1,[prefix{1} kind{1}]);
 end
end
inv=Simulink.ID.getFullName([m ':771']);
for k=1:3, b=find_system(inv,'SearchDepth',1,'Name',sprintf('Backend_Duty_%d',k)); logPort(b{1},1,sprintf('duty_%d',k)); end
b=find_system(inv,'SearchDepth',1,'Name','Backend_Enable'); logPort(b{1},1,'selected_enable');
si=Simulink.SimulationInput(m);
si=si.setModelParameter('FixedStep',num2str(cfg.commTs,17),'StopTime',num2str(cfg.stopTime,17),'ReturnWorkspaceOutputs','on','SignalLogging','on','SignalLoggingName','logsout');
for k=1:4
 xy=cfg.signals.(kinds{k}); si=si.setVariable(['STEP7D_' kinds{k} '_ts'],timeseries(xy(:,2),xy(:,1)));
end
for pair={'CONTROL_BACKEND',cfg.backend;'FPGA_Cosim_Enable',1;'FPGA_Cosim_Input_Mode',1;'FPGA_Reference_Mode',1; ...
 'FPGA_Cosim_Ts_s',cfg.commTs;'STEP7C_Comm_Ts_s',cfg.commTs}'
 si=si.setVariable(pair{1},pair{2});
end
si=si.setVariable('STEP7C_run_gate_ts',timeseries([1;1],[0;cfg.stopTime]));
si=si.setVariable('STEP7C_id_ref_ts',timeseries([0;0],[0;cfg.stopTime]));
si=si.setVariable('STEP7C_iq_ref_ts',timeseries([0;0],[0;cfg.stopTime]));
si=si.setVariable('STEP7D_CFG',cfg);
host=cfg.host; host.PMLSM_Ts_s=cfg.commTs; host.PMLSM_deadtime_s=cfg.deadtime_s; host.PMLSM_deadtime_ratio=cfg.deadtime_s/1e-4; host.Udc=48;
init='mw=get_param(bdroot,''ModelWorkspace'');'; fn=fieldnames(host);
for k=1:numel(fn), init=[init sprintf('mw.assignin(''%s'',%s);',fn{k},mat2str(host.(fn{k}),17))]; end %#ok<AGROW>
si=si.setModelParameter('InitFcn',[get_param(m,'InitFcn') newline init], 'StartFcn','step7d_record_start(bdroot,slResolve(''STEP7D_CFG'',bdroot));');
if cfg.backend==1
 h=find_system(m,'MatchFilter',@Simulink.match.allVariants,'Name','HDL_Cosimulation'); assert(numel(h)==1);
 si=si.setBlockParameter(h{1},'PortTimes',strrep(mat2str([-ones(1,11) cfg.commTs*ones(1,8)],17),' ',','));
end
end
function logPort(b,n,name)
p=get_param(b,'PortHandles'); set_param(p.Outport(n),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',name);
end
function restore(m,p,mp,ep,ev)
global STEP7D_RUN_LISTENERS STEP7D_RUN_EVENTS STEP7D_RUN_EFFECTIVE
STEP7D_RUN_LISTENERS=[]; STEP7D_RUN_EVENTS=[]; STEP7D_RUN_EFFECTIVE=[];
if bdIsLoaded(m), close_system(m,0); end
cd(p); path(mp); setenv('PATH',ep); setenv('XILINX_VIVADO',ev);
end
