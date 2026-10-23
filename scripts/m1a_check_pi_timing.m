function result=m1a_check_pi_timing(model)
% Numerical checks use copies of the saved PI/limiter blocks, not a rewrite.
root=fileparts(fileparts(mfilename('fullpath')));
evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');
byid=@(sid)Simulink.ID.getFullName(sprintf('%s:%d',model,sid));
h=sprintf('M1A_PI_%d',matlabProcessID); new_system(h);
cleanup=onCleanup(@()close_system(h,0));
add_block(byid(566),[h '/Id']); add_block(byid(591),[h '/Iq']);
add_block(byid(698),[h '/Limiter']);
references=[0 0;4 -5;4 -5;4 -5;-3 4;-3 4;2 -2;0 0;0.3 0.2;0 0];
reset=[0;0;0;0;1;0;0;1;0;0]; time=(0:numel(reset)-1)'*1e-4;
w=get_param(h,'ModelWorkspace');
inputs=[references,reset,zeros(numel(reset),1)];
for k=1:4
    name=sprintf('input_%d',k); w.assignin(name,timeseries(inputs(:,k),time));
    add_block('simulink/Sources/From Workspace',[h '/' name], ...
        'VariableName',name,'Interpolate','off','SampleTime','1e-4', ...
        'OutputAfterFinalValue','Holding final value');
end
wire(h,'input_1',1,'Id',1); wire(h,'input_2',1,'Iq',1);
for block={'Id','Iq'}
    for port=2:4,wire(h,'input_4',1,block{1},port);end
    wire(h,'input_3',1,block{1},6);
end
wire(h,'Limiter',3,'Id',5); wire(h,'Limiter',4,'Iq',5);
wire(h,'Id',1,'Limiter',1); wire(h,'Iq',1,'Limiter',2);
outputs={'Id',1;'Iq',1;'Limiter',1;'Limiter',2;'Limiter',3;'Limiter',4;'Limiter',5};
for k=1:size(outputs,1)
    name=sprintf('out_%d',k); add_block('simulink/Sinks/Out1',[h '/' name],'Port',num2str(k));
    wire(h,outputs{k,1},outputs{k,2},name,1);
end
for axis={'d','q'}
    if axis{1}=='d',scope='Id';else,scope='Iq';end
    state=find_system([h '/' scope],'SearchDepth',1,'BlockType','UnitDelay');
    p=get_param(state{1},'PortHandles');
    set_param(p.Outport,'DataLogging','on','DataLoggingNameMode','Custom', ...
        'DataLoggingName',['x_' axis{1}]);
end
set_param(h,'Solver','FixedStepDiscrete','FixedStep','1e-4','StopTime',num2str(time(end),17), ...
    'SaveOutput','on','OutputSaveName','yout','SaveFormat','Dataset','ReturnWorkspaceOutputs','on', ...
    'SignalLogging','on','SignalLoggingName','logsout');
data=sim(Simulink.SimulationInput(h));
actual=zeros(numel(reset),7);
for k=1:7,actual(:,k)=data.yout.getElement(k).Values.Data;end
states=[data.logsout.getElement('x_d').Values.Data data.logsout.getElement('x_q').Values.Data];
x=[0 0];du=[0 0];sat=0; expected=zeros(size(actual)); stateExpected=zeros(size(states));
kp=evalin('base','Kp_ACR');kiTs=evalin('base','Ki_ACR*Ts_ACR');
kaw=evalin('base','Kaw_d');limit=evalin('base','0.9*Udc/sqrt(3)');
for k=1:numel(reset)
    stateExpected(k,:)=x;
    raw=kp*references(k,:)+x;
    if reset(k),raw=[0 0];end
    scale=min(1,limit/(sqrt(sum(raw.^2))+1e-6)); limited=raw*scale;
    expected(k,:)=[raw limited du sat];
    x=x+kiTs*references(k,:)-kaw*du;
    if reset(k),x=[0 0];end
    du=raw-limited; sat=double(scale<0.999);
end
errorValues=max(abs(actual-expected),[],'all'); errorStates=max(abs(states-stateExpected),[],'all');
fprintf('M1A_PI_STATE output_error=%.17g state_error=%.17g\n',errorValues,errorStates);
assert(errorValues<1e-10 && errorStates<1e-10,'M1A:PI_STATE','Old-state PI/AW/reset numerical mismatch.');
clear cleanup

% Check actual saved periods, then measure scheduler events in a running model.
for sid=[207 208 232 234]
    expression=get_param(byid(sid),'SampleTime'); assert(slResolve(expression,byid(sid))==1e-6);
end
for sid=[871 876 879]
    assert(slResolve(get_param(byid(sid),'SampleTime'),byid(sid))==5e-5);
    assert(slResolve(get_param(byid(sid),'InitialCondition'),byid(sid))==0.5);
end
logged=[740 1;740 2;505 1;505 2;505 3;866 1;866 2;866 3;771 1;771 2];
labels={'speed_tick','position_tick','cmd_u','cmd_v','cmd_w','applied_u','applied_v','applied_w','vd_applied','vq_applied'};
for k=1:size(logged,1)
    p=get_param(byid(logged(k,1)),'PortHandles');
    set_param(p.Outport(logged(k,2)),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',labels{k});
end
input=Simulink.SimulationInput(model).setModelParameter('StopTime','0.011');
ticks=sim(input);
speed=ticks.logsout.getElement('speed_tick').Values;
position=ticks.logsout.getElement('position_tick').Values;
speedTimes=speed.Time(logical(speed.Data)); positionTimes=position.Time(logical(position.Data));
assert(abs(speedTimes(1)-0.0009)<1e-12 && abs(positionTimes(1)-0.0099)<1e-12, ...
    'M1A:FIRST_TICK','Unexpected first speed/position event.');
evalin('base','Host_Enable_Schedule=[0 0 0 1]; Host_Iq_Test_Mode=1; Host_Iq_A=0.2;');
evalin('base','M1A_PWM_ts=timeseries([1;0;0],[0;0.005;1.2]);');
update=sim(input);
command=update.logsout.getElement('cmd_v').Values;
applied=update.logsout.getElement('applied_v').Values;
firstCommand=command.Time(find(abs(command.Data-0.5)>1e-8,1));
firstApplied=applied.Time(find(abs(applied.Data-0.5)>1e-8,1));
assert(abs(firstApplied-firstCommand-5e-5)<1e-12,'M1A:PWM_DELAY','Expected one 50 us application delay.');
for axis={'vd_applied','vq_applied'}
    value=update.logsout.getElement(axis{1}).Values;
    assert(all(value.Data(value.Time>=0.005)==0),'M1A:PWM_DISABLE','PWM disable must prohibit average voltage.');
end
evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');
result=struct('pass',true,'details',struct('PI_output_max_error',errorValues,'PI_state_max_error',errorStates, ...
    'first_speed_tick_s',speedTimes(1),'first_position_tick_s',positionTimes(1), ...
    'first_command_s',firstCommand,'first_applied_s',firstApplied));
output=fullfile(root,'docs','reports','m1a_float_baseline','pi_timing_acceptance.json');
fid=fopen(output,'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
fprintf('M1A_PI_TIMING_PASS\n');
end
function wire(model,source,sourcePort,destination,destinationPort)
a=get_param([model '/' source],'PortHandles'); b=get_param([model '/' destination],'PortHandles');
add_line(model,a.Outport(sourcePort),b.Inport(destinationPort),'autorouting','on');
end
