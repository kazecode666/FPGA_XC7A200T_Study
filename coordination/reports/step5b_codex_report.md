# Step 5B - BX72 PWM breathing LED

## Baseline and scope

- Read `coordination/HANDOFF.md` and `coordination/tasks/step5b_breathing_led.md` from updated main before editing.
- PR #6 merge is in main as `5c22743`; main was fast-forwarded/pulled to `f067672` before creating branch `step5b-breathing-led`.
- Accepted physical Step 5A results (JTAG `xc7a200t`, successful programming, 0.5 s OFF/ON blink, KEY2 OFF/restart) come from the current handoff. They are not a claim that Codex tested Step 5B hardware.
- Frozen hardware retained: 50 MHz, `clk=Y18`, `key2_n=V17` active LOW with external 4.7 kohm pull-up, `led1=AA18` active HIGH; all Bank 14 / LVCMOS33; CFGBVS=VCCO, CONFIG_VOLTAGE=3.3.
- Local pin-workbook edits existed at start. Relevant cells Sheet1 B1:C1, B3:C3, B8:C8 still match committed assignments; the workbook is preserved and excluded from this PR.
- No Computer Use, JTAG programming, file-hash verification, or Step 6 work.

## Files and project entry

The new project is **`PWM_Breathe/PWM_Breathe.xpr`**, design top **`pwm_breathe_top`**, default simulation top **`pwm_breathe_top_tb`**. It reuses original source files by relative references. Its separate project/run/simulation directories avoid changing the user's open Step 5A Vivado session and its saved results.

| File | Purpose |
|---|---|
| `PWM_Breathe/rtl/pwm_breathe_top.sv` | Three-port wrapper, reset synchronizer, compare ramp, aligned update scheduler, frozen core instance |
| `PWM_Breathe/tb/pwm_breathe_top_tb.sv` | Readable self-check with N=8, update every 2 periods, step=2 |
| `PWM_Breathe/constraints/bx72_step5b.xdc` | Separate frozen board constraints and narrow reset exception |
| `PWM_Breathe/PWM_Breathe.xpr` | Independent portable project, `constrs_step5b`, `step5b_synth`, `step5b_impl` |
| `scripts/step5b_bx72_build.tcl` | All three regressions, synthesis, route, reports/checks, gated bitstream generation |
| `docs/reports/step5b/` | Actual tool evidence, separate from Step 5A |
| `README.md` and this report | Build entry, results and manual hardware handoff |

`pwm_controller`, `pwm_demo_top`, both old TBs, Step 5A XDC/build script/reports and existing run outputs are preserved. No old expectations were changed.

## Rates and behavior

| Quantity | Default hardware value |
|---|---|
| System clock | 50 MHz / 20 ns |
| Carrier N | 50,000 clocks = 1 ms = 1 kHz |
| Update interval | 10 complete carrier periods = 500,000 clocks = 10 ms = 100 updates/s |
| Compare step | 500 = 1% of N |
| Compare trajectory | 50,000 -> 49,500 -> ... -> 0 -> 500 -> ... -> 50,000 -> repeat |
| HIGH duty | (N-C)/N; C=N is OFF, C=0 is fully ON |
| Envelope | 100 updates/half-cycle = 1 s; complete breathing cycle 200 updates = 2 s |

This is a linear duty ramp without perceptual/gamma correction. The physical eye response need not be linear. No triangular carrier, SPWM, shadow registers, complementary PWM or dead time was added.

### Reset and scheduler timing

Two FDCE-targeted release flops use `ASYNC_REG=TRUE`, `SHREG_EXTRACT=NO` and INIT=0. KEY2 asynchronously clears them; release takes two rising edges. Initialization also starts the demo correctly when KEY2 is already HIGH at configuration.

After the second release edge, `config_en` becomes HIGH; at the third edge the core samples its first configuration C=N, the scheduler sets `started`, and `interval_count` remains zero. The LED stays OFF. Let this initial sampling edge be t0 and L=N*UPDATE_PWM_PERIODS:

| Sampling edge | Scheduler/core action |
|---|---|
| t0 | Initial config C=N; interval=0, core count=0 |
| t0+1 ... t0+L-1 | Count complete carrier periods; interval advances to L-1 |
| Interval before t0+L | `update_due` and `config_en` HIGH; next compare is stable for sampling |
| t0+L | Both counters return to zero; new compare is applied |
| t0+2L, t0+3L, ... | Repeat exactly L clocks apart |

The core would naturally wrap from N-1 to zero at each update sampling edge. Its configuration-triggered reset therefore does not truncate a period or add a clock. No synthesizable RTL reads `u_pwm.time_cnt`; the testbench reads it only to check alignment.

`compare_active` stores the value currently applied to the core. `compare_command` presents the next value during the one-clock configuration window, otherwise the active value. Decreasing C brightens the active-HIGH LED. Direction reverses when a committed command reaches zero or N; endpoints each last one update interval without an extra repeated endpoint. Saturating subtraction/addition avoids unsigned underflow/overflow, including positive steps that do not divide N. Simulation rejects zero period, zero update count, intervals below two clocks, zero step or step>N; the specified defaults and TB parameters satisfy these checks.

