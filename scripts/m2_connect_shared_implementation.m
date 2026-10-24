function m2_connect_shared_implementation
% 仅包裹原FOC作停止后选择；单一定点源经Model Reference接同一环境。
m='PMLSM_PI_FOC_Float_Baseline';evalin('base','clear init_PMLSM_PI_FOC_Float_Baseline;init_PMLSM_PI_FOC_Float_Baseline;');old=Simulink.ID.getFullName([m ':546']);original=get_param(old,'Position');control=get_param(old,'Parent');assert(strcmp(control,[m '/Control_Task_10kHz']));
Simulink.BlockDiagram.createSubsystem(get_param(old,'Handle'),'Name','FOC_Implementation');wrapper=[control '/FOC_Implementation'];
% Ninth bus is unused by the original reference, whose eight ports/math remain intact.
bus=add_block('built-in/Inport',[wrapper '/Vdc_V'],'Port','9');t=add_block('built-in/Terminator',[wrapper '/Original_Udc_Base_Reference']);wire(wrapper,bus,1,t,1);
source=add_block('built-in/Constant',[control '/FOC_Bus_V'],'Value','Udc','SampleTime','-1','Position',[1450 1350 1540 1370]);wire(control,source,1,wrapper,9);
handle=Simulink.VariantUtils.convertToVariantSubsystem(get_param(wrapper,'Handle'),'VariantControlMode','expression','VariantControl','FOC_Impl_Select == 0','VariantActivationTime','update diagram');wrapper=getfullname(handle);float=[wrapper '/FOC_Implementation'];set_param(float,'Name','Float');float=[wrapper '/Float'];
fixed=add_block('built-in/Subsystem',[wrapper '/Fixed']);fixed=getfullname(fixed);keys={'Current','Current','Current','Angle','Omega','Current','Current','Reset','Bus'};names={'ia','ib','ic','theta_e','omega_e','iq_ref','id_ref','PI_Reset_EN','Vdc_V'};
ref=add_block('built-in/ModelReference',[fixed '/FOC_Model'],'ModelName','PMLSM_FOC_FixedPoint','SimulationMode','Normal');
for k=1:9
 b=add_block('built-in/Inport',[fixed '/' names{k}],'Port',num2str(k));dt=['FOC_Fixed_Config.Types.' keys{k}];if k==8,dt='boolean';end
 cv=add_block('built-in/DataTypeConversion',sprintf('%s/Encode_%s',fixed,names{k}),'OutDataTypeStr',dt,'RndMeth','Convergent','SaturateOnIntegerOverflow','on');wire(fixed,b,1,cv,1);wire(fixed,cv,1,ref,k);
end
outnames={'duty_u_cmd','duty_v_cmd','duty_w_cmd'};for k=1:3,cv=add_block('built-in/DataTypeConversion',sprintf('%s/Decode_Duty%d',fixed,k),'OutDataTypeStr','double');b=add_block('built-in/Outport',[fixed '/' outnames{k}],'Port',num2str(k));wire(fixed,ref,k,cv,1);wire(fixed,cv,1,b,1);end
% Variant selection compiles exactly one algorithm, no running hot-switch.
% Variant interfaces match by names; Variant Subsystem has no editable internal wires.
set_param(float,'VariantControl','FOC_Impl_Select == 0');set_param(fixed,'VariantControl','FOC_Impl_Select == 1');set_param(wrapper,'Position',original);
Simulink.BlockDiagram.arrangeSystem(fixed);Simulink.BlockDiagram.arrangeSystem(wrapper);set_param(wrapper,'Position',original);set_param(m,'SimulationCommand','update');save_system(m);disp('M2_SHARED_FLOAT_UPDATED');
assignin('base','FOC_Impl_Select',1);set_param(m,'SimulationCommand','update');disp('M2_SHARED_FIXED_UPDATED');assignin('base','FOC_Impl_Select',0);
end
function wire(parent,a,ai,b,bi),p=get_param(a,'PortHandles');q=get_param(b,'PortHandles');add_line(parent,p.Outport(ai),q.Inport(bi),'autorouting','on');end
