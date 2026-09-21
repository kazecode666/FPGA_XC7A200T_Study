function step7b_refresh_foc_block
% Refresh only the generated XSI mask, preserving all model wiring/layout.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'simulink模型'));
m='PMLSM_ThreeLoop_Simple'; g='hdlverifier_wizard_mc_foc_cosim_top';
assert(~bdIsLoaded(m)); load_system(m);
cm=onCleanup(@() close_system(m,0)); %#ok<NASGU>
load_system(fullfile(root,'.Xil','step7b_foc_cosim',[g '.slx']));
cg=onCleanup(@() close_system(g,0)); %#ok<NASGU>
b=find_system(g,'SearchDepth',1,'ReferenceBlock','vivadosimlib/HDL Cosimulation'); assert(numel(b)==1);
set_param([m '/FPGA_HDL_Cosim/HDL_Cosimulation'],'UserData',get_param(b{1},'UserData'),'UserDataPersistent','on');
for f={'PortPaths','PortModes','PortTimes','PortSigns','PortFracLengths','PortWordLengths','PortHDLWordSizes','ClockPaths','ClockModes','ClockTimes','PreRunTime'}
    set_param([m '/FPGA_HDL_Cosim/HDL_Cosimulation'],f{1},get_param(b{1},f{1}));
end
save_system(m);
end
