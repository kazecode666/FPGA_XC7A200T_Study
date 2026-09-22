function step7c_add_monitor
root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'simulink模型'));
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m)); load_system(m); c=onCleanup(@() close_system(m,0)); %#ok<NASGU>
s=[m '/Step7C_Monitor']; assert(getSimulinkBlockHandle(s)<0);
add_block('built-in/Subsystem',s,'Position',[1450 650 1650 1050]);
add_block('simulink/Signal Routing/Mux',[s '/Mux'],'Inputs','25');
add_block('simulink/Sinks/To Workspace',[s '/Log'],'VariableName','step7c_monitor','SaveFormat','Timeseries'); add_line(s,'Mux/1','Log/1');
% Expose reference observations only; they do not drive any control block.
f=[m '/FPGA_HDL_Cosim']; a=[f '/FPGA_Input_Adapter'];
for k=1:2
    names={'id_ref','iq_ref'}; n=names{k};
    add_block('built-in/Outport',[a '/Monitor_' n],'Port',num2str(12+k)); add_line(a,['Reference_' n '/1'],['Monitor_' n '/1']);
    add_block('built-in/Outport',[f '/Monitor_' n],'Port',num2str(12+k)); add_line(f,['FPGA_Input_Adapter/' num2str(12+k)],['Monitor_' n '/1']);
end
sources=[{f,13;f,14};repmat({[m '/PMLSM_Plant_Model'],0},9,1);repmat({f,0},12,1);{[m '/Inverter_DeadTime'],1;[m '/Inverter_DeadTime'],2}];
for k=1:9, sources{k+2,2}=k; end
ports=[5 6 7 1 2 3 8 9 10 4 11 12]; for k=1:12, sources{k+11,2}=ports(k); end
for k=1:25
    n=sprintf('Signal_%02d',k); add_block('built-in/Inport',[s '/' n],'Port',num2str(k));
    add_block('simulink/Signal Attributes/Data Type Conversion',[s '/' n '_double'],'OutDataTypeStr','double');
    add_line(s,[n '/1'],[n '_double/1']); add_line(s,[n '_double/1'],['Mux/' num2str(k)]);
    p=get_param(sources{k,1},'PortHandles'); q=get_param(s,'PortHandles'); add_line(m,p.Outport(sources{k,2}),q.Inport(k),'autorouting','on');
end
save_system(m); fprintf('STEP7C_MONITOR_SAVED\n');
end
