function result=m3_pwm_phase_contract(events,clockPeriod)
% 固定合同前检：从真实事件配对测量，不搜索可使错误通过的相位。
events.signal=string(events.signal);phase={'u','v','w'};tol=1e-12;zohPairs=0;appliedPairs=0;
periods=zeros(3,3);offsets=[];
for k=1:3
    cmd=events(events.signal=="command_"+phase{k},:);
    zoh=events(events.signal=="zoh_"+phase{k},:);
    applied=events(events.signal=="applied_"+phase{k},:);
    assert(height(cmd)==11&&height(zoh)==11&&height(applied)==21, ...
        'M3:PWM_COUNT','Expected complete 1ms three-phase probe, phase%s.',phase{k});
    periods(k,:)=[median(diff(cmd.time_s)),median(diff(zoh.time_s)),median(diff(applied.time_s))];
    assert(all(abs(diff(cmd.time_s)-1e-4)<tol)&&all(abs(diff(zoh.time_s)-1e-4)<tol) ...
        &&all(abs(diff(applied.time_s)-5e-5)<tol),'M3:PWM_PERIOD','Actual PWM/control period changed, phase%s.',phase{k});
    assert(abs(cmd.time_s(1))<tol&&abs(applied.time_s(1))<tol ...
        &&all(abs(cmd.time_s-zoh.time_s)<tol),'M3:PWM_PHASE','Command/ZOH phase changed, phase%s.',phase{k});
    assert(isequal(cmd.duty,zoh.duty),'M3:PWM_VALUE','Command/ZOH values differ, phase%s.',phase{k});
    zohPairs=zohPairs+height(cmd);
    for j=1:height(cmd)
        target=cmd.time_s(j)+5e-5;
        if target>applied.time_s(end)+tol,continue;end
        at=find(abs(applied.time_s-target)<tol);
        assert(numel(at)==1,'M3:PWM_PHASE','Missing/duplicate applied(t+50us), phase%s.',phase{k});
        assert(isequal(cmd.duty(j),applied.duty(at)),'M3:PWM_VALUE','Applied value differs, phase%s sample%d.',phase{k},j-1);
        appliedPairs=appliedPairs+1;offsets(end+1)=applied.time_s(at)-cmd.time_s(j); %#ok<AGROW>
    end
end
assert(zohPairs==33&&appliedPairs==30,'M3:PWM_COUNT','No complete nonzero pair count.');
measuredOffset=median(offsets);deadline=round(measuredOffset/clockPeriod);
assert(deadline==2500&&all(abs(offsets-5e-5)<tol),'M3:PWM_DEADLINE','Frozen 2500-clock application boundary changed.');
result=struct('status','PASS','phases',3,'zoh_pairs',zohPairs,'applied_pairs',appliedPairs, ...
    'measured_periods_per_phase_s',periods,'control_period_s',median(periods(:,1)), ...
    'ZOH_period_s',median(periods(:,2)),'delay_period_s',median(periods(:,3)), ...
    'measured_application_offset_s',measuredOffset,'application_deadline_cycles',deadline, ...
    'first_mismatch',[],'time_tolerance_s',tol,'duty_comparison','exact logged values');
end
