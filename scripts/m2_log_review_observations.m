function m2_log_review_observations(model,foc,mode)
% Test copies only. Observe actual branch outputs; no derived sign substitutes.
assert(contains(get_param(model,'FileName'),[filesep '.runtime' filesep]));
assert(ismember(mode,{'discovery','detail'}));
phases={'a','b','c'};
signSid=[826 841 856];
for k=1:3
    observe(Simulink.ID.getFullName(sprintf('%s:%d',model,signSid(k))),1, ...
        ['review_sign_' phases{k}]);
end
for item={'Park',1,'review_park_d';'Park',2,'review_park_q'; ...
        'Id',1,'review_vd_raw';'Iq',1,'review_vq_raw'; ...
        'dq_voltage_limiter',5,'review_sat_delayed'; ...
        'SVPWMG',4,'review_sector'}'
    observe([foc '/' item{1}],item{2},item{3});
end
observe(Simulink.ID.getFullName([model ':1993']),1,'review_x_ref_mm');
if strcmp(mode,'detail')
    % Each row is the corresponding actual block output in phases A/B/C.
    sid=[817 832 847;825 840 855;822 837 852;820 835 850;827 842 857];
    label={'phase_i','deadzone','delta_d','d_eff','pole_V'};
    for row=1:size(sid,1)
        for k=1:3
            observe(Simulink.ID.getFullName(sprintf('%s:%d',model,sid(row,k))), ...
                1,['review_' label{row} '_' phases{k}]);
        end
    end
    for k=1:3
        observe(Simulink.ID.getFullName([model ':866']),k, ...
            ['review_duty_applied_' phases{k}]);
    end
    for k=1:2
        label={'review_vd_applied','review_vq_applied'};
        observe(Simulink.ID.getFullName([model ':771']),k,label{k});
    end
end
end
function observe(block,port,name)
p=get_param(block,'PortHandles');
set_param(p.Outport(port),'DataLogging','on','DataLoggingNameMode','Custom', ...
    'DataLoggingName',name,'DataLoggingDecimateData','off');
end
