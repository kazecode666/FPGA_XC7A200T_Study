# Step 6C1 — Fixed-point FOC transform execution report

Date: 2026-09-18. Branch: `step6c1-fixed-point-transforms`.
Base `main`: `dc7579b`, including accepted Step 6B PWM PR #11 (merge `bbe0cc1`).
Implementation and verification through `376ff18`; this handoff packages existing
measured evidence without rerunning simulation or builds.

## Delivered behavior and arithmetic contract

Portable inferred SystemVerilog provides `mc_fxp_pkg`, `mc_clarke`,
`mc_sincos_lut`, `mc_park`, `mc_inv_park`, and `mc_current_transform`.
The synthesis top is the coherent current transform: Clarke and quarter-wave
LUT sin/cos feed Park, with alpha/beta/sin/cos debug fields aligned to id/iq.
Inverse Park is separately implemented and tested; it is not part of this top's
resource count. Architecture is LUT plus DSP48 arithmetic, with no CORDIC,
floating-point datapath, or explicit DSP48E1/RAMB primitive instantiation.

| Signal | Exact format | Physical interpretation |
|---|---|---|
| ia, ib, ic | signed 24 F15 | raw / 32768 A |
| Transform currents/voltages | signed 25 F15 | raw / 32768 A or V |
| Coefficients, sin/cos | signed 18 F16 | raw / 65536 |
| Electrical angle | unsigned 16-bit binary angle | raw * 2*pi / 65536 radians |

Constants are `C_TWO_THIRDS=43691`, `C_INV_SQRT3=37837`, and
`SIN_COS_ONE=65536`. Full signed 43-bit F31 products are retained; Park and
inverse-Park accumulation uses signed 44 bits. Conversion uses magnitude-based
round-to-nearest, ties away from zero, then signed saturation to
[-16777216, 16777215]. The Clarke half-sum also rounds odd ties away from zero.
Negative exact multiples remain exact; overflow does not silently wrap.

The 4096 x 18 quarter-wave ROM follows the authoritative formula
`floor(65536*sin(pi*q/8192)+0.5)`, q=0..4095. Its last **10** entries equal
65536 after rounding, even though the geometric quarter-wave endpoint is
excluded. The plan's example assertion `<65536` conflicted with that formula;
the recorded ruling preserves the formula and permits `<=65536`. Quadrant
reconstruction uses an exact 65536 at the missing endpoint. Angle bits [1:0]
are intentionally discarded; all 65536 input phase words were checked.

## Measured latency and transaction contract

An input is accepted at rising edge N with input_valid asserted. The following
are measured edge differences, not an inclusive count of register stages.

| Block | Output edge | Edge latency | At 50 MHz |
|---|---|---:|---:|
| Clarke | N+2 | 2 clocks | 40 ns |
| sin/cos LUT | N+1 | 1 clock | 20 ns |
| Park / inverse Park standalone | N+2 | 2 clocks | 40 ns |
| Current transform | N+5 | 5 clocks | 100 ns |
| Tested Park-to-inverse-Park RTL cascade | N+5 | 5 clocks | 100 ns |

Every block sustains one transaction per clock (initiation interval 1). The
current transform adds one sin/cos alignment register; Park accepts the matched
tuple at N+3, and three debug registers align all six outputs at N+5. Bubbles
propagate through valid state. Active-low asynchronous reset flushes pending
transactions. Internal synchronous ROM read-data registers have no asynchronous
reset, preserving BRAM inference; reset valid state masks their values.

## Numerical acceptance

RTL acceptance is integer-exact against the quantized Python oracle. The
Step 6A Simulink lookup is a separate algorithm-level comparison, not a
bit-exact trigonometric target. The recorded final `reference_python.txt`
reports these maximum absolute errors across all 160 Step 6A rows:

