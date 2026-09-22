# Step 7D — Task 4 blocked on deadtime speed performance

Date: 2026-09-22. Branch: `codex/step7d-outer-loops-cosim`.

**Not a Step 7D acceptance PASS. Tasks 1–3 passed; Task 4 failed; Tasks 5–8 were not started.** The stop rule in the taskbook takes precedence over completing the remaining scenarios. No gain, RTL, timestep, physical parameter, window or threshold was changed to make this failure pass.

## Host and outer-loop integration

The user clarified that Simple_Host is the upper-computer request source. Its direct `iq_test_ref` belongs to open-outer-loop current testing. Position mode instead uses the existing Host trajectory, original position loop and original speed loop. The original Reference_Manager selects id/iq. Those two selected references are now exported through Control_Task outports 4/5 and local tags `S7D_Outer_Id/Iq` to the existing FPGA live input. The original Host `id_cmd/iq_cmd` tags keep their test-command semantics.

As-found SLX and native/matched legacy baselines were committed in `f6e4e50` before functional wiring in `41a1b4a`. The saved default remains legacy. Test-only request sources, logging and simulation overrides are never saved. Only the SLX root system and Control_Task system changed; all 356 existing Inport/Outport geometries and icons were preserved. New outports retain 30×14 default size. New Goto blocks are local and hide their names/attribute labels.

Implementation stayed in the original `D:/Project/FPGA_XC7A200T` working tree. The initial dirty tracked/untracked inventory and binary diff were retained locally under `.superpowers/sdd/step7d_outer_loops_cosim/`. Hardware-document moves/deletions, XPR edits, minimal-model edits, old Step 7C report edits and caches were not staged. No worktree, clone, stash, reset, cleanup, installation or global PATH change was performed.

## Verified gates before performance testing

- Task 1: original legacy backend ran without HDL setup. Native 5 ms current and 1.2 s speed/position baselines plus all five matched 1 μs legacy performance cases passed their gates. Raw MAT location: `.Xil/step7d/20260922_113014_967/`.
- Task 2: missing signal, NaN, empty window, skipped command, wrong effective reference mode and wrong effective control period are rejected. A real legacy fresh-start run completed.
- Task 3: actual Reference_Manager-to-Adapter connectivity, zero live-source error, full-rate selected/quantized canary equality, real scheduling and ideal-duty mapping passed. Post-wiring native legacy signals, including the original 17 channels and outer states, match the before baseline within 1e-10 (observed maximum difference 0).
- Real schedules: current 100 μs, speed 1 ms, position 10 ms. Short-run accepted/active counts 2000/1999; accepted-to-active delay 50 μs. No extra control-period delay was introduced.
- Runtime: MATLAB R2026b Prerelease Update 3, Vivado 2026.1, physical HDL clock 20 ns, reset 200 ns, prerun 0, exchange/plant 1 μs, PI_PROFILE=0. Backend modes `[1 1 1 1]`; Host current-test mode 0.

Evidence: `docs/reports/step7d/task1_baseline_20260922_04/`, `task2_contracts.txt`, `task3_live_source/`, `task3_verified/`, `task3_legacy_after/`.

## Task 4 outcome and exact failure

`speed_ideal` passed the full 1.2 s numerical scenario. Its worst steady-window speed RMSE is 0.085629 mm/s; current tracking RMSE is 0.00088643 A. The deadtime case uses the identical scenario and gains, with average deadtime 1 μs. It fails `Step7D:SpeedPerformance` at the first specified window. Read-only analysis of the already captured data also finds failures in two later windows:

| Speed window (s) | Samples | Legacy deadtime RMSE (mm/s) | FPGA deadtime MAE (mm/s) | FPGA deadtime RMSE (mm/s) | Result |
|---|---:|---:|---:|---:|---|
| [0.27, 0.30) | 30 | 0.128573 | 1.052120 | 1.102646 | FAIL |
| [0.44, 0.49) | 50 | 0.231702 | 0.091153 | 0.096691 | within window limits |
| [0.65, 0.74) | 90 | 0.231937 | 1.041484 | 1.073642 | FAIL |
| [1.00, 1.04) | 40 | 0.000007 | 0.000891 | 0.001105 | within window limits |
| [1.12, 1.20) | 80 | 0.231294 | 1.061316 | 1.087421 | FAIL |

