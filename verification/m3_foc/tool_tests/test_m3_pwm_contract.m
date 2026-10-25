function result=test_m3_pwm_contract(eventsFile,output)
% 实际129条记录 + 四类故障，验证前检不是仅写MEASURED。
t=readtable(eventsFile,'TextType','string');
good=m3_pwm_phase_contract(t,20e-9);
assert(strcmp(good.status,'PASS')&&good.applied_pairs==30&&good.zoh_pairs==33);
bad=t;k=find(bad.signal=="applied_v"&bad.time_s>0,1);bad.duty(k)=bad.duty(k)+1e-6;
reject(bad,'M3:PWM_VALUE');
bad=t;k=find(bad.signal=="applied_w"&bad.time_s>0,1);bad.time_s(k)=bad.time_s(k)+20e-9;
reject(bad,'M3:PWM_PERIOD');
bad=t;k=find(bad.signal=="command_u"&bad.time_s>0,1);bad.time_s(k)=bad.time_s(k)+20e-9;
reject(bad,'M3:PWM_PERIOD');
bad=t(t.signal~="applied_w",:);reject(bad,'M3:PWM_COUNT');
result=struct('status','PASS','tests',5,'actual_zoh_pairs',good.zoh_pairs, ...
    'actual_applied_pairs',good.applied_pairs,'negative_value_time_control_missing_rejected',true);
fid=fopen(output,'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
end
function reject(events,id)
rejected=false;try,m3_pwm_phase_contract(events,20e-9);catch e,rejected=strcmp(e.identifier,id);end
assert(rejected,'M3:PWM_NEGATIVE','Expected rejection %s.',id);
end
