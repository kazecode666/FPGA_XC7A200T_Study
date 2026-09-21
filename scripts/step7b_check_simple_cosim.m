function step7b_check_simple_cosim
% Read actual connections and masks, update without saving.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'simulink模型'));
oldpwd=pwd; oldpath=getenv('PATH'); oldvivado=getenv('XILINX_VIVADO');
restore=onCleanup(@() localRestore(oldpwd,oldpath,oldvivado)); %#ok<NASGU>
hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');
cd(fullfile(root,'.Xil','step7b_foc_cosim'));
m='PMLSM_ThreeLoop_Simple'; load_system(m); cleanup=onCleanup(@() close_system(m,0)); %#ok<NASGU>
p=[m '/FPGA_HDL_Cosim']; assert(getSimulinkBlockHandle(p)>0,'STEP7B_MISSING_FOC_BRANCH');
fid=fopen(fullfile(root,'docs','reports','step7b','simple_model_after.txt'),'w'); c=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'Model=%s\nSolver=%s\nFixedStep=%s\nInitFcn=%s\n',m,get_param(m,'Solver'),get_param(m,'FixedStep'),get_param(m,'InitFcn'));
assert(strcmp(get_param(m,'Solver'),'FixedStepDiscrete'));
assert(strcmp(get_param(m,'FixedStep'),'PMLSM_Ts_s'));
for s={'Control_Task_10kHz','Inverter_DeadTime','PMLSM_Plant_Model'}
    ports=get_param([m '/' s{1}],'PortHandles');
    for h=ports.Inport
        l=get_param(h,'Line'); assert(l>0); src=get_param(l,'SrcPortHandle');
        fprintf(fid,'%s:%d -> %s:%d\n',get_param(src,'Parent'),get_param(src,'PortNumber'),get_param(h,'Parent'),get_param(h,'PortNumber'));
        assert(~contains(get_param(src,'Parent'),'FPGA_'));
        if strcmp(s{1},'Inverter_DeadTime') && get_param(h,'PortNumber')<=3
            assert(strcmp(get_param(src,'Parent'),[m '/Control_Task_10kHz']),'Legacy compare connection lost');
        end
    end
end
% Monitor subsystem has no output ports, so no path can drive the plant.
ph=get_param(p,'PortHandles'); assert(isempty(ph.Outport));
g=find_system(m,'SearchDepth',1,'BlockType','From');
for k=1:numel(g), if contains(g{k},'/FPGA_Live_'), fprintf(fid,'LIVE_SOURCE=%s tag=%s\n',g{k},get_param(g{k},'GotoTag')); end, end
h=[p '/HDL_Cosimulation'];
for field={'PortPaths','PortModes','PortTimes','PortSigns','PortFracLengths','ClockPaths','ClockTimes','PreRunTime','TimingMode','TimingScaleFactor'}
    fprintf(fid,'%s=%s\n',field{1},get_param(h,field{1}));
end
set_param(m,'SimulationCommand','update');
fprintf(fid,'FPGA_BRANCH_DRIVES_PLANT=0\nLEGACY_CONTROL_DRIVES_INVERTER=1\nMODEL_UPDATE=PASS\n');
fprintf('STEP7B_SIMPLE_STRUCTURE_PASS\n');
end
function localRestore(p,e,v)
cd(p); setenv('PATH',e); setenv('XILINX_VIVADO',v);
end
