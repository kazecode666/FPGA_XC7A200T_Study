function m2_apply_fixed_types
% 开发转换：保留可视化块/原PI记忆；仅替换不支持fixed的向量Fcn。
root=fileparts(fileparts(mfilename('fullpath')));m='PMLSM_FOC_FixedPoint';d=[m '/FOC_DUT'];assert(bdIsLoaded(m));assert(evalin('base','exist(''FOC_Fixed_Config'',''var'')==1'));
b=find_system(d,'LookUnderMasks','all','FollowLinks','off','BlockType','Fcn');for k=1:numel(b),expand_fcn(b{k});end
blocks=find_system(m,'LookUnderMasks','all','FollowLinks','off','Type','Block');
for k=1:numel(blocks)
 b=blocks{k};p=get_param(b,'DialogParameters');type=get_param(b,'BlockType');
 if isfield(p,'RndMeth'),set_param(b,'RndMeth','Convergent');end
 if isfield(p,'SaturateOnIntegerOverflow'),set_param(b,'SaturateOnIntegerOverflow','on');end
 if isfield(p,'OutDataTypeStr')&&~any(strcmp(type,{'SubSystem','Inport','Outport','RelationalOperator','Logic'})),set_param(b,'OutDataTypeStr','FOC_Fixed_Config.Types.Work');end
 if isfield(p,'AccumDataTypeStr'),set_param(b,'AccumDataTypeStr','FOC_Fixed_Config.Types.Work');end
 if strcmp(type,'Gain'),set_param(b,'ParamDataTypeStr','FOC_Fixed_Config.Types.Coefficient');end
 if strcmp(type,'Switch'),set_param(b,'InputSameDT','off');end
 if strcmp(type,'Math')&&strcmp(get_param(b,'Operator'),'square'),set_param(b,'OutDataTypeStr','FOC_Fixed_Config.Types.Square');end
