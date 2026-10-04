function study_l1_build_pi(model,mode,p)
% Independently constructed PI graph from audited SIDs; no source copying.
new_system(model);
set_param(model,'Solver','FixedStepDiscrete','FixedStep',num2str(p.Ts,17), ...
    'StopTime','0.01','SignalLogging','on','SignalLoggingName','logsout');
mw=get_param(model,'ModelWorkspace');
for name=string(fieldnames(p))', mw.assignin(char(name),p.(name)); end
s=[model '/PI']; add_block('built-in/SubSystem',s,'Position',[235 100 460 345]);
inputs={'v_ref_mmps','v_meas_mmps','enable','reset','sample_tick','angle_init','test_mode'};
for k=1:numel(inputs)
    add_block('built-in/Inport',[model '/' inputs{k}],'Port',num2str(k),'Position',[25 35+45*k 55 49+45*k]);
    if k~=5
        port=k-(k>5);
        block('Inport',inputs{k},[20 20+port*70 50 34+port*70],'Port',num2str(port));
        add_line(model,[inputs{k} '/1'],['PI/' num2str(port)]);
    end
end
block('TriggerPort','Tick',[170 15 190 35],'TriggerType','rising');
add_line(model,'sample_tick/1','PI/Trigger');
t=study_l1_types(mode);
block('DataTypeConversion','Ref',[85 75 130 105],'OutDataTypeStr',t.input);
block('DataTypeConversion','Meas',[85 150 130 180],'OutDataTypeStr',t.input);
block('Sum','Error',[170 95 205 140],'Inputs','+-','OutDataTypeStr',t.error,'AccumDataTypeStr',t.error);
block('Gain','P',[265 55 325 85],'Gain','Kp_ASR','ParamDataTypeStr',t.coeff,'OutDataTypeStr',t.work);
block('Gain','KiTs',[265 165 325 195],'Gain','Ki_ASR*Ts_ASR','ParamDataTypeStr',t.coeff,'OutDataTypeStr',t.work);
block('UnitDelay','Integrator',[440 310 480 340],'InitialCondition','0','SampleTime','-1');
block('UnitDelay','PreviousExcess',[930 420 970 450],'InitialCondition','0','SampleTime','-1');
block('Gain','AW',[995 420 1050 450],'Gain','Kaw_s','ParamDataTypeStr',t.coeff,'OutDataTypeStr',t.work);
block('Sum','Unlimited',[540 70 575 125],'Inputs','++','OutDataTypeStr',t.sum,'AccumDataTypeStr',t.acc);
block('Saturate','OutputLimit',[625 75 685 115],'UpperLimit','Speed_loop_Iq_Limit','LowerLimit','-Speed_loop_Iq_Limit');
block('DataTypeConversion','OutputFormat',[710 75 760 115],'OutDataTypeStr',t.output);
block('Sum','Excess',[775 190 810 240],'Inputs','+-','OutDataTypeStr',t.work,'AccumDataTypeStr',t.acc);
block('Sum','Update',[550 320 585 380],'Inputs','++-','OutDataTypeStr',t.acc,'AccumDataTypeStr',t.acc);
block('Saturate','IntegratorLimit',[625 320 685 360],'UpperLimit','Iq_int_limit','LowerLimit','-Iq_int_limit');
block('DataTypeConversion','StateFormat',[710 320 760 360],'OutDataTypeStr',t.state);
block('Constant','StateZero',[650 260 690 285],'Value','0','OutDataTypeStr',t.state);
block('Switch','IntReset',[810 310 855 370],'Criteria','u2 > Threshold','Threshold','0.5');
block('Constant','OutputZero',[790 15 825 40],'Value','0','OutDataTypeStr',t.output);
block('Switch','HardReset',[865 65 910 125],'Criteria','u2 > Threshold','Threshold','0.5');
% Exact reset manager: hard=angle|PIreset|test|~enable;
% int=hard | (abs(ref)<zero_eps) | (abs(ref)>ff_eps & sign(ref)*error<-over_eps).
block('Logic','Disabled',[165 600 205 630],'Operator','NOT');
block('Logic','Hard',[320 525 360 625],'Operator','OR','Inputs','4');
block('Abs','AbsRef',[165 700 205 730]);
block('RelationalOperator','RefZero',[270 670 310 710],'Operator','<');
block('RelationalOperator','RefMoving',[270 730 310 770],'Operator','>');
block('Constant','ZeroEps',[170 650 220 675],'Value','v_ref_zero_eps','OutDataTypeStr',t.input);
block('Constant','FFEps',[170 770 220 795],'Value','v_ff_eps','OutDataTypeStr',t.input);
block('Signum','RefSign',[170 830 210 860]);
block('Product','SignedError',[270 820 310 875],'OutDataTypeStr',t.error);
block('Constant','OverEps',[270 900 320 925],'Value','-v_over_eps','OutDataTypeStr',t.error);
block('RelationalOperator','OverSpeed',[370 825 410 875],'Operator','<');
block('Logic','Over',[455 745 495 790],'Operator','AND','Inputs','2');
block('Logic','Int',[550 620 590 700],'Operator','OR','Inputs','3');
block('RelationalOperator','Saturated',[870 200 915 235],'Operator','~=');
w('v_ref_mmps/1','Ref/1'); w('v_meas_mmps/1','Meas/1');
w('Ref/1','Error/1'); w('Meas/1','Error/2');
w('Error/1','P/1'); w('Error/1','KiTs/1');
w('P/1','Unlimited/1'); w('Integrator/1','Unlimited/2');
w('Unlimited/1','OutputLimit/1'); w('OutputLimit/1','OutputFormat/1');
w('Unlimited/1','Excess/1'); w('OutputLimit/1','Excess/2');
w('Excess/1','PreviousExcess/1'); w('PreviousExcess/1','AW/1');
w('Integrator/1','Update/1'); w('KiTs/1','Update/2'); w('AW/1','Update/3');
w('Update/1','IntegratorLimit/1'); w('IntegratorLimit/1','StateFormat/1');
w('StateZero/1','IntReset/1'); w('Int/1','IntReset/2'); w('StateFormat/1','IntReset/3');
w('IntReset/1','Integrator/1'); w('OutputZero/1','HardReset/1');
w('Hard/1','HardReset/2'); w('OutputFormat/1','HardReset/3');
w('enable/1','Disabled/1'); w('angle_init/1','Hard/1'); w('reset/1','Hard/2');
w('test_mode/1','Hard/3'); w('Disabled/1','Hard/4');
w('Ref/1','AbsRef/1'); w('AbsRef/1','RefZero/1'); w('ZeroEps/1','RefZero/2');
w('AbsRef/1','RefMoving/1'); w('FFEps/1','RefMoving/2');
w('Ref/1','RefSign/1'); w('RefSign/1','SignedError/1'); w('Error/1','SignedError/2');
w('SignedError/1','OverSpeed/1'); w('OverEps/1','OverSpeed/2');
w('RefMoving/1','Over/1'); w('OverSpeed/1','Over/2');
w('Hard/1','Int/1'); w('RefZero/1','Int/2'); w('Over/1','Int/3');
w('Unlimited/1','Saturated/1'); w('OutputLimit/1','Saturated/2');
names={'iq_ref_A','iq_unlimited_A','integrator_A','saturation_active','integrator_next_A', ...
    'previous_excess_A','excess_next_A','hard_reset','int_reset','iq_limited_A','error_mmps','P_A','KiTs_A','AW_A'};
