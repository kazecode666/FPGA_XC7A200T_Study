function result=step7c_run_scenario(name,commTs)
if nargin<2, commTs=1e-6; end
if strcmp(name,'legacy'), result=step7c_capture_legacy_baseline('after'); return; end
assert(any(strcmp(name,{'ideal','deadtime','stop'})),'Unsupported scenario');
deadtime=double(strcmp(name,'deadtime'))*1e-6;
root=fileparts(fileparts(mfilename('fullpath'))); p=pwd; mp=path; ep=getenv('PATH'); ev=getenv('XILINX_VIVADO');
c=onCleanup(@() restore(p,mp,ep,ev)); %#ok<NASGU>
addpath(fullfile(root,'simulink模型')); cd(fullfile(root,'.Xil','step7c_foc_cosim'));
hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m)); load_system(m); cm=onCleanup(@() close_system(m,0)); %#ok<NASGU>
h=[m '/FPGA_HDL_Cosim/HDL_Backend_Variant/FPGA_Enabled/HDL_Cosimulation'];
set_param(h,'PortTimes',strrep(mat2str([-ones(1,11) commTs*ones(1,8)],17),' ',','));
a=[m '/FPGA_HDL_Cosim/FPGA_Input_Adapter'];
names={'ia','ib','ic','theta_e','we'};
for k=1:5, tap(a,['Select_' names{k}],['live_' names{k}]); end
v=[m '/Inverter_DeadTime']; for k=1:3, tap(v,['Backend_Duty_' num2str(k)],['selected_' num2str(k)]); end
tap(v,'Backend_Enable','selected_enable');
si=Simulink.SimulationInput(m); si=si.setModelParameter('FixedStep',num2str(commTs,17),'StopTime','0.031','ReturnWorkspaceOutputs','on');
for pair={'CONTROL_BACKEND',1;'FPGA_Cosim_Enable',1;'FPGA_Cosim_Input_Mode',1;'FPGA_Reference_Mode',0;'FPGA_Cosim_Ts_s',commTs;'STEP7C_Comm_Ts_s',commTs}'
    si=si.setVariable(pair{1},pair{2});
end
times=[0 1e-3 11e-3 16e-3 26e-3 31e-3]';
si=si.setVariable('STEP7C_iq_ref_ts',timeseries([0 .5 0 -.5 0 0]',times));
si=si.setVariable('STEP7C_id_ref_ts',timeseries([0;0],[0;.031]));
si=si.setVariable('STEP7C_run_gate_ts',timeseries([1;1],[0;.031]));
if strcmp(name,'stop'), si=si.setVariable('STEP7C_run_gate_ts',timeseries([1;0;0],[0;.008;.031])); end
init=sprintf('mw=get_param(bdroot,''ModelWorkspace''); mw.assignin(''PMLSM_Ts_s'',%.17g); mw.assignin(''PMLSM_deadtime_s'',0); mw.assignin(''PMLSM_deadtime_ratio'',0); mw.assignin(''Host_Enable_Schedule'',[0 1 0 1]); mw.assignin(''Host_Load_N'',0); mw.assignin(''Udc'',48);',commTs);
init=[init sprintf(' mw.assignin(''PMLSM_deadtime_s'',%.17g); mw.assignin(''PMLSM_deadtime_ratio'',%.17g);',deadtime,deadtime/1e-4)];
si=si.setModelParameter('InitFcn',[get_param(m,'InitFcn') newline init],'StartFcn',sprintf('step7c_assert_timing([],bdroot,%.17g);',commTs));
out=sim(si); ts=out.get('step7c_monitor'); result=struct('time',ts.Time,'data',double(ts.Data),'commTs',commTs,'name',name);
f=out.get('fpga_monitor'); result.rangeFlags=max(double(f.Data(:,12:end)),[],1);
result.live=zeros(numel(ts.Time),5); result.selected=zeros(numel(ts.Time),4);
for k=1:5, q=out.get(['live_' names{k}]); assert(isequal(q.Time,ts.Time)); result.live(:,k)=double(q.Data); end
for k=1:3, q=out.get(['selected_' num2str(k)]); assert(isequal(q.Time,ts.Time)); result.selected(:,k)=double(q.Data); end
q=out.get('selected_enable'); result.selected(:,4)=double(q.Data);
end
function tap(parent,source,var)
b=[parent '/Step7C_' var]; add_block('simulink/Sinks/To Workspace',b,'VariableName',var,'SaveFormat','Timeseries'); add_line(parent,[source '/1'],['Step7C_' var '/1']);
end
function restore(p,mp,ep,ev)
cd(p); path(mp); setenv('PATH',ep); setenv('XILINX_VIVADO',ev);
end