MAE and RMSE limits are both 0.5 mm/s. Window 1 maximum error is 1.347152 mm/s (below the separate 2 mm/s maximum limit). The table does not turn passing individual windows into overall acceptance.

Failed run ID: `20260922_124923_408`. Full local output and reduced result: `.Xil/step7d/20260922_124923_408/simulation_output.mat` and `result.mat`. Committed failure/configuration/metrics/plots: `docs/reports/step7d/task4_speed_deadtime/`. Ideal comparison: `task4_speed_ideal/`.

## Read-only diagnosis and remaining uncertainty

The full-rate Adapter live inputs match plant/selected references exactly; q-reference quantization error is 1.52417e-5 A (within half Q15 LSB). Mode checks, actual execution periods, command sequence/pairing, 50 μs delay and selected CMP/2500 boundary passed before the performance assertion. Full-rate fault and range flags are zero. Normal-run `hard_reset` and `int_reset` are zero. Outer reference peak 0.11254 A is well below the 1 A limit; actual iq/id peaks are 0.09657/0.00544 A. This is not an observed source-selection, unit, direction, reset or saturation-limit failure.

Zero-speed loaded hold [1.00,1.04) s is good: mean iq reference 0.0225194 A, integral state 0.0225153–0.0225244 A, with no reset. The deadtime waveform shows repeated low-current speed excursions after unloading and in unloaded steady motion; ideal operation and matched legacy deadtime perform better. These observations point to the low-current behavior of the fixed FPGA current controller interacting with the shared average-deadtime model as a diagnostic lead, **not a proven root cause**. No compensator, gain, quantizer, limiter or deadtime law was changed.

Suggested next decision for ChatGPT Review: approve a bounded low-current/deadtime root-cause investigation using these saved signals and, if needed, explicitly authorized diagnostic experiments. Do not resume Task 5 or tune parameters merely to satisfy the gate. A remedy that changes the frozen controller or common inverter needs an explicit taskbook revision.

## Reproduction and scope left open

See `docs/reports/step7d/README.md`. Rerunning the deadtime scenario with a fresh report directory must currently throw `Step7D:SpeedPerformance`; the diagnostic report utility records that failure without declaring acceptance. Early debug attempts are retained locally: continuous test-input sample time rejected at HDL compilation, then timestamp-roundoff comparison corrected by aligning to physical communication ticks. Neither required a saved control-model change.

Task 4 is incomplete. No FPGA position/negative-position acceptance, original-PI limit harness, stop/restart acceptance, convergence check, fresh historical regressions or Task 8 whole-suite acceptance has been claimed. Those tasks remain pending behind this failure. No merge, next stage, bitstream or hardware operation was performed.

## Independent partial review and verification

A fresh-context reviewer examined the partial branch and identified that the standalone result evaluator could accept empty active-command data or a truncated contiguous command prefix. A new negative fixture reproduced the false acceptance before the fix. The evaluator now checks finite matching event arrays, consecutive integer IDs, pairing/delay and complete normal-run command count/phase. Empty-active, truncated-tail, NaN-time, wrong-pairing and wrong-phase fixtures now reject the data. The requested wrong-backend startup test was also added. HANDOFF now distinguishes the initial preflight from saved Task 3 wiring.

The post-review contract suite, real Task 3 saved-evidence verification and recorded Task 4 failure reproduction all completed with process exit 0. The deadtime performance assertion remains failed as expected. `docs/reports/step7d/blocked_verification.txt` records this bounded verification, not a whole-stage PASS.

Review limits and decisions: Tasks 5–8 stay deferred under the stop rule; the deadtime cause remains unproven. The reviewer did not rerun simulations or independently inspect binary SLX/layout or original dirty content. The author's real simulations, XML/geometry audit, visual report checks and 21 unchanged original tracked diffs/162 still-present untracked paths supply that evidence. Identity of every untracked file's contents was not independently established. No review finding remains deliberately deferred; no remedy to the controller failure was attempted.
