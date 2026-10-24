function result=m3_measure_pwm_phase(cfg,folder)
% 仅后台副本；读取真实控制、100us ZOH和50us delay的事件。
m='PMLSM_PI_FOC_Float_Baseline';load_system(fullfile(folder,[m '.slx']));
assert(strcmpi(get_param(m,'FileName'),fullfile(folder,[m '.slx'])));
blocks=find_system(m,'LookUnderMasks','all','FollowLinks','off','Type','Block');
for k=1:numel(blocks)
    p=get_param(blocks{k},'PortHandles');
    for q=p.Outport,set_param(q,'DataLogging','off');end
end
sid=[505 505 505 870 875 878 871 876 879];port=[1 2 3 1 1 1 1 1 1];
names={'command_u','command_v','command_w','zoh_u','zoh_v','zoh_w','applied_u','applied_v','applied_w'};
for k=1:numel(sid)
    block=Simulink.ID.getFullName(sprintf('%s:%d',m,sid(k)));
    p=get_param(block,'PortHandles');set_param(p.Outport(port(k)),'DataLogging','on', ...
        'DataLoggingNameMode','Custom','DataLoggingName',names{k},'DataLoggingDecimateData','off');
end
in=Simulink.SimulationInput(m).setVariable('Host_Start_s',0).setVariable('Host_Position_Loop_EN',0) ...
    .setVariable('Host_Close_Loop_EN',0).setVariable('Host_Iq_Test_Mode',1) ...
    .setVariable('Host_Iq_A',.2).setVariable('M1A_StopTime_s',.001) ...
    .setVariable('FOC_Impl_Select',0).setModelParameter('StopTime','0.001');
out=sim(in);save(fullfile(cfg.run_dir,'pwm_phase_raw.mat'),'out','-v7.3');
rows=cell(0,3);
for k=1:numel(names)
    v=out.logsout.get(names{k}).Values;
    for j=1:numel(v.Time),rows(end+1,:)={names{k},v.Time(j),v.Data(j)};end %#ok<AGROW>
end
events=cell2table(rows,'VariableNames',{'signal','time_s','duty'});
writetable(events,fullfile(cfg.run_dir,'pwm_phase_events.csv'));
result=m3_pwm_phase_contract(events,cfg.clock_period_s);
result.raw='pwm_phase_raw.mat';result.csv='pwm_phase_events.csv';
result.control_generator_priority=get_param(Simulink.ID.getFullName([m ':785']),'Priority');
close_system(m,0);
end