This remains the learning core's configuration/restart architecture. It is valid for the specified aligned updates, not a general glitch-free shadow-compare architecture for arbitrary update times.

### Constraint strategy

The XDC uses the frozen pin/voltage facts above. External KEY2 is excepted only to CLR pins of `reset_release_reg[0]` and `[1]`; the build requires exactly two matches and checks ASYNC_REG/INIT. The query obtains pins through synchronizer cells to avoid Step 5A's XDCB-5 efficiency warning. Internal stage-to-stage timing and synchronized-reset recovery/removal remain timed. No synchronous bus delays are invented for a button and human-visible LED; no DRC severity is changed.

## Simulation and build results

**Build PASS**, Vivado 2026.1, 2026-09-16. Batch start 15:03:17, completion 15:07:01 local time; exit code 0, no retries. All evidence paths below are under `docs/reports/step5b/`.

| Regression | Result |
|---|---|
| `pwm_controller_tb` | PASS, 5460 ns; all 8 original functional cases and 4 alignment cases (`pwm_controller_tb.txt`) |
| `pwm_demo_top_tb` | PASS, 1531 ns; unchanged Step 5A startup/reset/one-shot/blink assertions (`pwm_demo_top_tb.txt`) |
| `pwm_breathe_top_tb` | PASS, 9091 ns; 28 accepted configurations and 56 complete carrier periods, 448 LED samples (`pwm_breathe_top_tb.txt`) |

New TB coverage against the 13 task requirements:

| Requirement | Actual self-check |
|---|---|
| 1, 11: async assertion / running reset | Assert KEY2 3 ns away from a clock edge while LED is ON; after 1 ns require LED/reset/config/scheduler/compare/direction reset values; hold across three clocks |
| 2: synchronized release | First edge keeps internal reset LOW; second edge releases it and starts configuration; immediate button release cannot release internal reset |
| 3: deterministic OFF startup | Power-on without a button press requests C=N, brightening direction and LED OFF |
| 4: one-clock config | Measure each normal config pulse as 20 ns and require exactly one asserted sample at each update; asynchronous reset can cancel a pending unsampled pulse |
| 5, 6, 7: trajectory/bounds/direction | Independent expected array `8,6,4,2,0,2,4,6`, repeated through two envelopes before reset; check command in 0..8 and non-X, active value and direction every sample; repeat from C=8 after reset |
| 8: exact update interval | Require 16 sampled edges between updates, scheduler count 0..15, and old core count=7 before each reconfiguration; require core phase=sample mod 8 |
| 9: duty measurement | Count each complete 8-sample period: HIGH/LOW = 0/8, 2/6, 4/4, 6/2, 8/0 and reverse; two complete periods per applied level |
| 10: polarity | Each LED sample must match both the independent expected HIGH condition and `pwm_core_out` |
| 12: deterministic restart | Recheck two-edge release and ten modulation levels after running reset; total 28 accepted config events |
| 13: fail/hang handling | Every mismatch uses `$fatal`; separate 20 us watchdog; build requires the explicit PASS marker and rejects Fatal/ERROR log text |

The simulation uses N=8 / periods=2 / step=2, never a real 2-second waveform. Hardware builds use the RTL defaults N=50,000 / periods=10 / step=500 without parameter overrides.

| Build check | Actual result / evidence |
|---|---|
| Synthesis | `synth_design Complete!`; 237 LUTs, 117 FFs, 45 CARRY4; 0 latches/BRAM/DSP (`synthesis_utilization.rpt`) |
| Implementation | `route_design Complete!`; 233 LUTs, 117 FFs (110 FDCE + 7 FDPE), 45 CARRY4, 1 BUFG, 2 IBUF, 1 OBUF (`implementation_utilization.rpt`) |
| Routing | 438/438 routable nets fully routed, 0 routing errors; 615 logical nets (`route_status.rpt`) |
| Clock | Exactly one `sys_clk`, 20.000 ns / 50.000 MHz |
| Setup | **WNS 11.737 ns, TNS 0.000 ns**, 0 failing of 291 endpoints |
| Hold | **WHS 0.159 ns, THS 0.000 ns**, 0 failing of 291 endpoints |
| Pulse width | WPWS 9.500 ns, TPWS 0.000 ns, 0 failing of 118 endpoints |
| Internal constraint coverage | no_clock=0, unconstrained_internal_endpoints=0, no combinational/latch loops (`timing_summary.rpt`) |
| DRC | Routed default DRC **0 violations**; bitstream precondition DRC also 0 errors. NSTD-1/UCIO-1/CFGBVS-1 absent and never suppressed (`drc.rpt`) |
| Methodology | One TIMING-18 warning for LED1 missing output delay; no XDCB-5 (`methodology.rpt`) |
| CDC/reset | 1 safe asynchronous input/reset crossing, 0 unsafe, 0 unknown, 0 missing ASYNC_REG (`cdc.rpt`) |
| Pins/configuration | All three audited pins/standards match; CFGBVS=VCCO, CONFIG_VOLTAGE=3.3; both release FFs FDCE, INIT=0, ASYNC_REG=1, colocated SLICE_X6Y125; exactly their two CLR pins are excepted (`board_properties.txt`, `io.rpt`, `exceptions.rpt`) |
| Bitstream | **Generated: Yes**, `write_bitstream Complete!`, `STEP5B_BUILD_PASS` (`build_result.txt`) |
| Physical hardware | **NOT TESTED** |

