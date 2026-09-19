# Step 6C2 execution report

Status: PASS. The final full build completed at 2026-09-19 17:05:08 with process exit 0 and exact `STEP6C2_BUILD_PASS`. All evidence below is from the final code revision unless explicitly labeled development/RED evidence.

## Scope and provenance

Accepted documentation baseline: `74f6128` (C2 docs PR #13), including accepted C1 PR #12 merge `1207f38`. The isolated worktree branch is `step6c2-pi-dq-limiter`; reviewed RTL/TB handoff is `7bc81ce`. Final tested code revision: `8934278` (portable-project baseline `9724e77`, build hardening and narrow parser repair included). The tested code revision and final run are recorded below; a subsequent report-only commit is not represented as the revision executed by Vivado.

All changes are C2 additions under the frozen task book. Accepted C1, Step6A, Step6B PWM, Simulink, spec/task/HANDOFF files and parent-checkout modifications remain untouched. No hashes, deletion/cleanup, computer use, bitstream, hardware access or C3 work were performed.

## Independent numerical comparisons

The oracle reads the actual `coordination/reports/step6a_pi_foc_golden_vectors.csv` in its original order: profile 0 `real_commissioning` (80 rows), then profile 1 `MIL_PI_override` (80 rows). Inputs id/iq/reference/speed/bus are quantized directly, without rerunning C1 transforms. Each profile starts from hardware/model reset and maintains its own state continuously. Per-row `pi_reset` and `uq_zero_en` commands are preserved; integrators are never loaded from CSV expected values. The comparison CSV `step6c2_pi_fixed_vectors.csv` retains OLD/NEXT histories, integer results, reference values and errors.

The CSV `du_d_z` and `du_q_z` columns are compared with OLD delayed corrections. OLD and current saturation flags are checked separately: zero mismatches across all 160 rows, so there are no threshold-neighborhood exceptions to list. Current `sat_flag` uses the frozen 0.999 comparison independently from whether scale is less than one.

Actual CSV source ranges (physical units; flags Boolean):

| Column | Minimum | Maximum |
|---|---:|---:|
| du_d_z | -7.65238846430606 | 127.897391383021 |
| du_q_z | -85.2649275886806 | 5.10159230953737 |
| id | -0.23094010767585 | 1 |
| id_ref | -1 | 30 |
| iq | -0.23094010767585 | 1 |
| iq_ref | -20 | 20 |
| pi_reset | 0 | 1 |
| sat_flag_z | 0 | 1 |
| ud_lim | -21.4177912038294 | 20.7526086169791 |
| ud_raw | -28.4049965895518 | 148.65 |
| uq_lim | -13.8350724113194 | 16.1361811957173 |
| uq_raw | -99.1 | 18.9366643930345 |
| uq_zero_en | 0 | 1 |
| vdc | 48 | 48 |
| we | 0 | 100 |

Maximum absolute errors against Step6A (each must be <=0.002 V):

| Column | Maximum error (V) | Profile | Row (1-based within profile) | Case |
|---|---:|---|---:|---|
| du_d_z | 2.27579897948971e-06 | 1 MIL_PI_override | 76 | recovery_3 |
| du_q_z | 1.49733110177408e-06 | 1 MIL_PI_override | 76 | recovery_3 |
| ud_lim | 9.58486421498428e-05 | 1 MIL_PI_override | 18 | angle_1.5708 |
| ud_raw | 8.58946664723526e-05 | 1 MIL_PI_override | 18 | angle_1.5708 |
| uq_lim | 0.000119042001521991 | 1 MIL_PI_override | 15 | angle_0.0000 |
| uq_raw | 0.000112545095241473 | 1 MIL_PI_override | 15 | angle_0.0000 |

The limiter ideal comparison uses the same quantized S40 raw voltage and valid S25 bus, real `min(1,Umax/(hypot(d,q)+1e-6))`, finite/sign checks, 150 directed cases and 4096 seeded full-width cases. The maximum component error is 0.00002170713307236838 V (gate 0.00006103515625 V), and maximum norm excess is 0.000019523331644677455 V (gate 0.000030517578125 V). Independent 90-digit Decimal checks cover 105 valid directed cases. Final RTL limiter output additionally reports d maximum 0.000021481294 V at fixture row 2067, q maximum 0.000021707133 V at row 4080, norm excess 0.000019523332 V at row 3657, and 4231 valid ideal comparisons (display precision 12 decimals; fixture IDs zero-based). These bounds do not establish a general relative-angle bound near zero.

## Bit-exact fixtures, timing, state and fault coverage

Fixture counts are independently literal-gated by the oracle and TBs: round 1101; range 9; sqrt 2078; divider 2058; evaluator 1042 (521/profile); limiter 4246; golden core 160 (80/profile); successful seeded core 2048 (1024/profile); error stream 258 (one successful saturation preamble plus 128 errors/profile). Fixed-width lowercase-hex parsing checks exact field count, widths, unused high bits, contiguous unique IDs, order, headers and EOF count before casting. The integer oracle uses unbounded Python arithmetic, `math.isqrt` and integer division, independent of iterative RTL.

Measured completion intervals are evaluator +16, sqrt +40, divider +72, limiter +160 and core +256 rising edges after acceptance, including errors. Earliest next acceptance is the following edge. Scoreboards inspect pre-edge handshakes and post-NBA outputs; unknown valid/data, extra/missing/reordered results, early state commits and busy-input contamination fail. Each sequential unit tests >=5000 idle clocks, output hold and valid held across busy. Core repeats each golden/seeded/error sequence twice with different idle gaps and requires identical accepted-sequence results.

| Test | Responses | Async aborted transactions | Other exact coverage |
|---|---:|---:|---|
| FXP helpers | 1101 round + 9 range | n/a | literals, ties/neighbors, S96 minimum, S25/S40 rails |
| sqrt | 6193 | 40 | 2078 fixture rows, identity/remainder invariants, all +40 phases |
| divider | 4125 | 72 | 2058 rows, divide-by-zero and full-width invariants |
| evaluator profile 0 | 556 | 18 | 521 fixture + 16 directed; +16 |
| evaluator profile 1 | 556 | 18 | same counts, independent profile elaboration |
| limiter | 4287 | 160 | 56 errors, 11 injected private-engine errors; +160 |
| core profile 0 | 2493 | 258 | 2751 accepted, 2229 success, 129 invalid bus, 128 range, 7 internal |
| core profile 1 | 2493 | 258 | same counts; +256 |

Core abort coverage per profile: evaluator-active 16, sqrt-active 40, divider-active 72, completed-private/final-padding 75; sweep phases 0..255 plus two simultaneous-edge resets. Errors retain all five OLD state values and NEXT state equals OLD, while visible error data is zero. Command reset during saturation observes OLD correction before clearing selected NEXT state. q-only reset preserves d state. Seven private-engine fault injections are preceded by successful saturation so all five OLD state fields are nonzero.

Literal three-update profile-0 identity from zero is verified: raw d F24 `36595302,41565552,46535802`; OLD xd `0,4970250,9940500`; NEXT xd `4970250,9940500,14910750`; external d F15 `71475,81183,90890`; q and corrections zero.

Previously reviewed functional negative controls are retained in the unit verification reports under `docs/reports/step6c2/`: arithmetic-shift rounding fails row 14; using NEXT integrator for raw voltage fails the first one-amp case; multiplying Kaw by Ts fails the OLD-du case; signed norm, omitted epsilon and F15-derived feedback mutations each fail limiter oracle checks; current-du anti-windup, per-busy-clock integration and premature +18 state commit mutations fail core checks; truncated golden fixtures fail before accepting transactions. Mutation compile/elaboration succeeded and the expected explicit TB Fatal/no-success result was observed. XSim can return 0 on TB Fatal, so process exit alone is never acceptance. Integration found an XSim 2026.1 native crash on short rows in the earlier FXP/sqrt string-destination sscanf parsers. With explicit additional authorization, only those two new C2 testbench parsers were replaced by the indexed-byte tokenizer already used by the other C2 benches; all numerical and fixture gates remain unchanged. Retained RED evidence shows the native crash, and focused GREEN evidence shows normal exact-count PASS plus explicit short-row TB Fatal. The final build exercises short-column, nonhex and truncated round/range/sqrt fixtures (nine cases), missing source and missing marker: eleven negative probes. Fixture probes require explicit TB Fatal and reject native FATAL_ERROR, so the known malformed input is covered rather than avoided.

## Portable project and final tool evidence

Final acceptance is recorded under `docs/reports/step6c2/final04/`; code commit `8934278c834f115fc0e68b8dd196d69abb03419e`, run started 2026-09-19 16:53:08. Vivado/XSim 2026.1 build 6511674 and the actual Vivado environment's CPython 3.13.0 were used. Earlier standalone oracle development used CPython 3.14.6; those versions are not conflated.

Reproduction from the repository root (choose a fresh report label):

```powershell
& 'E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat' -mode batch -nojournal -log .Xil/c2_accept.log -source scripts/step6c2_pi_build.tcl -tclargs accept_new
```

`portable_audit.txt` records an actual read-only open of a relocated minimal tree. All six RTL, six TB, nine simulation-only data files and one exact 20.000 ns clock XDC resolve inside that tree; source inventory/types, package-first compilation, part and profile/top settings are checked. Only the disposable copy is then reopened writable for `launch_simulation -scripts_only`. All nine staged data files match their external source content. The generated batch command contains quoted `-testplusarg "VECTOR_DIR=."`, and actual exported compile/elaborate/simulate scripts run the default profile-0 core to its exact transaction count and success marker in the generated cwd. `staging_supplement.txt` separately verifies all exported compile source files are inside the relocated tree (the Vivado installation include directory is identified separately), and the actual four C1 regression cwd ROM/fixture contents equal the untouched accepted sources.

The positive simulation inventory is exactly 13: the portable profile-0 core; FXP, sqrt, divider, evaluator profiles 0/1, limiter, profile-1 core; four unchanged C1 tops; and unchanged Step6B PWM. The final script invokes explicit C1 source files, never the whole C1 build. Separate fresh compile/elaboration directories prove profile identity; every positive process exit is 0, exact marker and diagnostic/count gates pass. All 11 Python unit tests, C2 `--check`, C1 `--check`, Step6A verifier, and both `-O`/`-OO` rejection paths for both C2 Python entrypoints pass. Check logs contain the regenerated numerical maxima and exact fixture counts.

Eleven negative-result files start IN_PROGRESS and finish FAILED as required. The nine fixture probes compile and elaborate successfully and explicitly reject two-column rows, nonhex four-column rows, or truncated counts in each round/range/sqrt fixture, without native FATAL_ERROR. The missing-source probe rejects an actually absent scratch path; the missing-marker probe runs a fresh valid FXP simulation but requires a deliberately absent marker, so exit 0 alone cannot pass it. The overall result becomes PASS only after every positive, negative, portability and two-profile route gate.

Both profiles use independent fresh synthesis/implementation projects and complete route_design. Each open synthesized design now produces its own `profileN/synth_timing_summary.rpt` before the build closes it; each report header explicitly identifies `Design State : Synthesized`. Both diagnostic summaries report estimated WNS 11.016 ns, WHS 0.122 ns and WPWS 9.500 ns, with zero negative totals/failing endpoints. These synthesis estimates are retained for diagnosis only: no new synthesis-slack acceptance gate was added, and the frozen routed gates continue to use the separate `profileN/timing_summary.rpt` identified as Routed.

The outer PowerShell wrapper serialized the exact command, ISO start/end times and both Vivado/wrapper exit code 0 in `outer_wrapper_exit.txt`; its observed process exit was also 0. The candidate was committed before the complete final04 invocation, and no build/RTL/TB edit occurred during or after that invocation.

Final measured resources (logical LUT primitive count is distinct from packed Slice LUT utilization):

| Profile / stage | DSP48E1 | RAMB36 / RAMB18 | Logical LUTs | Slice LUTs | FFs | Latches / black boxes |
|---|---:|---:|---:|---:|---:|---:|
| 0 synthesis | 52 | 0 / 0 | 6334 | 5389 | 5476 | 0 / 0 |
| 0 routed | 52 | 0 / 0 | 6309 | 5321 | 5476 | 0 / 0 |
| 1 synthesis | 54 | 0 / 0 | 6222 | 5293 | 5420 | 0 / 0 |
| 1 routed | 54 | 0 / 0 | 6197 | 5224 | 5420 | 0 / 0 |

Synthesis hierarchy attributes 30/32 DSPs to the profile-0/profile-1 evaluator and 22 DSPs to the limiter; sqrt/divider each use 0 DSP and 0 BRAM. Their nested logic remains identifiable in the hierarchy reports. This is measured inference, with no fixed DSP-count target and no debug KEEP forcing.

| Profile | WNS / TNS (ns) | WHS / THS (ns) | WPWS / TPWS (ns) | Setup failing / timed | Hold failing / timed | Pulse failing / timed | Routed / routable / errors |
|---|---:|---:|---:|---:|---:|---:|---:|
| 0 | 7.450 / 0.000 | 0.072 / 0.000 | 9.500 / 0.000 | 0 / 13581 | 0 / 13581 | 0 / 5523 | 11176 / 11176 / 0 |
| 1 | 7.340 / 0.000 | 0.079 / 0.000 | 9.500 / 0.000 | 0 / 13597 | 0 / 13597 | 0 / 5469 | 11112 / 11112 / 0 |

The raw `SLACK` properties were queried directly (no additional rounding) and independently gated: profile 0 max 7.450, min 0.072; profile 1 max 7.340, min 0.079 ns. Profile-0 worst setup starts at `eval_engine/product_ff_reg[0][5]/C` and ends at `eval_engine/term_ff_reg[0][94]/D`; profile-1 starts at bit 1 and ends at the same term endpoint. Worst hold is `eval_engine/ff_pair01_reg[1][46]/C` to `eval_engine/product_ff_reg[1][46]/D` for profile 0, and `limiter_engine/captured_d_reg[23]/C` to `limiter_engine/correction_d_reg[23]/D` for profile 1. Full setup/hold path reports are retained. Both designs have exactly one `sys_clk` at 20.000 ns; no_clock, unconstrained_internal_endpoints, loops and latch_loops are all zero. No multiple-driver or unresolved-module/non-board error/critical DRC blocker is present.

Warnings are retained and enumerated in `warning_inventory.txt`, `simulator_warning_inventory.txt`, both raw run logs, DRC reports and methodology reports. The inventory reads actual compiler, elaborator and simulator subprocess logs as well as the driver/implementation outputs. Each synthesis emits 133 warning lines: 100 `Synth 8-3332` unused sequential-bit removals (the native repeat-message cap is retained), 14 `Synth 8-3936` unused internal-register bit trimming, and 19 `Synth 8-6014` unused sequential/debug-register removals. Neither implementation child log emits an anchored warning/error line; that does not mean the design is free of DRC/methodology findings:

| Finding | Profile 0 | Profile 1 | Meaning |
|---|---:|---:|---|
| NSTD-1 / UCIO-1 | 1 / 1 critical warning | 1 / 1 critical warning | Board I/O standards and pin locations unspecified |
| CFGBVS-1 | 1 warning | 1 warning | Board configuration-voltage properties unspecified |
| DPOP-1 | 20 warnings | 20 warnings | DSP PREG output-pipelining advice |
| DPOP-2 | 52 warnings | 54 warnings | DSP MREG output-pipelining advice |
| SYNTH-10 | 26 warnings | 28 warnings | Multi-DSP wide multipliers |
| TIMING-18 | 217 warnings | 217 warnings | 161 inputs and 56 outputs lack external delays |

The actual exported portable simulation emits five `Wavedata 42-489` warnings: `vec` (3389120 bits), `queue_row`, `queue_edge` and `queue_id` (262144 bits each), and `queue_old` (1318912 bits) exceed the 65536-bit wave-window display limit. These warnings concern adding large testbench objects to the waveform window, not their numerical execution or scoreboard checks; the simulation still completes with exact counts and its success marker. All five raw WARNING lines and their actual per-file/category count are retained in both inventories. No severity suppression or display-limit expansion was made.

The minimal relocated project also retains missing generated IP-directory and empty-board-part warnings; path-length advisory and generated-script/tool paths are preserved in `driver_transcript.txt`. None of these severities was suppressed or reassigned. Internal routed timing passes with these findings visible; external board timing remains unspecified.

Committed `docs/reports/step6c2/development_attempts.txt` summarizes the development history; full final04 evidence and parser-repair RED/GREEN evidence are committed. Original dev01..dev05 and final01..final02 run directories remain preserved locally and are intentionally excluded from the commit; references to those older directories below describe local history, not GitHub artifacts. dev01/dev02/dev03/dev04 correctly failed on property syntax, lazy simulator properties/read-only export behavior, and Windows plusarg quoting, then those integration issues were corrected. Earlier short-row native-crash RED evidence is retained and the parser fix is covered in final04. Superseded final01 failed during profile-1 Vivado tool initialization (`Could not open 'C' for writing`, `tclapp::load_apps` during create_project); its full child error log is retained. No root cause is asserted for that tool startup failure. Superseded final02 was deliberately terminated only through its verified task-owned wrapper PID/child tree and remains IN_PROGRESS/nonPASS. Neither superseded run is substituted for final04.

Scope audit uses Git diff against accepted main `74f6128`, direct source inventories and tool output, not hashes. All existing protected paths remain unchanged. Only authorized new C2 files are included; the additional FXP/sqrt parser fixes were explicitly authorized after the reproduced simulator failures. Report text may have trailing whitespace normalized for Git; source data and prior accepted reports remain unchanged. No board pins, I/O standards, external delays, exception waivers or message-severity changes were added. There is no bitstream or physical-board validation and no board timing sign-off. The implementation is prepared for the specified unmerged PR and ChatGPT review; merge and C3 are outside this completion boundary.


Task 7 review fixes are limited to R1/R2: the build now retains diagnostic synthesis summaries for both profiles, and warning accounting includes the five real simulator waveform-display warnings. Prior `final03` evidence remains committed and unchanged as the earlier full functional/routed run; it is superseded as authoritative acceptance by `final04`, which reran every required check after the last script edit. No RTL, testbench, frozen constraint or protected source changed in this review-fix round.
