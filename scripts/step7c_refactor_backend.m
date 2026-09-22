function step7c_refactor_backend
% One-time edit: ideal duty boundary, preserving approved deadtime ordering.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'simulink模型'));
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m)); load_system(m);
cm=onCleanup(@() close_system(m,0)); %#ok<NASGU>
evalin('base','init_PMLSM_fpga_cosim_params;');
i=[m '/Inverter_DeadTime']; p=[m '/FPGA_HDL_Cosim']; a=[i '/Legacy_Counts_To_Duty'];
assert(getSimulinkBlockHandle(a)<0,'Already refactored');
for b={[i '/PWM_Update_HalfTs'],[i '/DeadTime_Voltage_Model'],[p '/HDL_Cosimulation']}, assert(getSimulinkBlockHandle(b{1})>0); end
add_block('built-in/Subsystem',a,'Position',[270 40 440 180]);
for k=1:3
    phase=[i '/DeadTime_Voltage_Model/Phase_' char('A'+k-1) '_DeadTime'];
    assert(strcmp(get_param([phase '/duty_norm'],'Gain'),'-1/PMLSM_pwm_period_counts'));
    assert(strcmp(get_param([phase '/duty_active_high'],'Bias'),'1'));
    add_block([phase '/duty_norm'],[a '/Gain' num2str(k)],'Position',[90 60*k 200 60*k+25]);
    add_block([phase '/duty_active_high'],[a '/Bias' num2str(k)],'Position',[240 60*k 280 60*k+25]);
    port(a,['Count' num2str(k)],k,true,[20 60*k 50 60*k+20]);
    port(a,['Duty' num2str(k)],k,false,[340 60*k 370 60*k+20]);
    add_line(a,['Count' num2str(k) '/1'],['Gain' num2str(k) '/1']);
    add_line(a,['Gain' num2str(k) '/1'],['Bias' num2str(k) '/1']);
    add_line(a,['Bias' num2str(k) '/1'],['Duty' num2str(k) '/1']);
    delete_line(phase,'duty/1','duty_norm/1'); delete_line(phase,'duty_norm/1','duty_active_high/1');
    delete_line(phase,'duty_active_high/1','d_sum/1');
    delete_block([phase '/duty_norm']); delete_block([phase '/duty_active_high']);
    add_line(phase,'duty/1','d_sum/1');
    delete_line(i,['PWM_Update_HalfTs/' num2str(k)],['DeadTime_Voltage_Model/' num2str(k)]);
    add_line(i,['PWM_Update_HalfTs/' num2str(k)],['Legacy_Counts_To_Duty/' num2str(k)]);
    name=['fpga_duty_' char('u'+k-1)]; port(i,name,9+k,true,[20 430+50*k 50 450+50*k]);
    v=[i '/Backend_Duty_' num2str(k)]; variantSource(v,[530 60*k 600 60*k+35]);
    add_line(i,['Legacy_Counts_To_Duty/' num2str(k)],['Backend_Duty_' num2str(k) '/1']);
    add_line(i,[name '/1'],['Backend_Duty_' num2str(k) '/2']);
    add_line(i,['Backend_Duty_' num2str(k) '/1'],['DeadTime_Voltage_Model/' num2str(k)]);
end
port(i,'fpga_bridge_enable',13,true,[20 680 50 700]);
variantSource([i '/Backend_Enable'],[530 300 600 340]);
delete_line(i,'PWM_EN/1','vd_PWM_Enable/2'); delete_line(i,'PWM_EN/1','vq_PWM_Enable/2');
add_line(i,'PWM_EN/1','Backend_Enable/1'); add_line(i,'fpga_bridge_enable/1','Backend_Enable/2');
add_line(i,'Backend_Enable/1','vd_PWM_Enable/2'); add_line(i,'Backend_Enable/1','vq_PWM_Enable/2');
v=[p '/HDL_Backend_Variant']; add_block('simulink/Ports & Subsystems/Variant Subsystem',v,'Position',[540 50 840 490]);
Simulink.SubSystem.deleteContents(v);
on=[v '/FPGA_Enabled']; off=[v '/FPGA_Disabled'];
add_block('built-in/Subsystem',on,'VariantControl','V_Backend_FPGA','Position',[180 50 380 250]);
add_block('built-in/Subsystem',off,'VariantControl','V_Backend_Legacy','Position',[180 350 380 550]);
add_block([p '/HDL_Cosimulation'],[on '/HDL_Cosimulation'],'Position',[150 50 440 490]);
for k=1:11
    for parent={v,on,off}, port(parent{1},['In' num2str(k)],k,true,[20 40*k 50 40*k+20]); end
    add_line(on,['In' num2str(k) '/1'],['HDL_Cosimulation/' num2str(k)]);
    add_block('simulink/Sinks/Terminator',[off '/Unused' num2str(k)]);
    add_line(off,['In' num2str(k) '/1'],['Unused' num2str(k) '/1']);
    delete_line(p,['FPGA_Input_Adapter/' num2str(k)],['HDL_Cosimulation/' num2str(k)]);
    add_line(p,['FPGA_Input_Adapter/' num2str(k)],['HDL_Backend_Variant/' num2str(k)]);
