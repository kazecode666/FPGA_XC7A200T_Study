function step7b_open_cosim(kind)
% Interactive session setup only. No global PATH change and no model save.
if nargin==0, kind='foc'; end
root=fileparts(fileparts(mfilename('fullpath')));
assert(strcmp(version('-release'),'2026b'),'Use R2026b');
assert(any(strcmp(kind,{'foc','minimal'})));
work=fullfile(root,'.Xil',['step7b_' kind '_cosim']);
assert(isfile(fullfile(work,'xsim.dir','design','xsimk.dll')),'Regenerate the selected XSI runtime first');
addpath(fullfile(root,'simulink模型'));
hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');
cd(work);
if strcmp(kind,'foc')
    m='PMLSM_ThreeLoop_Simple'; open_system(m);
    set_param(m,'StopTime','200e-6','ReturnWorkspaceOutputs','on');
    open_system([m '/FPGA_HDL_Cosim']);
else
    open_system('PMLSM_HDL_Cosim_Minimal');
end
fprintf('Ready for Run. Runtime directory and PATH apply only to this MATLAB session. Do not save transient stop-time overrides.\n');
end
