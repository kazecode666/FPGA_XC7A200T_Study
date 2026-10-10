function study_l1_d_generate(runname)
% Own XSI snapshot only; no build or model writes to existing FOC runtime.
s=fileparts(mfilename('fullpath')); study=fileparts(s); root=fileparts(fileparts(study));
w=fullfile(study,'.runtime',runname); assert(~isfolder(w)); mkdir(w); cd(w);
assert(strcmp(version('-release'),'2026b')); assert(license('test','EDA_Simulator_Link'));
fprintf('D_XSI_GATE %s EDA_Simulator_Link=1\n',version);
hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');
names=strsplit('mc_fxp_pkg mc_clarke mc_sincos_lut mc_park mc_inv_park mc_current_transform mc_pi_fxp_pkg mc_isqrt_u80 mc_udiv_u72_u41 mc_pi_dq_eval mc_dq_limiter mc_pi_dq_core mc_svpwm_pkg mc_svpwm_sector_xyz mc_sector_svpwm mc_foc_current_core');
files=cellfun(@(n)fullfile(root,'motor_control_ip','foc','rtl',[n '.sv']),names,'UniformOutput',false);
tail={'pwm/rtl/motor_pwm_core.sv','integration/rtl/mc_duty_to_cmp.sv','integration/rtl/mc_foc_pwm_top.sv','integration/rtl/mc_foc_cosim_top.sv'};
files=[files cellfun(@(n)fullfile(root,'motor_control_ip',n),tail,'UniformOutput',false) ...
 {fullfile(study,'generated_hdl','baseline','PI.sv'),fullfile(study,'generated_hdl','baseline','HDLCore.sv'), ...
 fullfile(study,'handwritten','speed_pi_sv.sv'),fullfile(study,'handwritten','study_l1_system_cosim_top.sv')}];
f=fopen(fullfile(w,'source_manifest.txt'),'w'); fprintf(f,'%s\n',files{:}); fclose(f);
rom=fullfile(root,'motor_control_ip','foc','rom','sin_qw_4096x18.mem'); copyfile(rom,w);
simdir=fullfile(w,'hdlverifier_wizard_project','wizprj.sim','sim_1','behav','xsim'); mkdir(simdir); copyfile(rom,simdir);
top='study_l1_system_cosim_top'; c=cosimulationConfiguration('Vivado Simulator','Simulink',top);
c.HDLFiles=files; c.HDLSimulatorPath='E:/AMDDesignTools/2026.1/Vivado/bin';
c.HDLTimeUnit='ns'; c.AutoTimeScale=false; c.TimeScale={1,'s'};
specifyClock(c,'clk','Period',20,'Edge','Rising'); specifyReset(c,'reset_n','InitialValue',0,'Duration',200);
[ins,outs,iw,ow,os,of]=study_l1_d_ports; specifyInput(c,ins);
for k=1:numel(outs), specifyOutput(c,outs{k},'SampleTime',1e-6); end
runWorkflow(c);
% Wizard recreates its simulation directory; restore the ROM after workflow.
copyfile(rom,simdir);
mdl=['hdlverifier_wizard_' top]; load_system(fullfile(w,[mdl '.slx']));
b=find_system(mdl,'SearchDepth',1,'ReferenceBlock','vivadosimlib/HDL Cosimulation'); assert(numel(b)==1);
close_system(mdl,0); study_l1_d_fix_mask(w); fprintf('D_XSI_GENERATION_PASS\n');
end