sources={'HardReset','Unlimited','Integrator','Saturated','IntReset','PreviousExcess','Excess','Hard','Int','OutputLimit','Error','P','KiTs','AW'};
for k=1:numel(names)
    block('Outport',names{k},[1120 30+55*k 1150 44+55*k],'Port',num2str(k));
    w([sources{k} '/1'],[names{k} '/1']);
    add_block('built-in/Outport',[model '/' names{k}],'Port',num2str(k),'Position',[535 20+38*k 565 34+38*k]);
    add_line(model,['PI/' num2str(k)],[names{k} '/1']);
end
    function block(type,name,pos,varargin)
        b=add_block(['built-in/' type],[s '/' name],'Position',pos,varargin{:});
        params=get_param(b,'ObjectParameters');
        if isfield(params,'RndMeth'), set_param(b,'RndMeth','Convergent'); end
        if isfield(params,'SaturateOnIntegerOverflow'), set_param(b,'SaturateOnIntegerOverflow','on'); end
        if isfield(params,'InputSameDT'), set_param(b,'InputSameDT','off'); end
        if strcmp(type,'Logic'), set_param(b,'AllPortsSameDT','off','OutDataTypeStr','boolean'); end
    end
    function w(a,b)
        add_line(s,a,b,'autorouting','on');
    end
end
