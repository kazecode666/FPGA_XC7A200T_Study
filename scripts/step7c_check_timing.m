function step7c_check_timing(reportDir)
root=fileparts(fileparts(mfilename('fullpath'))); mp=path; oldpwd=pwd; ep=getenv('PATH'); ev=getenv('XILINX_VIVADO');
if nargin<1, reportDir=fullfile(root,'docs','reports','step7c'); end
if ~isfolder(reportDir), mkdir(reportDir); end
c=onCleanup(@() restore(oldpwd,mp,ep,ev)); %#ok<NASGU>
addpath(fullfile(root,'simulink模型')); cd(fullfile(root,'.Xil','step7c_foc_cosim'));
hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m)); load_system(m); cm=onCleanup(@() close_system(m,0)); %#ok<NASGU>
si=Simulink.SimulationInput(m); si=si.setModelParameter('FixedStep','1e-6','StopTime','0.0005','ReturnWorkspaceOutputs','on');
for pair={'CONTROL_BACKEND',1;'FPGA_Cosim_Enable',1;'FPGA_Cosim_Input_Mode',1;'FPGA_Reference_Mode',0;'FPGA_Cosim_Ts_s',1e-6;'STEP7C_Comm_Ts_s',1e-6}'
    si=si.setVariable(pair{1},pair{2});
end
si=si.setVariable('STEP7C_iq_ref_ts',timeseries([0;0],[0;0.001]));
si=si.setVariable('PMLSM_Ts_s',1e-6,'Workspace',m);
si=si.setVariable('Host_Enable_Schedule',[0 1 0 1],'Workspace',m);
% The saved InitFcn reloads the model workspace after SimulationInput values.
si=si.setModelParameter('InitFcn',[get_param(m,'InitFcn') newline ...
    'mw=get_param(bdroot,''ModelWorkspace''); mw.assignin(''PMLSM_Ts_s'',1e-6); mw.assignin(''Host_Enable_Schedule'',[0 1 0 1]);']);
si=si.setModelParameter('StartFcn','step7c_assert_timing([],bdroot,1e-6);');
out=sim(si); ts=out.get('fpga_monitor'); d=double(ts.Data); t=ts.Time;
ai=find(diff(d(:,4))>0)+1; ci=find(diff(d(:,5))>0)+1;
assert(numel(ai)>=4 && numel(ci)>=4 && all(abs(diff(t(ai))-100e-6)<1e-12));
assert(all(diff(d(ai,4))==1) && all(diff(d(ci,5))==1));
assert(all(d(:,7:8)==0,'all'));
delay=t(ci)-t(ai(1:numel(ci)))-50e-6; assert(all(abs(delay)<=1e-6+1e-12));
fid=fopen(fullfile(reportDir,'timing_1us.txt'),'w'); cf=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'commTs=1e-6 plant_step=1e-6 Ts_ACR=1e-4 HDL_clock=20e-9 reset=200e-9 prerun=0 timescale=1:1\n');
fprintf(fid,'accepted_transition_times=%s\nactive_transition_times=%s\nvisibility_relative_to_accept_plus_half_period=%s\n',mat2str(t(ai)',17),mat2str(t(ci)',17),mat2str(delay',17));
fprintf(fid,'fault=0 needs_reset=0\nSTEP7C_1US_TIMING_PASS\n'); fprintf('STEP7C_1US_TIMING_PASS\n');
end
function restore(p,mp,ep,ev)
cd(p); path(mp); setenv('PATH',ep); setenv('XILINX_VIVADO',ev);
end