Worst setup path: `compare_active_reg[2]/C -> u_pwm/pwm_out_reg_reg/D`; data delay 8.221 ns = 2.695 ns logic + 5.526 ns routing, 15 logic levels. Worst hold path: `reset_release_reg[0]/C -> reset_release_reg[1]/D`; delay 0.219 ns = 0.164 ns logic + 0.055 ns routing. Full five-path max/min reports are `setup_paths.rpt` and `hold_paths.rpt`. The timing summary also retains the synchronized reset's recovery/removal group; it is not covered by the external reset exception.

Exact generated bitstream path:

`D:/Project/FPGA_XC7A200T/PWM_Breathe/PWM_Breathe.runs/step5b_impl/pwm_breathe_top.bit`

The file exists, 9,730,859 bytes, modification time 2026-09-16 15:06:50 local. It is not committed; reproduce it with the script below.

### Warnings, limits and preservation

- **TIMING-18:** LED1 is observed by a person, without an external synchronous sampling clock, so it intentionally has no output delay. KEY2 has no phase relationship to sys_clk; its reset-entry path alone is excepted. `check_timing` lists key2_n as one no-input-delay port with a false path and led1 as one no-output-delay port. This is not synchronous external-bus sign-off. No invented delays or disabled rules were used.
- The outer batch, synthesis run and implementation/bitgen run each have **0 ERROR, 0 CRITICAL WARNING, 0 WARNING** anchored log lines (`messages.txt`). The methodology warning above is a separate report finding, not hidden by these log counts. The synthesis information message about implementation-specific constraints simply defers pin/configuration properties to implementation, where their actual values were checked.
- No unresolved build blockers. JTAG programming and physical breathing confirmation remain the user's next action after review.
- `preservation.txt`: all 88 pre-existing Step 5A synthesis/implementation files retained their sizes and modification times. Git diff confirms unchanged old RTL/TBs/XDC/script/reports. Original `PWM_Controller.xpr` and the locally modified pin workbook matched pre-task backups byte-for-byte, without using hashes. Neither local modification is staged.
- The reports contain actual Vivado output with only trailing whitespace/blank EOF lines normalized for Git. Generated local run metadata in the new XPR is retained locally but excluded from its portable committed configuration.

## Reproduction and physical handoff

From the repository root in PowerShell:

```powershell
& 'E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat' -mode batch -nojournal -log step5b_build.log -source scripts/step5b_bx72_build.tcl
```

The script creates/opens only the new project, selects each regression top, requires its PASS marker, builds only Step 5B runs, checks actual pin/voltage/clock/reset objects and timing/DRC, then creates the bitstream. Generated run directories, DCPs, bitstreams, caches, logs and journals are not committed.

After PR acceptance, the user should:

1. Open `PWM_Breathe/PWM_Breathe.xpr`, with BX72 connected for the same standalone LED experiment as Step 5A.
2. Open Hardware Manager -> Open Target -> Auto Connect; confirm the detected device is still `xc7a200t`.
3. Program the Step 5B `pwm_breathe_top.bit` at the exact local path recorded with the results. Do not select the older blink bitstream. No configuration-flash programming is needed.
4. Observe LED1/D7: OFF -> gradually brighter for about 1 s -> gradually dimmer for about 1 s -> OFF, repeating.
5. Hold KEY2/S2; LED1 must turn OFF. Release it; after contact settling, breathing restarts from OFF (first duty step after 10 ms). There is no pushbutton debounce circuit in RTL.
6. Report programming result, breathing behavior and reset/restart behavior back to ChatGPT. No oscilloscope is required.

**Physical hardware: NOT TESTED.** The user must perform and report Step 5B observations; Step 5A's accepted hardware result does not establish Step 5B physical PASS.

## Submission / stop

Branch: `step5b-breathing-led`.

Implementation commit: `1dfd0df86202a57e845440ff1af44c121ca8bc2d` (`feat: add BX72 PWM breathing LED demo`). A documentation-only follow-up records these submission links; the PR head contains the latest report.

PR URL: https://github.com/kazecode666/FPGA_XC7A200T_Study/pull/7 (open, not merged).

Stop at the open Step 5B PR for ChatGPT review. Do not enter Step 6.
