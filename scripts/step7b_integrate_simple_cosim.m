function step7b_integrate_simple_cosim
% Add one parallel monitor branch. Refuse to overwrite an existing branch.
root=fileparts(fileparts(mfilename('fullpath')));
assert(strcmp(version('-release'),'2026b'));
addpath(fullfile(root,'simulink模型'));
m='PMLSM_ThreeLoop_Simple';
assert(~bdIsLoaded(m),'Close the Simple model before integration');
load_system(m); cleanup=onCleanup(@() close_system(m,0)); %#ok<NASGU>
for s={'Simple_Host','Control_Task_10kHz','Inverter_DeadTime','PMLSM_Plant_Model'}
    assert(getSimulinkBlockHandle([m '/' s{1}])>0);
end
p=[m '/FPGA_HDL_Cosim'];
assert(getSimulinkBlockHandle(p)<0,'FPGA branch already exists');
before=legacyConnections(m);
tags={'PWM_EN','ia','ib','ic','theta','we','id_cmd','iq_cmd','vdc','PI_Reset'};
for k=1:numel(tags)
    g=find_system(m,'SearchDepth',1,'BlockType','Goto','GotoTag',tags{k});
    assert(numel(g)==1,'Missing or ambiguous live tag %s',tags{k});
end
generated='hdlverifier_wizard_mc_foc_cosim_top';
load_system(fullfile(root,'.Xil','step7b_foc_cosim',[generated '.slx']));
cg=onCleanup(@() close_system(generated,0)); %#ok<NASGU>
b=find_system(generated,'SearchDepth',1,'ReferenceBlock','vivadosimlib/HDL Cosimulation');
assert(numel(b)==1);
% PreLoad supplies defaults once; SimulationInput may override for each run.
assert(isempty(get_param(m,'PreLoadFcn')),'Unexpected existing PreLoadFcn');
set_param(m,'PreLoadFcn','init_PMLSM_fpga_cosim_params;');
evalin('base','init_PMLSM_fpga_cosim_params;');
subsystem(p,[1800 1200 2100 1570]);
subsystem([p '/FPGA_Input_Adapter'],[180 50 430 490]);
a=[p '/FPGA_Input_Adapter'];
for k=1:numel(tags)
    add_block('simulink/Signal Routing/From',[m '/FPGA_Live_' tags{k}],...
        'GotoTag',tags{k},'Position',[1530 1190+40*k 1640 1210+40*k]);
    add_block('simulink/Ports & Subsystems/In1',[p '/' tags{k}],...
        'Port',num2str(k),'Position',[20 25+40*k 50 45+40*k]);
    add_block('simulink/Ports & Subsystems/In1',[a '/' tags{k}],...
        'Port',num2str(k),'Position',[20 25+100*k 50 45+100*k]);
    add_line(m,['FPGA_Live_' tags{k} '/1'],['FPGA_HDL_Cosim/' num2str(k)]);
    add_line(p,[tags{k} '/1'],['FPGA_Input_Adapter/' num2str(k)]);
end
names={'run_enable','ia','ib','ic','theta_e','we','id_ref','iq_ref','vdc','pi_reset','uq_zero_en'};
values={'1','FPGA_Smoke_ia_A','FPGA_Smoke_ib_A','FPGA_Smoke_ic_A','FPGA_Smoke_theta_rad',...
    'FPGA_Smoke_we_radps','FPGA_Smoke_id_ref_A','FPGA_Smoke_iq_ref_A','FPGA_Smoke_vdc_V','0','0'};
types={'boolean','fixdt(1,24,15)','fixdt(1,24,15)','fixdt(1,24,15)','fixdt(0,16,0)',...
    'fixdt(1,32,16)','fixdt(1,25,15)','fixdt(1,25,15)','fixdt(1,25,15)','boolean','boolean'};
limits=[0 1;-256 256-2^-15;-256 256-2^-15;-256 256-2^-15;0 65535;...
    -32768 32768-2^-16;-512 512-2^-15;-512 512-2^-15;-512 512-2^-15;0 1;0 1];
