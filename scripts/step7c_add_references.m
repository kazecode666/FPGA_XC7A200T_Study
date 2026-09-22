function step7c_add_references
root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'simulink模型'));
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m)); load_system(m); c=onCleanup(@() close_system(m,0)); %#ok<NASGU>
a=[m '/FPGA_HDL_Cosim/FPGA_Input_Adapter']; assert(getSimulinkBlockHandle([a '/Reference_Mode'])<0);
add_block('simulink/Sources/Constant',[a '/Reference_Mode'],'Value','FPGA_Reference_Mode','Position',[30 1230 100 1260]);
for axis={'id','iq'}
    n=[axis{1} '_ref']; source(a,['Scripted_' n],['STEP7C_' n '_ts'],[200 1250+100*strcmp(axis{1},'iq') 350 1280+100*strcmp(axis{1},'iq')]);
    add_block('simulink/Signal Routing/Switch',[a '/Reference_' n],'Criteria','u2 ~= 0','Position',[440 1250+100*strcmp(axis{1},'iq') 480 1300+100*strcmp(axis{1},'iq')]);
    delete_line(a,['LiveDouble_' n '/1'],['Select_' n '/1']);
    add_line(a,['LiveDouble_' n '/1'],['Reference_' n '/1']); add_line(a,'Reference_Mode/1',['Reference_' n '/2']);
    add_line(a,['Scripted_' n '/1'],['Reference_' n '/3']); add_line(a,['Reference_' n '/1'],['Select_' n '/1']);
end
source(a,'Scripted_Run_Gate','STEP7C_run_gate_ts',[200 1450 350 1480]);
add_block('simulink/Logic and Bit Operations/Logical Operator',[a '/Live_Run_Gate'],'Operator','AND','Inputs','2','Position',[440 1450 480 1500]);
delete_line(a,'LiveDouble_run_enable/1','Select_run_enable/1');
add_line(a,'LiveDouble_run_enable/1','Live_Run_Gate/1'); add_line(a,'Scripted_Run_Gate/1','Live_Run_Gate/2');
add_line(a,'Live_Run_Gate/1','Select_run_enable/1');
% Type-match the switch's live and smoke data branches explicitly.
add_block('simulink/Signal Attributes/Data Type Conversion',[a '/Gate_Double'],'OutDataTypeStr','double');
delete_line(a,'Live_Run_Gate/1','Select_run_enable/1'); add_line(a,'Live_Run_Gate/1','Gate_Double/1'); add_line(a,'Gate_Double/1','Select_run_enable/1');
save_system(m); fprintf('STEP7C_REFERENCES_SAVED\n');
end
function source(a,n,var,pos)
add_block('simulink/Sources/From Workspace',[a '/' n],'VariableName',var,'Interpolate','off','OutputAfterFinalValue','Holding final value','SampleTime','FPGA_Cosim_Ts_s','Position',pos);
end
