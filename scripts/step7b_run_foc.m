function step7b_run_foc(mode)
if nargin==0, mode='foc'; end
root=fileparts(fileparts(mfilename('fullpath')));
assert(strcmp(version('-release'),'2026b'));
oldpwd=pwd; oldpath=getenv('PATH'); oldvivado=getenv('XILINX_VIVADO'); mp=path;
cleanup=onCleanup(@() restore(oldpwd,oldpath,oldvivado,mp)); %#ok<NASGU>
hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');
addpath(fullfile(root,'simulink模型'));
work=fullfile(root,'.Xil','step7b_foc_cosim'); cd(work);
copyfile(fullfile(root,'motor_control_ip','foc','rom','sin_qw_4096x18.mem'),work);
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m),'Close Simple model before acceptance run');
load_system(m); cm=onCleanup(@() close_system(m,0)); %#ok<NASGU>
assert(getSimulinkBlockHandle([m '/FPGA_HDL_Cosim'])>0,'STEP7B_MISSING_FOC_BRANCH');
si=Simulink.SimulationInput(m); si=si.setModelParameter('StopTime','200e-6','ReturnWorkspaceOutputs','on');
si=si.setVariable('FPGA_Cosim_Input_Mode',0);
if strcmp(mode,'legacy')
    si=si.setVariable('FPGA_Cosim_Enable',0); file='legacy_short_run.txt';
else
    assert(strcmp(mode,'foc')); si=si.setVariable('FPGA_Cosim_Enable',1);
    si=si.setModelParameter('FixedStep','50e-6'); file='foc_cosim_result.txt';
end
out=sim(si); ts=out.get('fpga_monitor'); data=double(ts.Data);
fid=fopen(fullfile(root,'docs','reports','step7b',file),'w'); cl=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'columns=time cmp_u cmp_v cmp_w accepted_id active_id valid needs_reset fault duty_u duty_v duty_w range_flags(11)\n');
for k=1:numel(ts.Time), fprintf(fid,'%s\n',strtrim(sprintf('%.12g ',[ts.Time(k) data(k,:)]))); end
assert(all(data(:,7)==0 & data(:,8)==0),'HDL fault/reset required');
assert(all(data(:,12:end)==0,'all'),'Input conversion saturated');
assert(all(abs(data(:,9:11)-data(:,1:3)/2500)<1e-12,'all'),'Duty is not active CMP/2500');
if strcmp(mode,'legacy')
    assert(all(data(:,6)==0),'Disabled branch produced valid output');
    marker='STEP7B_LEGACY_SHORT_RUN_PASS';
else
    first=find(data(:,5)>=1 & data(:,6)==1,1);
    assert(~isempty(first) && data(first,4)>=1,'No accepted active command');
    assert(isequal(data(first,1:3),[1165 1335 1335]),'First active CMP mismatch');
    marker='STEP7B_FOC_COSIM_SMOKE_PASS';
end
fprintf(fid,'%s\n',marker); fprintf('%s\n',marker);
end
function restore(p,e,v,mp)
cd(p); setenv('PATH',e); setenv('XILINX_VIVADO',v); path(mp);
end
