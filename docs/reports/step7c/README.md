# Step 7C reproduction

Use MATLAB R2026b Prerelease Update 3 with HDL Verifier, Fixed-Point Designer and the installed AMD support package. This machine uses `D:/Program Files/MATLAB/R2026b_Prerelease` and Vivado `E:/AMDDesignTools/2026.1/Vivado`. No persistent PATH changes are needed. Runtime DLLs and Vivado caches are deliberately not committed.

Close `PMLSM_ThreeLoop_Simple` before each runner. From a fresh checkout at the original project path:

```matlab
cd('D:/Project/FPGA_XC7A200T');
addpath(fullfile(pwd,'scripts'));

% Saved default backend 0: no XSI generation, HDL setup or runtime cwd.
step7c_run_scenario('legacy',1e-6);

% Build only local FPGA runtime; the committed Simple model is already wired.
step7c_generate_foc_cosim(1e-6,true);
step7c_run_dynamic('ideal');
step7c_run_dynamic('deadtime');
step7c_run_dynamic('stop');
step7c_compare_convergence;

% Full acceptance additionally requires the separate Step 7B minimal runtime.
% false preserves the existing minimal SLX, including local user edits.
step7b_generate_minimal_cosim(true,false);
diary('docs/reports/step7c/acceptance_console.txt');
step7c_acceptance;
diary off;
```

For raw returned arrays, call `r=step7c_run_scenario('ideal',1e-6)` (also `deadtime`, `stop`, `convergence`). This runs the real HDL/plant loop; `step7c_run_dynamic` adds scenario assertions and text reports. `convergence` runs only 12 ms. Full scenarios run 31 ms. Scenarios change settings in memory and close without saving. Do not rerun the one-time `refactor_backend`, `add_references`, or `add_monitor` construction scripts on an already integrated model.

The saved Simple model remains backend 0 at its original 50 us plant step; its inactive HDL block stores 1 us PortTimes. FPGA runners apply backend 1, 1 us exchange/plant step, scripted references and scenario parameters. The InitFcn reloads model parameters; scenario overrides are appended after that reload. StartFcn checks effective workspace values, solver step and all four plant integrator sample times. `Ts_ACR=100 us` remains unchanged. A 0.5 us comparison never saves transient metadata.

The ideal-duty boundary is `1 - legacy_count/period` versus FPGA `CMP_active/2500`. The approved legacy extraction has **no pre-deadtime saturation**. Both backends retain the same `deadtime correction -> d_sum -> d_sat[0,1] -> v0_eff_calc`. The FPGA interface guard is separate. HDL is statically disabled for backend 0, and FPGA duty bypasses legacy `PWM_Update_HalfTs` and polarity mapping.

`step7c_monitor` has 25 columns, listed in each dynamic report; adapter feedback and selected inverter inputs are additionally tapped in memory to prove live data and zero added sample delay. Raw MAT diagnostics are under ignored `.Xil`, and `dynamic_comparison.png` is the accepted-run overview. Stop sets vd/vq to zero using the inherited disabled inverter behavior; it is not a hardware freewheel model.

The batch acceptance also invokes the existing PowerShell XSim tests with a process-only execution policy and a Step 7C report directory. It preserves historical Step 7B evidence. Expected end marker: `STEP7C_FULL_ACCEPTANCE_PASS`. All thresholds are fixed by the taskbook; no FPGA PI or RTL changes are involved.
