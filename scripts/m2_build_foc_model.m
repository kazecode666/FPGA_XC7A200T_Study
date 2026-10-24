function m2_build_foc_model(outputDir)
% 开发重建：复制当前原FOC，仅新增母线边界及零分母前置保护。
root=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(root,'simulink模型'));if nargin==0,outputDir=fullfile(root,'simulink模型');end;source='PMLSM_PI_FOC_Float_Baseline';m='PMLSM_FOC_FixedPoint';assert(~bdIsLoaded(m)&&~isfile(fullfile(outputDir,[m '.slx'])),'M2:OUTPUT_EXISTS','重建不得覆盖已有实现。');open_system(fullfile(root,'simulink模型',[source '.slx']));src=Simulink.ID.getFullName([source ':546']);new_system(m);open_system(m);set_param(m,'SolverType','Fixed-step','Solver','FixedStepDiscrete','FixedStep','Ts_ACR','StopTime','.01','DataTypeOverride','Off','SignalLogging','on','ReturnWorkspaceOutputs','on');
dut=[m '/FOC_DUT'];add_block(src,dut,'Position',[300 100 600 680],'TreatAsAtomicUnit','on');
% Track exact copied SID correspondence before adaptation.
a=find_system(src,'LookUnderMasks','all','FollowLinks','off','Type','Block');map=struct;for k=1:numel(a),sid=get_param(a{k},'SID');if isempty(sid),continue;end;rel=extractAfter(a{k},strlength(src));b=[dut char(rel)];map.(['s' sid])=b;end
names={'ia','ib','ic','theta_e','omega_e','iq_ref','id_ref','PI_Reset_EN','Vdc_V'};
for k=1:9,b=add_block('built-in/Inport',[m '/' names{k}],'Port',num2str(k),'SampleTime','Ts_ACR','Position',[40 70*k 70 70*k+20]);if k==8,set_param(b,'OutDataTypeStr','boolean');end;if k<=8,wire(m,b,1,dut,k);end;end
outnames={'duty_u_cmd','duty_v_cmd','duty_w_cmd'};for k=1:3,b=add_block('built-in/Outport',[m '/' outnames{k}],'Port',num2str(k),'Position',[750 150*k 780 150*k+20]);wire(m,dut,k,b,1);end
v=add_block('built-in/Inport',[dut '/Vdc_V'],'Port','9','Position',[30 850 60 870]);
% Explicit same-sample bus input to both limiter and modulation.
for id=[702 673]
 old=map.(['s' num2str(id)]);parent=get_param(old,'Parent');pos=get_param(old,'Position');p=get_param(old,'PortHandles');dest=get_param(get_param(p.Outport,'Line'),'DstPortHandle');name=get_param(old,'Name');for d=dest,delete_line(parent,p.Outport,d);end;delete_block(old);
 ni=add_block('built-in/Inport',[parent '/' name],'Port','3','Position',pos);q=get_param(ni,'PortHandles');for d=dest,add_line(parent,q.Outport,d,'autorouting','on');end
 if id==702,g=add_block('built-in/Gain',[parent '/Bus_over_sqrt3'],'Gain','1/sqrt(3)','Position',[pos(3)+40 pos(2) pos(3)+100 pos(4)]);for d=dest,delete_line(parent,q.Outport,d);end;wire(parent,ni,1,g,1);gp=get_param(g,'PortHandles');for d=dest,add_line(parent,gp.Outport,d,'autorouting','on');end;end
 wire(dut,v,1,parent,3);
end
wire(m,[m '/Vdc_V'],1,dut,9);
for id=[661 662],replace_guarded(map.(['s' num2str(id)]),id==661);end
% Remove only copied observation flags; independent tests explicitly select their observations.
b=find_system(m,'LookUnderMasks','all','FollowLinks','off','Type','Block');for k=1:numel(b),p=get_param(b{k},'PortHandles');for port=p.Outport,set_param(port,'DataLogging','off');end;end
save_system(m,fullfile(outputDir,[m '.slx']));fid=fopen(fullfile(root,'.runtime/m2_20261024/extraction_map.json'),'w');fprintf(fid,'%s',jsonencode(map,PrettyPrint=true));fclose(fid);disp('M2_EXTRACTED_DOUBLE_SAVED');
end
function replace_guarded(old,first)
parent=get_param(old,'Parent');name=get_param(old,'Name');pos=get_param(old,'Position');p=get_param(old,'PortHandles');sp=get_param(get_param(p.Inport,'Line'),'SrcPortHandle');dest=get_param(get_param(p.Outport,'Line'),'DstPortHandle');delete_line(parent,sp,p.Inport);for d=dest,delete_line(parent,p.Outport,d);end;delete_block(old);new=add_block('built-in/Subsystem',[parent '/' name],'Position',pos);new=getfullname(new);
b=add_block('built-in/Inport',[new '/Vector'],'Position',[20 100 50 120]);dm=add_block('built-in/Demux',[new '/Times'],'Outputs','3','Position',[90 40 95 180]);wire(new,b,1,dm,1);
s=add_block('built-in/Sum',[new '/Sum_Times'],'Inputs','++','Position',[150 40 180 80]);wire(new,dm,1,s,1);wire(new,dm,2,s,2);
z=add_block('simulink/Logic and Bit Operations/Compare To Zero',[new '/Denominator_Nonzero'],'relop','~=');wire(new,s,1,z,1);
one=add_block('built-in/Constant',[new '/Defined_Fallback'],'Value','1');safe=add_block('built-in/Switch',[new '/Safe_Denominator'],'Criteria','u2 ~= 0');wire(new,s,1,safe,1);wire(new,z,1,safe,2);wire(new,one,1,safe,3);
prod=add_block('built-in/Product',[new '/Numerator'],'Inputs','**');wire(new,dm,3,prod,2);wire(new,dm,2-double(first),prod,1);div=add_block('built-in/Product',[new '/Defined_Quotient'],'Inputs','*/');wire(new,prod,1,div,1);wire(new,safe,1,div,2);out=add_block('built-in/Outport',[new '/Value']);wire(new,div,1,out,1);Simulink.BlockDiagram.arrangeSystem(new);
p=get_param(new,'PortHandles');add_line(parent,sp,p.Inport,'autorouting','on');for d=dest,add_line(parent,p.Outport,d,'autorouting','on');end
end
function wire(parent,a,ai,b,bi),p=get_param(a,'PortHandles');q=get_param(b,'PortHandles');add_line(parent,p.Outport(ai),q.Inport(bi),'autorouting','on');end