| Quantity | Versus Step 6A | Versus mathematical ideal |
|---|---:|---:|
| i_alpha (A) | 1.2207031e-05 | 1.01725261333e-05 |
| i_beta (A) | 1.359400385e-05 | 1.00701378221e-05 |
| id (A) | 1.359400385e-05 | 1.01725261333e-05 |
| iq (A) | 2.17200290529e-05 | 2.56175066903e-05 |
| v_alpha (V) | 0.0018247646495 | 0.00198968832234 |
| v_beta (V) | 0.00469674939613 | 0.00461102494122 |

Ideal transform comparisons use quantized physical inputs and mathematical
sin/cos at the Step 6A electrical angle. Inverse Park uses Step 6A `ud_lim/uq_lim`
as inputs and `v_alpha/v_beta` as references. Across all 65536 binary phases,
maximum sin/cos ideal error is **0.000295057787973**. The 1000 independent seeded
safe-range Park/inverse-Park round trips (within +/-8 physical units) have maximum
error **5 raw F15 LSB = 0.000152587890625** physical units. Deliberate saturation
cases are checked separately and excluded from this unsaturated bound.

## TDD and regression evidence

RED elaboration logs precede each missing module implementation: Clarke,
sin/cos, Park/inverse Park, and current transform. They fail for the intended
missing design unit, not a claimed functional pass. GREEN is established by the
saved exact success markers and self-checking scoreboards. Evidence resides in
`docs/reports/step6c1/tdd_*` and the final `*_tb.txt` files.

| Gate | Recorded result |
|---|---|
| Clarke | PASS: 165 fixture rows, 175 checked outputs; helpers, rounding, saturation, valid/reset |
| sin/cos | PASS: 65536 phase rows, 65548 checked outputs, exact axes and ideal-error bound |
| Park / inverse Park | PASS: 1141 / 1143 fixture rows, 1000 safe RTL cascade rows, 3299 checked outputs |
| Current transform | PASS: all 256 rows, 160 Step 6A-derived plus 96 continuous distinct transactions; 4 pending reset-flushed |
| All six current-transform fields | PASS: bit-exact, fixed latency 5, bubbles, reset recovery, extra/missing/reordering checks |
| Accepted Step 6B PWM regression | PASS: `ALL STEP 6B MOTOR PWM TESTS PASSED`; unchanged testbench, 1567 monitored clocks |
| Step 6A Python regression | PASS: 160 actual-source rows, 2926 checks, maximum absolute error 5.46e-12 |
| C1 Python reference --check | PASS: 4096 ROM entries, 65536 phases, 160 rows, deterministic artifact equality and invariant checks |
| Optimized Python guard | PASS: python -O rejected with exit 2 before generation or assertion-based acceptance |

The previously noted Python optimization weakness is fixed: optimized execution
cannot silently disable assert-based acceptance. The final normal check and
optimized rejection were both recorded; generated numerical assets are unchanged.

## Vivado project, build and actual mapping

Vivado 2026.1 targets `xc7a200tfbg484-2` and `mc_current_transform`, with only
`create_clock -period 20.000 -name sys_clk [get_ports clk]`. The portable
`FOC_Transforms/FOC_Transforms.xpr` externally references six RTL files, four
testbenches, one ROM, and one XDC; the package compiles first. Task 6 actually
opened a relocated minimal tree read-only, verified all twelve references and
ROM synthesis/simulation attributes, and exited 0. No drive-absolute XPR paths
or duplicated project-local source files remain.

The first build attempt exited natively while opening the XPR after closing
PWM XSim, without a Tcl error and before synthesis. The completed build therefore
used an explicit scratch project from the exact external inventory, with a
read-only XML audit of the portable XPR's part, top, source inventory, ROM
attributes, and clock contract. The tracked XPR was unchanged. This workaround
and the independent relocation result are preserved in `build_rework.txt`,
`project_build_contract.txt`, and `project_portability.txt`.

The final full run, token `20260918_154058_6976`, exited 0 and recorded
`STEP6C1_BUILD_PASS`: all five simulations, both normal Python regressions,
optimized rejection, synthesis, route, timing, resource, and XML gates passed.
After that run, the report-only route completeness gate was added to the script;
its exact Tcl block was executed independently against the final route report
with Vivado, exit 0. This was not another full design build. No RTL or constraint
change intervened. `route_gate.txt` confirms 1455/1455 nets fully routed and
zero routing errors; future full runs include this gate directly.

