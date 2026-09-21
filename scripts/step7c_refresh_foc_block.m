function step7c_refresh_foc_block
root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'simulink模型'));
m='PMLSM_ThreeLoop_Simple'; g='hdlverifier_wizard_mc_foc_cosim_top'; assert(~bdIsLoaded(m)); load_system(m);
cm=onCleanup(@() close_system(m,0)); %#ok<NASGU>
load_system(fullfile(root,'.Xil','step7c_foc_cosim',[g '.slx'])); cg=onCleanup(@() close_system(g,0)); %#ok<NASGU>
b=find_system(g,'SearchDepth',1,'ReferenceBlock','vivadosimlib/HDL Cosimulation'); assert(numel(b)==1);
h=[m '/FPGA_HDL_Cosim/HDL_Backend_Variant/FPGA_Enabled/HDL_Cosimulation'];
set_param(h,'UserData',get_param(b{1},'UserData'),'UserDataPersistent','on');
for f={'PortPaths','PortModes','PortTimes','PortSigns','PortFracLengths','PortWordLengths','PortHDLWordSizes','ClockPaths','ClockModes','ClockTimes','PreRunTime'}
    set_param(h,f{1},get_param(b{1},f{1}));
end
t=str2num(get_param(h,'PortTimes')); modes=str2num(get_param(h,'PortModes')); clocks=str2num(get_param(h,'ClockTimes')); %#ok<ST2NM>
assert(sum(modes==1)==11 && sum(modes==2)==8 && all(t(12:end)==1e-6));
assert(isequal(clocks,[20e-9 200e-9]));
save_system(m); fprintf('STEP7C_REFERENCE_MASK_SAVED\n');
end