end
for k=1:8
    for parent={v,on,off}, port(parent{1},['Out' num2str(k)],k,false,[520 40*k 550 40*k+20]); end
    add_line(on,['HDL_Cosimulation/' num2str(k)],['Out' num2str(k) '/1']);
    add_block('simulink/Sources/Constant',[off '/Zero' num2str(k)],'Value','0','Position',[200 40*k 230 40*k+20]);
    add_line(off,['Zero' num2str(k) '/1'],['Out' num2str(k) '/1']);
    delete_line(p,['HDL_Cosimulation/' num2str(k)],['FPGA_Output_Adapter/' num2str(k)]);
    add_line(p,['HDL_Backend_Variant/' num2str(k)],['FPGA_Output_Adapter/' num2str(k)]);
end
delete_block([p '/HDL_Cosimulation']);
names={'fpga_duty_u','fpga_duty_v','fpga_duty_w','fpga_bridge_enable','cmp_u_active','cmp_v_active','cmp_w_active','accepted_sample_id','active_command_id','active_valid','fault_code','needs_reset'};
for k=1:12, port(p,names{k},k,false,[1570 50*k 1600 50*k+20]); end
for k=1:3
    g=['Duty_Guard' num2str(k)]; add_block('simulink/Discontinuities/Saturation',[p '/' g],'LowerLimit','0','UpperLimit','1','Position',[1450 50*k 1510 50*k+20]);
    add_line(p,['FPGA_Output_Adapter/' num2str(8+k)],[g '/1']); add_line(p,[g '/1'],[names{k} '/1']);
end
add_block('simulink/Signal Routing/Mux',[p '/Bridge_Inputs'],'Inputs','4','Position',[1100 580 1105 720]);
add_block('simulink/User-Defined Functions/Fcn',[p '/Bridge_Valid'],'Expr','(u[1] != 0) && (u[2] != 0) && (u[3] == 0) && (u[4] == 0)','Position',[1200 620 1400 660]);
add_line(p,'PWM_EN/1','Bridge_Inputs/1'); add_line(p,'FPGA_Output_Adapter/6','Bridge_Inputs/2');
add_line(p,'FPGA_Output_Adapter/7','Bridge_Inputs/3'); add_line(p,'FPGA_Output_Adapter/8','Bridge_Inputs/4');
add_line(p,'Bridge_Inputs/1','Bridge_Valid/1'); add_line(p,'Bridge_Valid/1','fpga_bridge_enable/1');
map=[1 2 3 4 5 6 8 7];
for k=1:8, add_line(p,['FPGA_Output_Adapter/' num2str(map(k))],[names{4+k} '/1']); end
for k=1:4, add_line(m,['FPGA_HDL_Cosim/' num2str(k)],['Inverter_DeadTime/' num2str(9+k)],'autorouting','on'); end
save_system(m); fprintf('STEP7C_BACKEND_REFACTOR_SAVED\n');
end
function port(parent,name,index,input,pos)
if input, lib='simulink/Ports & Subsystems/In1'; else, lib='simulink/Ports & Subsystems/Out1'; end
add_block(lib,[parent '/' name],'Port',num2str(index),'Position',pos);
end
function variantSource(p,pos)
add_block('simulink/Signal Routing/Variant Source',p,'Position',pos,...
    'VariantControls',{'V_Backend_Legacy','V_Backend_FPGA'},'VariantActivationTime','update diagram');
end