| Resource | Synthesis | Routed |
|---|---:|---:|
| Slice LUTs | 735 | 732 |
| Slice registers / FF | 580 | 580 |
| DSP48E1 | 6 | 6 |
| RAMB36E1 | 2 | 2 |
| RAMB18E1 | 0 | 0 |
| Latches | 0 | 0 |

The synthesis primitive inventory lists **888 logical LUT cells** before LUT
combining/packing accounting; this differs from the **735 Slice LUTs** in the
synthesis utilization report and must not replace it. Routed Slice LUT usage is
732. Hierarchy confirms two Clarke and four Park DSPs, and two RAMB36E1 cells
for the dual-read ROM, with nonzero initialization data. Mapping matches the
intended LUT+DSP/BRAM architecture; no inference deviation was found.

## Internal timing and retained warnings

| Timing / route gate | Actual result |
|---|---:|
| sys_clk | 20.000 ns / 50 MHz |
| WNS / TNS | 10.548 ns / 0.000 ns |
| WHS / THS | 0.118 ns / 0.000 ns |
| no_clock / unconstrained internal endpoints | 0 / 0 |
| combinational loops / latch loops | 0 / 0 |
| Fully routed / routable nets | 1455 / 1455 |
| Routing errors | 0 |

The actual worst setup path is `clarke/beta_product0/CLK` to
`clarke/i_beta_reg[0]/D`; worst hold is `beta_delay_reg[0][13]/C` to
`beta_delay_reg[1][13]/D`. These are internal clock timing results.

Driver snapshot: 18 anchored WARNING lines, 0 ERROR, 0 CRITICAL WARNING,
including echoed child-run messages. Synthesis log: 4 repeated warning lines
for intentionally unused theta_e[1:0]. Implementation run: 0 warning lines.
Driver warnings also cover oversized testbench objects omitted from wave display
and the empty latch query. These log counts are not a clean DRC claim.

Separate `drc.rpt` retains NSTD-1 and UCIO-1 **Critical Warning** findings
(one each, affecting all 226 logical ports), CFGBVS-1 (1), DSP DPIP-1 input
pipelining advisories (10), and DPOP-2 MREG output pipelining advisories (6).
`methodology.rpt` records 481 checks: DPIR-1 asynchronous-driver advisories 252,
SYNTH-6 RAM timing advisories 2, and TIMING-18 missing-I/O-delay findings 227.
`check_timing.rpt` separately lists 88 inputs and 137 outputs without delays.
Counts belong to different report categories and are not interchangeable.
No board pins, IOSTANDARD, or input/output delays were added, and none of these
findings were suppressed. This establishes internal timing only, not board
I/O timing sign-off or bitstream readiness.

## Scope and review handoff

Changes relative to base main are confined to the new FOC IP/fixtures/ROM,
FOC_Transforms project and clock XDC, C1 reference/build scripts, the fixed
comparison CSV, and C1 reports. Protected `PWM_Controller/`, `PWM_Breathe/`,
`simulink模型/`, Step 6A golden files, and accepted Step 6B PWM sources are
unchanged in the branch diff. The pre-existing dirty BX72 pin spreadsheet and
two legacy XPRs remain preserved and unstaged.

This packaging commit only adds this report and normalizes trailing whitespace
and extra blank EOF lines in `docs/reports/step6c1` text evidence. Diagnostic
content, numerical results, and warning findings are preserved. No reports
were deleted. Scratch task reports remain local and untracked.

No Step 6C2 functionality, PI controller, voltage limiter, SVPWM, ADC/encoder,
PWM integration, board wrapper, bitstream generation, or hardware programming
was performed. Handoff is for review and an open PR; merge and Step 6C2 remain
outside this task. Build reproduction is documented in the FOC README and
`scripts/step6c1_foc_transforms_build.tcl`.
