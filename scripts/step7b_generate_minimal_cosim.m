function step7b_generate_minimal_cosim(rebuild,saveModel)
if nargin==0, rebuild=true; end
if nargin<2, saveModel=true; end
root=fileparts(fileparts(mfilename('fullpath')));
assert(strcmp(version('-release'),'2026b'));
oldpwd=pwd; oldpath=getenv('PATH'); oldvivado=getenv('XILINX_VIVADO');
cleanup=onCleanup(@() localRestore(oldpwd,oldpath,oldvivado)); %#ok<NASGU>
hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');
work=fullfile(root,'.Xil','step7b_minimal_cosim');
if ~isfolder(work), mkdir(work); end
cd(work);
c=cosimulationConfiguration('Vivado Simulator','Simulink','step7b_counter');
c.HDLFiles={fullfile(root,'motor_control_ip','integration','tb','cosim','step7b_counter.sv'),'Verilog'};
c.HDLSimulatorPath='E:/AMDDesignTools/2026.1/Vivado/bin';
c.HDLTimeUnit='ns'; c.AutoTimeScale=false; c.TimeScale={1,'s'};
specifyClock(c,'clk','Period',20,'Edge','Rising');
specifyReset(c,'reset_n','InitialValue',0,'Duration',200);
specifyOutput(c,'out_data','SampleTime',1e-6);
if rebuild, runWorkflow(c); end
if ~saveModel
    if bdIsLoaded('hdlverifier_wizard_step7b_counter'), close_system('hdlverifier_wizard_step7b_counter',0); end
    fprintf('STEP7B_MINIMAL_RUNTIME_ONLY_GENERATED\n'); return;
end
generated='hdlverifier_wizard_step7b_counter';
load_system(fullfile(work,[generated '.slx']));
b=find_system(generated,'SearchDepth',1,'ReferenceBlock','vivadosimlib/HDL Cosimulation');
assert(numel(b)==1,'Expected exactly one generated Vivado block');
mdl='PMLSM_HDL_Cosim_Minimal';
assert(~bdIsLoaded(mdl),'Close the minimal model before regenerating');
new_system(mdl);
add_block(b{1},[mdl '/HDL_Cosimulation'],'Position',[220 75 410 175]);
set_param([mdl '/HDL_Cosimulation'],'PreRunTime','0');
add_block('simulink/Sources/Constant',[mdl '/Input'],'Value','42','OutDataTypeStr','uint8','SampleTime','1e-6','Position',[40 100 100 130]);
add_block('simulink/Sinks/To Workspace',[mdl '/HDL_Output'],'VariableName','hdl_output','SaveFormat','Timeseries','Position',[485 100 610 130]);
add_line(mdl,'Input/1','HDL_Cosimulation/1'); add_line(mdl,'HDL_Cosimulation/1','HDL_Output/1');
set_param(mdl,'SolverType','Fixed-step','Solver','FixedStepDiscrete','FixedStep','1e-6','StopTime','5e-6','ReturnWorkspaceOutputs','on');
save_system(mdl,fullfile(root,'simulink模型',[mdl '.slx']));
fprintf('BLOCK_TIMESCALE=%s %s\n',get_param([mdl '/HDL_Cosimulation'],'TimingScaleFactor'),get_param([mdl '/HDL_Cosimulation'],'TimingMode'));
fprintf('BLOCK_CLOCKS=%s\n',get_param([mdl '/HDL_Cosimulation'],'ClockTimes'));
disp(get_param([mdl '/HDL_Cosimulation'],'UserData'));
close_system(mdl,0); close_system(generated,0);
fprintf('MINIMAL_GENERATION_COMPLETE\n');
end
function localRestore(p,e,v)
cd(p); setenv('PATH',e); setenv('XILINX_VIVADO',v);
end