add_block('simulink/Sources/Constant',[a '/Mode'],'Value','FPGA_Cosim_Input_Mode','Position',[90 10 140 35]);
add_block('simulink/Sources/Constant',[a '/Enable'],'Value','FPGA_Cosim_Enable','Position',[480 30 540 50]);
add_block('simulink/Signal Routing/Mux',[a '/Saturation_Flags'],'Inputs','11','Position',[1070 130 1075 1160]);
for k=1:numel(names)
    n=names{k}; y=100*k;
    add_block('simulink/Sources/Constant',[a '/Smoke_' n],'Value',values{k},...
        'SampleTime','FPGA_Cosim_Ts_s','Position',[90 y+50 170 y+75]);
    add_block('simulink/Signal Routing/Switch',[a '/Select_' n],'Criteria','u2 ~= 0',...
        'Position',[260 y+20 300 y+70]);
    if k<=10
        add_block('simulink/Signal Attributes/Data Type Conversion',[a '/LiveDouble_' n],...
            'OutDataTypeStr','double','Position',[90 y+15 170 y+35]);
        add_line(a,[tags{k} '/1'],['LiveDouble_' n '/1']);
        add_line(a,['LiveDouble_' n '/1'],['Select_' n '/1']);
    else
        add_line(a,['Smoke_' n '/1'],['Select_' n '/1']);
    end
    add_line(a,'Mode/1',['Select_' n '/2']);
    add_line(a,['Smoke_' n '/1'],['Select_' n '/3']);
    src=['Select_' n '/1'];
    if k==1
        add_block('simulink/Logic and Bit Operations/Logical Operator',[a '/Enabled'],'Operator','AND','Inputs','2','Position',[480 y+20 520 y+65]);
        add_line(a,src,'Enabled/1'); add_line(a,'Enable/1','Enabled/2'); src='Enabled/1';
    elseif k==5
        add_block('simulink/User-Defined Functions/MATLAB Function',[a '/ThetaToU16'],'Position',[440 y+20 550 y+70]);
        rt=sfroot; chart=rt.find('-isa','Stateflow.EMChart','Path',[a '/ThetaToU16']);
        chart.Script=sprintf('function y = theta_to_u16(theta)\nt=mod(theta,2*pi);\nn=floor(t*65536/(2*pi)+0.5);\nif n>=65536, n=0; end\ny=uint16(n);\nend\n');
        add_line(a,src,'ThetaToU16/1'); src='ThetaToU16/1';
    end
    add_block('simulink/Signal Attributes/Data Type Conversion',[a '/Quantize_' n],...
        'OutDataTypeStr',types{k},'RndMeth','Nearest','SaturateOnIntegerOverflow','on','Position',[670 y+20 810 y+65]);
    add_block('simulink/Ports & Subsystems/Out1',[a '/' n '_HDL'],'Port',num2str(k),'Position',[900 y+30 930 y+50]);
    add_line(a,src,['Quantize_' n '/1']); add_line(a,['Quantize_' n '/1'],[n '_HDL/1']);
    % Log range overflow prior to conversion (theta is wrapped, never saturated).
    add_block('simulink/User-Defined Functions/Fcn',[a '/Range_' n],...
        'Expr',sprintf('(u < %.17g) || (u > %.17g)',limits(k,1),limits(k,2)),...
        'Position',[670 y+75 860 y+95]);
    add_block('simulink/Signal Attributes/Data Type Conversion',[a '/RangeDouble_' n],...
        'OutDataTypeStr','double','Position',[560 y+75 630 y+95]);
    add_line(a,src,['RangeDouble_' n '/1']); add_line(a,['RangeDouble_' n '/1'],['Range_' n '/1']);
    add_line(a,['Range_' n '/1'],['Saturation_Flags/' num2str(k)]);
end
add_block('simulink/Ports & Subsystems/Out1',[a '/Saturation'],'Port','12','Position',[1140 630 1170 650]);
add_line(a,'Saturation_Flags/1','Saturation/1');
add_block(b{1},[p '/HDL_Cosimulation'],'Position',[540 50 840 490]);
h=[p '/HDL_Cosimulation']; set_param(h,'PreRunTime','0');
paths=split(string(get_param(h,'PortPaths')),';'); modes=str2num(get_param(h,'PortModes')); %#ok<ST2NM>
fprintf('HDL_PORT_PATHS=%s\nHDL_PORT_MODES=%s\n',get_param(h,'PortPaths'),get_param(h,'PortModes'));
inpaths=paths(modes==1); outpaths=paths(modes==2);
for k=1:numel(names)
    port=find(endsWith(inpaths,"/"+names{k})); assert(isscalar(port),'HDL input mapping');
    add_line(p,['FPGA_Input_Adapter/' num2str(k)],['HDL_Cosimulation/' num2str(port)]);
