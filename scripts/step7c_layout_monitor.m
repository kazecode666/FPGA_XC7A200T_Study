function step7c_layout_monitor
% Local layout only: newly added monitor/reference observation blocks.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'simulink模型'));
m='PMLSM_ThreeLoop_Simple'; load_system(m); c=onCleanup(@() close_system(m,0)); %#ok<NASGU>
s=[m '/Step7C_Monitor']; set_param(s,'Position',[2250 300 2450 1100]);
for k=1:25
    n=sprintf('Signal_%02d',k); y=40*k;
    set_param([s '/' n],'Position',[30 y 60 y+20]);
    set_param([s '/' n '_double'],'Position',[140 y-5 220 y+25]);
end
set_param([s '/Mux'],'Position',[330 35 335 1030]); set_param([s '/Log'],'Position',[440 510 570 550]);
f=[m '/FPGA_HDL_Cosim']; a=[f '/FPGA_Input_Adapter'];
set_param([a '/Monitor_id_ref'],'Position',[1600 1230 1630 1250]);
set_param([a '/Monitor_iq_ref'],'Position',[1600 1330 1630 1350]);
set_param([a '/Gate_Double'],'Position',[550 1450 620 1480]);
set_param([f '/Monitor_id_ref'],'Position',[1570 750 1600 770]);
set_param([f '/Monitor_iq_ref'],'Position',[1570 810 1600 830]);
i=[m '/Inverter_DeadTime'];
set_param([i '/Legacy_Counts_To_Duty'],'Position',[385 80 495 230]);
set_param([i '/Backend_Enable'],'Position',[930 560 1000 600]);
save_system(m); fprintf('STEP7C_LOCAL_MONITOR_LAYOUT_SAVED\n');
end
