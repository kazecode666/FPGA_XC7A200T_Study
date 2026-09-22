function step7c_check_scenario_start(m,commTs,deadtime)
step7c_assert_timing([],m,commTs);
mw=get_param(m,'ModelWorkspace');
fprintf('ACTUAL_SCENARIO dt=%g ratio=%g Udc=%g load=%g schedule=%s\n',mw.getVariable('PMLSM_deadtime_s'),mw.getVariable('PMLSM_deadtime_ratio'),mw.getVariable('Udc'),mw.getVariable('Host_Load_N'),mat2str(mw.getVariable('Host_Enable_Schedule')));
values=cellfun(@(n) slResolve(n,m),{'CONTROL_BACKEND','FPGA_Cosim_Enable','FPGA_Cosim_Input_Mode','FPGA_Reference_Mode'});
fprintf('ACTUAL_SIMULATION_WORKSPACE backend=%g enable=%g inputmode=%g refmode=%g\n',values);
assert(mw.getVariable('PMLSM_deadtime_s')==deadtime,'EFFECTIVE_DEADTIME_MISMATCH');
assert(abs(mw.getVariable('PMLSM_deadtime_ratio')-deadtime/1e-4)<1e-15,'EFFECTIVE_DEADTIME_RATIO_MISMATCH');
assert(mw.getVariable('Udc')==48 && mw.getVariable('Host_Load_N')==0);
assert(isequal(mw.getVariable('Host_Enable_Schedule'),[0 1 0 1]),'EFFECTIVE_HOST_SCHEDULE_MISMATCH');
assert(isequal(values,[1 1 1 0]),'EFFECTIVE_SIMULATION_WORKSPACE_MISMATCH');
fprintf('STEP7C_EFFECTIVE_SCENARIO deadtime=%.17g Vdc=48 load=0 reference=scripted feedback=live\n',deadtime);
end
