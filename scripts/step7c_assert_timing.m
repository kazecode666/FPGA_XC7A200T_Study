function out=step7c_assert_timing(out,m,commTs)
% StartFcn: assert effective values while SimulationInput overrides are active.
mw=get_param(m,'ModelWorkspace');
assert(abs(mw.getVariable('Ts_ACR')-100e-6)<1e-15);
assert(abs(mw.getVariable('PMLSM_Ts_s')-commTs)<1e-15);
bs=find_system([m '/PMLSM_Plant_Model'],'BlockType','DiscreteIntegrator'); assert(numel(bs)==4);
for k=1:numel(bs), assert(abs(slResolve(get_param(bs{k},'SampleTime'),bs{k})-commTs)<1e-15); end
fs=get_param(m,'FixedStep'); fprintf('STEP7C_EFFECTIVE_FIXEDSTEP=%s\n',fs);
assert(abs(slResolve(fs,m)-commTs)<1e-15,'STEP7C_EFFECTIVE_FIXEDSTEP_MISMATCH');
assert(evalin('base','FPGA_CLK_Period_s')==20e-9);
h=[m '/FPGA_HDL_Cosim/HDL_Backend_Variant/FPGA_Enabled/HDL_Cosimulation'];
t=str2num(get_param(h,'PortTimes')); assert(all(abs(t(12:end)-commTs)<1e-15)); %#ok<ST2NM>
assert(isequal(str2num(get_param(h,'ClockTimes')),[20e-9 200e-9])); %#ok<ST2NM>
assert(str2double(get_param(h,'PreRunTime'))==0);
end