end
% Quantized coefficients are supplied once by the unique initialization config.
expressions={'Kp_ACR','Ki_ACR*Ts_ACR','Kaw_d','Kaw_q','PMLSM_Ld_H','PMLSM_Lq_H','PMLSM_psi_f_Wb','Ts','0.9','0.999','1e-6','2/3','1/sqrt(3)','0.866','1.7321','-2/T_pwm'};
coefficientNames={'Kp','KiTs','Kaw_d','Kaw_q','Ld','Lq','psi','Ts','C09','C0999','Epsilon','TwoThird','InvSqrt3','C0866','C17321','DutyGain'};
expressions{end+1}='1/(sqrt(3))';coefficientNames{end+1}='InvSqrt3';
for k=1:numel(blocks),type=get_param(blocks{k},'BlockType');key='';if strcmp(type,'Gain'),key='Gain';elseif strcmp(type,'Constant'),key='Value';end;if isempty(key),continue;end;expression=get_param(blocks{k},key);index=find(strcmp(expressions,expression));if ~isempty(index),set_param(blocks{k},key,['FOC_Fixed_Config.Coefficients.' coefficientNames{index} '.quantized']);end;end
% Unsigned square/sum/sqrt, wide quotient before min(1), noepsilon loss.
lim=[d '/dq_voltage_limiter'];set_param([lim '/Add'],'OutDataTypeStr','FOC_Fixed_Config.Types.Square','AccumDataTypeStr','FOC_Fixed_Config.Types.Square');set_param([lim '/Divide'],'OutDataTypeStr','FOC_Fixed_Config.Types.DivideWide');set_param([lim '/Sqrt'],'RndMeth','Floor');
% Port types; inner subsystem inputs inherit true fixed types from root.
keys={'Current','Current','Current','Angle','Omega','Current','Current','Reset','Bus'};b=find_system(m,'SearchDepth',1,'BlockType','Inport');for k=1:numel(b),i=str2double(get_param(b{k},'Port'));if i==8,set_param(b{k},'OutDataTypeStr','boolean');else,set_param(b{k},'OutDataTypeStr',['FOC_Fixed_Config.Types.' keys{i}]);end;end
b=find_system(m,'SearchDepth',1,'BlockType','Outport');for k=1:numel(b),set_param(b{k},'OutDataTypeStr','FOC_Fixed_Config.Types.Duty');end
% Explicit unsigned command-duty encoding, no hidden outport type coercion.
b=find_system(d,'SearchDepth',1,'BlockType','Outport');for k=1:numel(b),i=get_param(b{k},'Port');path=[d '/Encode_Duty_' i];if getSimulinkBlockHandle(path)<0,q=get_param(b{k},'PortHandles');sp=get_param(get_param(q.Inport,'Line'),'SrcPortHandle');delete_line(d,sp,q.Inport);add_block('built-in/DataTypeConversion',path);p=get_param(path,'PortHandles');add_line(d,sp,p.Inport,'autorouting','on');add_line(d,p.Outport,q.Inport,'autorouting','on');end;set_param(path,'OutDataTypeStr','FOC_Fixed_Config.Types.Duty','RndMeth','Convergent','SaturateOnIntegerOverflow','on');end
% Actual selected sector explicitlyuint8; retain original sign boundaries/defaults.
svp=[d '/SVPWMG'];sector=find_system(svp,'SearchDepth',1,'Regexp','on','BlockType','SubSystem','Name','^Sector');assert(isscalar(sector));b=find_system(sector{1},'SearchDepth',1,'BlockType','Constant');for k=1:numel(b),set_param(b{k},'OutDataTypeStr','uint8');end
b=find_system(sector{1},'SearchDepth',1,'BlockType','Switch');for k=1:numel(b),set_param(b{k},'OutDataTypeStr','uint8');end
n=[sector{1} '/N'];b=find_system(n,'Type','Block');for k=1:numel(b),p=get_param(b{k},'DialogParameters');if isfield(p,'OutDataTypeStr'),set_param(b{k},'OutDataTypeStr','uint8');end;if isfield(p,'ParamDataTypeStr'),set_param(b{k},'ParamDataTypeStr','uint8');end;if isfield(p,'AccumDataTypeStr'),set_param(b{k},'AccumDataTypeStr','uint8');end;end
b=find_system(m,'SearchDepth',1,'BlockType','Inport');for k=1:numel(b),set_param(b{k},'SampleTime','-1');end;
set_param(m,'FixedStep','auto','SampleTimeConstraint','STIndependent','DataTypeOverride','Off','DefaultParameterBehavior','Inlined','IntegerOverflowMsg','error','IntegerSaturationMsg','error','ParameterOverflowMsg','error','FixptConstOverflowMsg','error');set_param(m,'SimulationCommand','update');save_system(m);disp('M2_FIXED_MODEL_SAVED');
end
function expand_fcn(old)
expr=get_param(old,'Expr');parent=get_param(old,'Parent');name=get_param(old,'Name');pos=get_param(old,'Position');p=get_param(old,'PortHandles');sp=get_param(get_param(p.Inport,'Line'),'SrcPortHandle');dest=get_param(get_param(p.Outport,'Line'),'DstPortHandle');delete_line(parent,sp,p.Inport);for dd=dest(:)',delete_line(parent,p.Outport,dd);end;delete_block(old);b=add_block('built-in/Subsystem',[parent '/' name],'Position',pos);b=getfullname(b);in=add_block('built-in/Inport',[b '/Vector']);count=3;if contains(expr,'0.866')||strcmp(expr,'u[2]'),count=2;end
split=add_block('built-in/Demux',[b '/Elements'],'Outputs',num2str(count));wire(b,in,1,split,1);
if strcmp(expr,'u[2]'),value=split;vi=2;
elseif contains(expr,'0.866')
 a=add_block('built-in/Gain',[b '/Alpha0866'],'Gain','0.866');bb=add_block('built-in/Gain',[b '/Beta05'],'Gain','0.5');wire(b,split,1,a,1);wire(b,split,2,bb,1);signs='+-';if startsWith(expr,'-'),signs='--';end;value=add_block('built-in/Sum',[b '/Projection'],'Inputs',signs);wire(b,a,1,value,1);wire(b,bb,1,value,2);vi=1;
elseif startsWith(expr,'4*')
 a=add_block('built-in/Gain',[b '/Four'],'Gain','4');bb=add_block('built-in/Gain',[b '/Two'],'Gain','2');wire(b,split,3,a,1);wire(b,split,2,bb,1);value=add_block('built-in/Sum',[b '/SectorNumber'],'Inputs','+++');wire(b,a,1,value,1);wire(b,bb,1,value,2);wire(b,split,1,value,3);vi=1;
else
 order=[3 1 2];signs='+--';if contains(expr,'u[3]+u[1]'),signs='++-';elseif contains(expr,'u[3]+u[2]'),signs='+++';order=[3 2 1];elseif contains(expr,'u(3)'),order=[3 2 1];end
 value=add_block('built-in/Sum',[b '/Combination'],'Inputs',signs);for k=1:3,wire(b,split,order(k),value,k);end;vi=1;if contains(expr,'/4'),g=add_block('built-in/Gain',[b '/Quarter'],'Gain','.25');wire(b,value,1,g,1);value=g;end
end
out=add_block('built-in/Outport',[b '/Value']);wire(b,value,vi,out,1);Simulink.BlockDiagram.arrangeSystem(b);p=get_param(b,'PortHandles');add_line(parent,sp,p.Inport,'autorouting','on');for dd=dest(:)',add_line(parent,p.Outport,dd,'autorouting','on');end
end
function wire(parent,a,ai,b,bi),p=get_param(a,'PortHandles');q=get_param(b,'PortHandles');add_line(parent,p.Outport(ai),q.Inport(bi),'autorouting','on');end
