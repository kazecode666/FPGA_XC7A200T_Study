function step7d_test_scenarios
% Catch missing/wrong interpolation and invalid-scenario acceptance.
assert(exist('step7d_scenarios','file')==2,'Step7D:MissingScenarios','Scenario contract is not implemented.');
c=step7d_scenarios('speed_ideal');
assert(c.thresholds.speedMAE==.5 && c.thresholds.speedRMSE==.5 && c.thresholds.speedMax==2);
d=step7d_scenarios('speed_deadtime');
assert(d.thresholds.speedMAE==1.5 && d.thresholds.speedRMSE==1.5 && d.thresholds.speedMax==2);
assert(abs(interp1(c.signals.speed(:,1),c.signals.speed(:,2),.10)-2.5)<1e-12);
assert(interp1(c.signals.load(:,1),c.signals.load(:,2),.225,'previous')==.5);
assert(interp1(c.signals.load(:,1),c.signals.load(:,2),.25,'previous')==0);
assert(strcmp(c.signals.loadInterpolation,'zoh'));
p=step7d_scenarios('position_negative_deadtime'); assert(p.host.Host_Target_mm==-1);
assert(all(p.signals.load(:,2)==0));
failed=false; try, step7d_scenarios('unknown'); catch e, failed=strcmp(e.identifier,'Step7D:UnknownScenario'); end
assert(failed,'Step7D:BadNameAccepted','Unknown scenario must fail.');
fprintf('STEP7D_SCENARIO_TESTS_PASS\n');
end
