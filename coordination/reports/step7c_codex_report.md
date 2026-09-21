# Step 7C implementation report

Date: 2026-09-22. Implementation branch: `step7c-dynamic-current-loop-cosim`.

## A. Git baseline and preserved user changes

Started from merged PR #30, `b96a5ff617182eeab97a99e88a6e63068b79e39e`, in the original `D:/Project/FPGA_XC7A200T` working directory. No worktree, clone, stash, reset, cleanup, or bulk deletion. The user’s Simple-model `PWM_For_PI_Reset` position change was preserved. The locally modified minimal SLX, hardware-document deletions/moves, XPR edits, old reports and caches remain outside this implementation’s commits. No RTL files changed. Git networking uses the existing proxy only per command; no global PATH or software installation changed.

## B. Legacy baseline and equivalence

The pre-edit baseline was committed first as `a95fe9a`. A 5 ms, 101-point test logs 17 outputs: controller counts, inverter vd/vq, all nine plant outputs and delayed counts. The original output-free Step 7B monitor was removed **only in memory** for the baseline, to avoid initializing XSI; the SLX was not saved. Post-refactor legacy mode runs directly from project root with no HDL setup. Every maximum before/after difference is **0**, within `1e-10`. Final validation also checks the effective legacy scenario overrides at simulation start.

## C. Approved ideal-duty boundary

Inspection found the taskbook’s assumed pre-deadtime clamp did not exist. The user explicitly approved preserving the observed mathematics, documented in `step7c_preflight_blocker.md`: extract only Gain `-1/PMLSM_pwm_period_counts` and Bias `+1`. The original common `deadtime correction -> d_sum -> d_sat[0,1] -> v0_eff_calc` stays unchanged. Structure evidence records `LEGACY_PRE_DEADTIME_SATURATION=0`, `SHARED_POST_DEADTIME_SATURATION=1`. FPGA uses positive `CMP_active/2500` with an interface guard; it bypasses the legacy delay and count/polarity mapping.

## D. Static backend and XSI isolation

`CONTROL_BACKEND=0` selects legacy; `1` selects FPGA. Variant Sources select duty/enable at update diagram time. The HDL block sits in `FPGA_HDL_Cosim/HDL_Backend_Variant/FPGA_Enabled`; a constant-output inactive branch avoids XSI initialization in legacy. One shared inverter/deadtime core and one shared plant remain. The saved default remains legacy, with the original 50 us plant step. Scenario runners configure FPGA execution in memory and close without saving.

## E. Effective timing

HDL clock 20 ns; reset 200 ns; prerun 0; physical timescale 1:1; PWM/current transaction 100 us; reference communication and plant integration 1 us. All eight HDL output PortTimes, solver fixed step, plant workspace step and all four integrator sample times are checked. `Ts_ACR` stays 100 us. The actual accepted/active transition times are in `timing_1us.txt`; visibility is within 1 us of the half-period boundary. SimulationInput uses a simulation workspace, so checks resolve parameters in model context rather than reading unrelated base-workspace defaults. Scenario model-workspace assignments execute after the model InitFcn reload.

## F. Live feedback and references

FPGA receives the moving plant’s ia/ib/ic/theta_e/omega_e via the existing fixed-point adapter. Additional prequantization taps match all five corresponding plant outputs sample-for-sample. All range flags remain zero. Current references are scripted, not sourced from speed/position loops: id=0; iq=0 through 1 ms, +0.5 A through 11 ms, 0 through 16 ms, -0.5 A through 26 ms, then 0 to 31 ms. Vdc=48 V and load=0 N. PI_PROFILE=0 and RTL are unchanged. `Step7C_Monitor` has no outputs to the plant/control chain.

## G. Ideal free-motion loop

iq spans -0.500652 to +0.500858 A; maximum |id| is 0.001041 A. Positive/negative-window mean accelerations are +12122.63 / -12123.97 mm/s². Peak |v| is 122.0277 mm/s; final x=1.8298783 mm, v=-0.0730292 mm/s. Accepted/active IDs reach 310/309. Fault, needs_reset and range flags are zero. Selected inverter duty and bridge match FPGA outputs at every logged timestamp: no additional sample delay. `dynamic_ideal.txt` contains full min/max/final vectors and RMS errors.

## H. One average-deadtime layer

Only plant-side deadtime changes to 1 us, ratio=0.01. No six-gate waveforms or RTL deadtime enter the average plant. iq spans -0.500373 to +0.500351 A; maximum |id|=0.0626485 A. Peak |v|=117.2397 mm/s; final x=1.8260677 mm, v=4.9346702 mm/s. Acceleration windows are +11933.26 / -11666.63 mm/s². Accepted/active IDs=310/309; fault/reset/range flags=0.

| Pulse RMS tracking error (A), including transient | Ideal | 1 us deadtime |
|---|---:|---:|
| Positive pulse | 0.108628 | 0.133457 |
| Negative pulse | 0.108305 | 0.163114 |

Different deadtime traces are expected; equality is not an acceptance criterion.

## I. Stop during motion

At 8 ms the scripted gate deasserts while velocity is about 75.466 mm/s and angle 0.024715 rad. By the next 1 us observation, active_valid=0, bridge=0 and shared-inverter vd/vq=0. They remain zero. needs_reset=1 follows the existing stop contract; fault=0. Old CMP remains visible but disabled. No automatic restart, NaN or Inf. Zero vd/vq is the inherited disabled average-inverter behavior, not a hardware open-circuit/freewheel claim.

## J. Timestep convergence

The 12 ms ideal comparison uses exact common timestamps, without interpolation. Maximum differences `[iq A, id A, v mm/s, x mm]` are `[0.0003142032, 0.00000636946, 0.00592308, 0.0000751298]`, below `[0.05, 0.05, 2, 0.02]`. Both rates retain 100 us accepted transactions and equal accepted/active counts. The saved HDL PortTimes remain 1 us and saved backend default remains 0.

## K. Regressions and reproduction

The final ordered run completed with `STEP7C_FULL_ACCEPTANCE_PASS` and process exit 0. The exported six-panel ideal/deadtime plot was visually inspected; currents, free motion and reference transitions are consistent with the numeric reports.

The ordered acceptance driver includes structure, legacy/root isolation and comparison, real Step 7B minimal exchange, standalone wrapper, 6D profile0 DEMO=0, 6E profile0 DEMO=0, timing, ideal, deadtime, stop and convergence. Evidence is under `docs/reports/step7c`; `regression_summary.txt` collects numeric results and parses real simulator markers. Step 7B helper changes only permit a separate report directory and runtime-only generation, preserving the user’s minimal model and historical evidence. See `docs/reports/step7c/README.md` for fresh-checkout commands and runtime prerequisites.

## L. Limits

This is actual Simulink/HDL Verifier/XSI exchange with an average plant, not hardware or a gate-level motor simulation. The motor is freely moving, with no speed/position lock or travel clamp. No FPGA PI retuning, duplicate gate deadtime, extra legacy PWM delay, software installation, bitstream, board access, FIL, Vitis or Step 7D work. Results are specific to the installed R2026b prerelease and Vivado 2026.1; they do not imply vendor certification for every release combination. The generator warns that Vivado 2026.1 has not been fully tested with this MATLAB release and recommends 2025.1.1. The local real-exchange tests passed despite that compatibility warning.

## M. Step 7D entry boundary

After ChatGPT Review accepts this open implementation PR, a separately authorized Step 7D may restore Simulink speed/position outer-loop current references. It must reuse the static backend, shared ideal-duty/deadtime boundary, live feedback and verified 1 us timing. This implementation stops before that work and does not merge its PR.
