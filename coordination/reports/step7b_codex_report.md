# Step 7B execution report

Date: 2026-09-21. Status: implementation and fresh acceptance complete; awaiting ChatGPT PR Review. **No FPGA dynamic motor current loop was closed. Step 7C has not started.**

## A. MAIN, branch and preserved files

Work was confined to `D:/Project/FPGA_XC7A200T`, on `step7b-simulink-hdl-cosim`, based directly on fetched `origin/main` at `1fbef7127a1c6b9ba7f408d0f340c3abe042542f`. Origin is `kazecode666/FPGA_XC7A200T_Study`. No extra clone/worktree, stash, reset/clean, bulk deletion, installation or global PATH change was used. Existing hardware-document deletions, four modified Vivado XPRs, hardware files, previous reports and simulation caches were left alone and excluded from commits. Existing `FOC_Current`, `FOC_PWM` and `FOC_Gates` project builds were not rewritten.

## B. As-found Simple baseline

Commit **6774035** imports the original 388909-byte `simulink模型/PMLSM_ThreeLoop_Simple.slx` plus its honest as-found inventory before any model mutation. `c8b8f6d` only normalizes inventory whitespace. Initial update failed because original dependencies were absent; no co-sim modification proceeded then. After the user supplied `design_PMLSM_three_loop.m` and `pmlsm_scurve_profile.m`, commit **5470b9b** adds those original dependencies, original initialization script and a successful read-only dependency/update recheck.

The original top-level `Simple_Host`, `Control_Task_10kHz`, `Inverter_DeadTime`, `PMLSM_Plant_Model`, solver `FixedStepDiscrete`, fixed step `PMLSM_Ts_s`, model-workspace initialization and InitFcn were verified. Original SLX size/mtime remained unchanged during baseline inspection; no file hashes were used.

## C. Actual environment

- MATLAB **26.2.0.3340147, R2026b Prerelease Update 3**; explicit executable under `D:/Program Files/MATLAB/R2026b_Prerelease`.
- HDL Verifier, HDL Coder, Fixed-Point Designer, Simulink and SoC Blockset installed, version 26.2. Actual license checkout passed for `EDA_Simulator_Link`, `Simulink`, `fixed_point_toolbox`.
- **SoC Blockset Support Package for AMD FPGA and SoC Devices 26.2.2**, enabled and recognized by this release. MinGW support 26.2.2 also present.
- Vivado Simulator **2026.1**, `E:/AMDDesignTools/2026.1/Vivado/bin`; actual HDL/XSI execution passed. Local MathWorks warning recommends **2025.1.1** and says 2026.1 has not been fully tested. This is machine-specific runtime evidence, not a claim of vendor-certified compatibility.
- MATLAB startup reports a time-limited prerelease license (9 days remaining on audit date). Vitis/SoC migration was not performed.

Evidence: [environment probe](../../docs/reports/step7b/environment_probe.txt).

## D. Minimal Simulink block exchange

`PMLSM_HDL_Cosim_Minimal/HDL_Cosimulation` is a real `vivadosimlib/HDL Cosimulation` XSI block. Six fresh simulations produced inputs `[0 1 42 127 254 255]` -> HDL outputs `[1 2 43 128 255 0]`, with initial reset output zero. `STEP7B_SIMULINK_MINIMAL_COSIM_PASS` passed in final acceptance. This is not a MATLAB-only replacement or only the Step 7A System object test.

## E. Wrapper and passive taps

`mc_foc_pwm_top` changes only by three output declarations and direct assignments of existing active CMP registers. Its old wildcard TB declares matching wires. New `mc_foc_cosim_top` hides 50 MHz request/ready wiring, accepts a sample only when requested/ready, and exports active U/V/W CMP, accepted and active command IDs, validity, needs-reset and fault. IDs start at zero; active-valid remains false until the first actual load and is masked by disable/reset-needed.

Standalone wrapper TB passed first CMP, disable validity, re-enable reset-required and reset-cleared IDs. Existing FOC arithmetic, adapter polarity, PWM shadow/ZERO behavior, deadtime and gate RTL remain unchanged.

## F. First actual active CMP

The saved Simple model's fixed branch drives ia=1 A, ib=ic=-0.5 A, theta=we=id_ref=iq_ref=0, vdc=48 V. It returned first active **1165/1335/1335**, accepted ID=1, active ID=1, valid=1, needs-reset=0, fault=0 at the 150 us observation. Monitor duties are **0.466/0.534/0.534**, calculated exclusively as active CMP/2500. All input range flags were zero.

Evidence: [FOC exchange](../../docs/reports/step7b/foc_cosim_result.txt).

## G. ROM staging

The unchanged `motor_control_ip/foc/rom/sin_qw_4096x18.mem` is copied to `.Xil/step7b_foc_cosim`, the actual XSI working directory, before runtime. The generated DLL resides under its `xsim.dir/design`.

The wizard's preliminary design-query simulator can warn about the ROM because it recreates its own project simulation directory. This preliminary warning is not hidden. Final Simulink XSI runs use the staged ROM, recover the nonzero historical CMP tuple, and the complete final runtime transcript is scanned for missing-ROM diagnostics: **FINAL_RUNTIME_ROM_FILE_NOT_FOUND=0**. No ROM content or trig RTL changed.

