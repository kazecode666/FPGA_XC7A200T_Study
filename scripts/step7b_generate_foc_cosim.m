function step7b_generate_foc_cosim(rebuild)
% Regenerate the local XSI runtime; generated binaries stay outside Git.
if nargin==0, rebuild=true; end
root=fileparts(fileparts(mfilename('fullpath')));
assert(strcmp(version('-release'),'2026b'));
oldpwd=pwd; oldpath=getenv('PATH'); oldvivado=getenv('XILINX_VIVADO');
cleanup=onCleanup(@() localRestore(oldpwd,oldpath,oldvivado)); %#ok<NASGU>
hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');
work=fullfile(root,'.Xil','step7b_foc_cosim');
if ~isfolder(work), mkdir(work); end
rom=fullfile(root,'motor_control_ip','foc','rom','sin_qw_4096x18.mem');
copyfile(rom,work);
simdir=fullfile(work,'hdlverifier_wizard_project','wizprj.sim','sim_1','behav','xsim');
if ~isfolder(simdir), mkdir(simdir); end
copyfile(rom,simdir);
cd(work);
names=strsplit('mc_fxp_pkg mc_clarke mc_sincos_lut mc_park mc_inv_park mc_current_transform mc_pi_fxp_pkg mc_isqrt_u80 mc_udiv_u72_u41 mc_pi_dq_eval mc_dq_limiter mc_pi_dq_core mc_svpwm_pkg mc_svpwm_sector_xyz mc_sector_svpwm mc_foc_current_core');
files=cellfun(@(s) fullfile(root,'motor_control_ip','foc','rtl',[s '.sv']),names,'UniformOutput',false);
tail={'pwm/rtl/motor_pwm_core.sv','integration/rtl/mc_duty_to_cmp.sv','integration/rtl/mc_foc_pwm_top.sv','integration/rtl/mc_foc_cosim_top.sv'};
files=[files cellfun(@(s) fullfile(root,'motor_control_ip',s),tail,'UniformOutput',false)];
c=cosimulationConfiguration('Vivado Simulator','Simulink','mc_foc_cosim_top');
c.HDLFiles=files;
c.HDLSimulatorPath='E:/AMDDesignTools/2026.1/Vivado/bin';
c.HDLTimeUnit='ns'; c.AutoTimeScale=false; c.TimeScale={1,'s'};
specifyClock(c,'clk','Period',20,'Edge','Rising');
specifyReset(c,'reset_n','InitialValue',0,'Duration',200);
% Prevent name-based reset inference from consuming the data-side PI reset.
specifyInput(c,{'run_enable','ia','ib','ic','theta_e','we','id_ref','iq_ref','vdc','pi_reset','uq_zero_en'});
outs={'cmp_u_active','cmp_v_active','cmp_w_active','accepted_sample_id','active_command_id','active_valid','needs_reset','fault_code'};
for k=1:numel(outs), specifyOutput(c,outs{k},'SampleTime',50e-6); end
if rebuild, runWorkflow(c); end
% R2026b wizard still heuristically assigns pi_reset to its clock/reset table.
% Set the documented block mask explicitly so it remains a Simulink data port.
mdl='hdlverifier_wizard_mc_foc_cosim_top'; load_system(fullfile(work,[mdl '.slx']));
b=find_system(mdl,'SearchDepth',1,'ReferenceBlock','vivadosimlib/HDL Cosimulation'); assert(numel(b)==1);
ins={'run_enable','ia','ib','ic','theta_e','we','id_ref','iq_ref','vdc','pi_reset','uq_zero_en'};
ports=[ins outs]; paths=strjoin(cellfun(@(s) ['/mc_foc_cosim_top/' s],ports,'UniformOutput',false),';');
ud=get_param(b{1},'UserData');
% HdlSigInfo is positional; insert the identical one-bit input descriptor.
if numel(ud.HdlSigInfo)==18
    ud.HdlSigInfo=[ud.HdlSigInfo(1:9); ud.HdlSigInfo(1); ud.HdlSigInfo(10:end)];
end
assert(numel(ud.HdlSigInfo)==19);
set_param(b{1},'UserData',ud,'UserDataPersistent','on');
set_param(b{1},'PortPaths',[paths ';'],'PortModes',mat2str([ones(1,11) 2*ones(1,8)]),...
    'PortTimes',csv([-ones(1,11) 50e-6*ones(1,8)]),'PortSigns',csv(-ones(1,19)),...
    'PortFracLengths',csv(zeros(1,19)),'PortWordLengths',csv([-ones(1,11) 12 12 12 32 32 1 1 3]),...
    'PortHDLWordSizes',csv([1 24 24 24 16 32 25 25 25 1 1 12 12 12 32 32 1 1 3]),...
    'ClockPaths','/mc_foc_cosim_top/clk;/mc_foc_cosim_top/reset_n;',...
    'ClockModes','[2 4]','ClockTimes','[2e-8 2e-7]','PreRunTime','0');
save_system(mdl); close_system(mdl,0);
fprintf('STEP7B_FOC_GENERATION_COMPLETE\n');
end
function localRestore(p,e,v)
cd(p); setenv('PATH',e); setenv('XILINX_VIVADO',v);
end
function s=csv(v)
s=strrep(mat2str(v),' ',',');
end