end
outputs={'cmp_u_active','cmp_v_active','cmp_w_active','accepted_sample_id','active_command_id','active_valid','needs_reset','fault_code'};
subsystem([p '/FPGA_Output_Adapter'],[930 50 1140 440]);
o=[p '/FPGA_Output_Adapter'];
for k=1:numel(outputs)
    port=find(endsWith(outpaths,"/"+outputs{k})); assert(isscalar(port),'HDL output mapping');
    add_block('simulink/Ports & Subsystems/In1',[o '/' outputs{k}],'Port',num2str(k),'Position',[20 50*k 50 50*k+20]);
    add_block('simulink/Signal Attributes/Data Type Conversion',[o '/Double_' outputs{k}],'OutDataTypeStr','double','Position',[100 50*k 200 50*k+20]);
    add_block('simulink/Ports & Subsystems/Out1',[o '/Raw_' outputs{k}],'Port',num2str(k),'Position',[380 50*k 410 50*k+20]);
    add_line(o,[outputs{k} '/1'],['Double_' outputs{k} '/1']); add_line(o,['Double_' outputs{k} '/1'],['Raw_' outputs{k} '/1']);
    add_line(p,['HDL_Cosimulation/' num2str(port)],['FPGA_Output_Adapter/' num2str(k)]);
    if k<=3
        add_block('simulink/Math Operations/Gain',[o '/Duty_' num2str(k)],'Gain','1/FPGA_TBPRD','Position',[250 450+50*k 320 470+50*k]);
        add_block('simulink/Ports & Subsystems/Out1',[o '/DutyOut_' num2str(k)],'Port',num2str(8+k),'Position',[380 450+50*k 410 470+50*k]);
        add_line(o,['Double_' outputs{k} '/1'],['Duty_' num2str(k) '/1']); add_line(o,['Duty_' num2str(k) '/1'],['DutyOut_' num2str(k) '/1']);
    end
end
subsystem([p '/FPGA_Cosim_Monitor'],[1220 50 1430 490]); mon=[p '/FPGA_Cosim_Monitor'];
add_block('simulink/Signal Routing/Mux',[mon '/Pack'],'Inputs','12','Position',[200 45 205 650]);
for k=1:12
    add_block('simulink/Ports & Subsystems/In1',[mon '/In' num2str(k)],'Port',num2str(k),'Position',[30 50*k 60 50*k+20]);
    add_line(mon,['In' num2str(k) '/1'],['Pack/' num2str(k)]);
    if k<=11, src=['FPGA_Output_Adapter/' num2str(k)]; else, src='FPGA_Input_Adapter/12'; end
    add_line(p,src,['FPGA_Cosim_Monitor/' num2str(k)]);
end
add_block('simulink/Sinks/To Workspace',[mon '/Log'],'VariableName','fpga_monitor','SaveFormat','Timeseries','Position',[270 310 380 350]);
add_line(mon,'Pack/1','Log/1');
assert(isequal(before,legacyConnections(m)),'Legacy main-chain connectivity changed');
save_system(m,fullfile(root,'simulink模型',[m '.slx']));
fprintf('STEP7B_SIMPLE_INTEGRATION_SAVED\n');
end
function subsystem(p,pos)
add_block('built-in/Subsystem',p,'Position',pos);
end
function lines=legacyConnections(m)
lines={};
for s={'Control_Task_10kHz','Inverter_DeadTime','PMLSM_Plant_Model'}
    ports=get_param([m '/' s{1}],'PortHandles');
    for h=ports.Inport
        line=get_param(h,'Line');
        if line>0, src=get_param(line,'SrcPortHandle'); lines{end+1}=sprintf('%s:%d -> %s:%d',get_param(src,'Parent'),get_param(src,'PortNumber'),get_param(h,'Parent'),get_param(h,'PortNumber')); end %#ok<AGROW>
    end
end
lines=sort(lines);
end