## H. Simple model structure and formats

Added `FPGA_HDL_Cosim` contains `FPGA_Input_Adapter`, exactly one `HDL_Cosimulation`, `FPGA_Output_Adapter`, and `FPGA_Cosim_Monitor`. It has inputs only and **no output ports**. Original model layout was not automatically rearranged.

Mode 0 is accepted fixed smoke. Mode 1 reserves actual top-level local tags `PWM_EN, ia, ib, ic, theta, we, id_cmd, iq_cmd, vdc, PI_Reset`, validated by `find_system`; root-level From blocks pass them through subsystem inputs without altering tag visibility. Mode 1 was not dynamically validated.

Conversions use Nearest and saturation: currents signed 24/15, theta unsigned 16/0 after explicit 2π wrap/nearest conversion, we signed 32/16, refs/vdc signed 25/15. Per-sample range flags are logged. Params are isolated in `init_PMLSM_fpga_cosim_params.m`; original motor/PI parameters are untouched. PreLoadFcn initializes only the new co-sim defaults; original InitFcn reloads the original model workspace as before.

R2026b wizard classified `pi_reset` as a reset despite input specification. The generator explicitly corrects its clock/data mask and inserts the corresponding one-bit positional `HdlSigInfo` descriptor. A mismatched 18/19 descriptor count originally caused an XSI MEX exception; the corrected 19-port block passed actual update and exchange. This workaround is release-specific and is checked by the saved mask readback and runtime tests.

## I. Legacy plant path

Before/after integration, source/destination port strings for all inputs of controller, inverter and plant were identical. Current checks assert inverter inputs 1–3 still come from `Control_Task_10kHz`, all main-chain sources are non-FPGA, and the FPGA branch has no output ports. `FPGA_BRANCH_DRIVES_PLANT=0`, `LEGACY_CONTROL_DRIVES_INVERTER=1`, model update and a 200 us original-solver run with FPGA enable=0 passed. No original frozen numeric response exists, so no numeric-equivalence claim is made.

Evidence: [actual connectivity and masks](../../docs/reports/step7b/simple_model_after.txt), [legacy run](../../docs/reports/step7b/legacy_short_run.txt).

## J. Frozen scheduler contract

50 us communication; 20 ns HDL clock; active-low reset held 200 ns; zero prerun; 1 Simulink second = 1 HDL second. Existing profile-0 normal vector **index 5 (data row 6)** is A, expected `1165/1335/1335`; **index 6 (data row 7)** is B, expected `1250/1250/1250`. A is applied from start, B exactly at the 50 us data hit and held afterward.

Three independent simulations, each reloading/closing the same saved model without saving temporary Step sources, gave the same rule: **NEW B feeds accepted_sample_id=1 and active_command_id=1; command 2 also matches B.** On the 50 us observation grid, accepted IDs 1/2 first appear at 100/200 us and active IDs 1/2 at 150/250 us. The 200 ns reset means the first HDL peak is just after 50 us, not exactly coincident with it; no full-period delay was added. Changing reset, prerun or rates invalidates this contract and requires retesting. Observation timestamps are not claimed as exact internal edge timestamps.

Evidence: [raw vectors, physical inputs and three-run trace](../../docs/reports/step7b/timing_alignment.txt).

## K. Fresh complete regressions

`step7b_acceptance` ran all ten task stages in order after the final implementation changes and ended **STEP7B_FULL_ACCEPTANCE_PASS**. Both 6D profiles passed: base=80, tail=1, accepts=81, loads=81, full_cycles=80, protocols=6 each. 6E profile0/DEMO0 passed: deadtime=25, base=80, tail=1, full_cycles=80, shutdown=10. Minimal six values, wrapper, FOC smoke, three timing runs and legacy short run all passed. No synthesis/route was needed for passive monitor taps.

Evidence: [summary](../../docs/reports/step7b/regression_summary.txt), [complete runtime console](../../docs/reports/step7b/acceptance_console.txt). [Reproduction and interactive opening](../../docs/reports/step7b/README.md).

## L. Deliberately uncommitted

Vivado/XSI binaries, `.Xil`, `xsim.dir`, `slprj`, `.slxc`, MATLAB's automatic `.slx.r2026a` backup, skill scratch ledger/logs, old Step 6/7A outputs, user hardware material and unrelated XPR edits remain local. Cache-pattern `git ls-files` returned empty. Committed deliverables are native SLX, scoped source/scripts, original supplied dependencies and evidence/report text.

## M. Limits and next boundary

Step 7C remains unopened: live conversion validation under dynamic signals, plant takeover design, timing/delay ownership and first actual FPGA current-loop closure require separate review/authorization. No bitstream, physical hardware, Vitis/SoC migration or electrical validation occurred. Existing original model and user files are preserved; all operational effects are project-local or current MATLAB-process settings.

Execution rulings: original-repository branch used instead of a worktree; feature branch started directly from fetched main without moving local main; explicit R2026b batch/API edits used because MCP targeted R2026a; honest failed as-found inspection was committed before user-supplied dependencies made update possible. These choices preserve the user's scope but require narrow staging, leave local main unchanged, and make the initial inventory intentionally historical. The skill scratch workspace is retained under the user's deletion prohibition. Final independent review occurs before PR publication so the requested stop boundary can be honored.
