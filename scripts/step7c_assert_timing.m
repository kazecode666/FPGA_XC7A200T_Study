function out=step7c_assert_timing(out,m,commTs)
% StartFcn: assert effective values while SimulationInput overrides are active.
mw=get_param(m,'ModelWorkspace');
assert(abs(mw.getVariable('Ts_ACR')-100e-6)<1e-15);
assert(abs(mw.getVariable('PMLSM_Ts_s')-commTs)<1e-15);
fs=get_param(m,'FixedStep'); fprintf('STEP7C_EFFECTIVE_FIXEDSTEP=%s\n',fs);
assert(abs(slResolve(fs,m)-commTs)<1e-15,'STEP7C_EFFECTIVE_FIXEDSTEP_MISMATCH');
assert(evalin('base','FPGA_CLK_Period_s')==20e-9);
h=[m '/FPGA_HDL_Cosim/HDL_Backend_Variant/FPGA_Enabled/HDL_Cosimulation'];
t=str2num(get_param(h,'PortTimes')); assert(all(abs(t(12:end)-commTs)<1e-15)); %#ok<ST2NM>
end
