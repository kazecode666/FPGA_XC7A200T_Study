# Step 6B Motor PWM Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify a reusable three-phase, center-aligned, shadow-compare motor PWM core for 50 MHz / 10 kHz operation without modifying the legacy PWM learning core.

**Architecture:** `motor_pwm_core` owns one shared up/down time base, one atomic U/V/W shadow transaction, ZERO-only active loading, and three registered raw PWM outputs. The RTL lives under `motor_control_ip/pwm/` and is referenced by a separate `Motor_PWM` Vivado project so it can later move to Zynq PL without carrying the legacy project structure.

**Tech Stack:** SystemVerilog, Vivado/XSim 2026.1, Tcl, target `xc7a200tfbg484-2`.

**Spec:** `coordination/tasks/step6b_motor_pwm_core.md` implementing approved architecture `coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`.

## Global Constraints

- Default real `TBPRD=2500` at 50 MHz gives exactly 10 kHz center-aligned PWM.
- Testbench uses `TBPRD=8` and therefore a 16-clock ZERO-to-ZERO cycle.
- Do not modify `PWM_Controller/`, `PWM_Breathe/`, or `simulink模型/`.
- Do not implement `duty_to_cmp`, FOC, SVPWM, dead time, complementary outputs, trip, ADC, encoder, AXI, or physical pins.
- No vendor primitive may appear inside `motor_pwm_core.sv`.
- No bitstream or hardware programming.
- Use Git status/diff and executable evidence; no SHA/file-hash workflow.
- Stop at an open PR for ChatGPT review.

---

## File Structure

Create:

```text
motor_control_ip/pwm/README.md
motor_control_ip/pwm/rtl/motor_pwm_core.sv
motor_control_ip/pwm/tb/motor_pwm_core_tb.sv
Motor_PWM/Motor_PWM.xpr
Motor_PWM/Motor_PWM.srcs/constrs_1/new/motor_pwm_clock.xdc
scripts/step6b_motor_pwm_build.tcl
coordination/reports/step6b_codex_report.md
docs/reports/step6b/*
```

The project must reference, not duplicate, the RTL/TB under `motor_control_ip/pwm/`.

---

### Task 1: Create the branch and a failing self-checking testbench shell

**Files:**
- Create: `motor_control_ip/pwm/tb/motor_pwm_core_tb.sv`
- Read: `coordination/tasks/step6b_motor_pwm_core.md`
- Read: `coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`

**Interfaces:**
- Consumes: approved Step 6B interface contract.
- Produces: a self-checking TB that expects a module named `motor_pwm_core` with `TBPRD` and `COUNTER_WIDTH` parameters.

- [ ] **Step 1: Sync and branch**

```bash
git checkout main
git pull --ff-only
git status --short
git checkout -b step6b-motor-pwm-core
```

Verify PR #10 content and the Step 6B task/plan are present on this branch before edits.

- [ ] **Step 2: Write the TB constants, DUT interface, clock and failure accounting**

Use:

```systemverilog
localparam int unsigned TBPRD_TEST = 8;
localparam int unsigned CW = $clog2(TBPRD_TEST + 1);

logic clk = 1'b0;
always #10ns clk = ~clk;  // 50 MHz

int error_count = 0;
```

Instantiate the exact DUT interface from the task with `.TBPRD(TBPRD_TEST)` and `.COUNTER_WIDTH(CW)`.

- [ ] **Step 3: Add deterministic TB helpers before RTL exists**

Include a direction-aware expected-value function:

```systemverilog
function automatic logic expected_pwm(
    input int unsigned cmp,
    input int unsigned ctr,
    input logic up
);
    if (cmp == 0)
        expected_pwm = 1'b0;
    else if (cmp >= TBPRD_TEST)
        expected_pwm = 1'b1;
    else if (up)
        expected_pwm = (ctr < cmp);
    else
        expected_pwm = (ctr <= cmp);
endfunction
```

Add race-free helpers with stimulus on `negedge clk`:

```text
apply_reset
send_cmp_command(u,v,w)
wait_for_zero
check_current_reference_levels
count_highs_one_cycle
```

`send_cmp_command` must wait for `cmp_cmd_ready`, assert `cmp_cmd_valid` for one accepted clock only, then deassert it.

- [ ] **Step 4: Add the first two tests**

Test A: asynchronous reset while disabled:

```text
reset_n=0 -> tbctr=0, count_up=1,
active/shadow=0, pending=0,
pwm_u/v/w=0, event pulses=0
```

Test B: disabled preload `{0,4,8}`:

```text
accepted while pwm_enable=0
shadow={0,4,8}
active={0,4,8}
shadow_pending=0
compare_load_event=0
pwm_u/v/w remain LOW while disabled
```

- [ ] **Step 5: Run compilation and confirm RED**

Use Vivado/XSim compile commands or a temporary minimal project. Expected result: compilation/elaboration fails specifically because `motor_pwm_core` does not yet exist. Record this as the TDD RED state in the Codex report notes.

- [ ] **Step 6: Commit the failing test scaffold**

```bash
git add motor_control_ip/pwm/tb/motor_pwm_core_tb.sv
git commit -m "test: add Step 6B motor PWM testbench scaffold"
```

---

### Task 2: Implement reset, disabled behavior, and the shared up/down carrier

**Files:**
- Create: `motor_control_ip/pwm/rtl/motor_pwm_core.sv`
- Modify: `motor_control_ip/pwm/tb/motor_pwm_core_tb.sv`

**Interfaces:**
- Consumes: clock/reset/enable and compare command ports.
- Produces: deterministic `tbctr`, `count_up`, `carrier_zero`, `carrier_peak`, reset state and disabled state.

- [ ] **Step 1: Add the exact module shell**

Start with:

```systemverilog
module motor_pwm_core #(
    parameter int unsigned TBPRD = 2500,
    parameter int unsigned COUNTER_WIDTH = $clog2(TBPRD + 1)
) (
    input  logic clk,
    input  logic reset_n,
    input  logic pwm_enable,
    input  logic [COUNTER_WIDTH-1:0] cmp_u_cmd,
    input  logic [COUNTER_WIDTH-1:0] cmp_v_cmd,
    input  logic [COUNTER_WIDTH-1:0] cmp_w_cmd,
    input  logic cmp_cmd_valid,
    output logic cmp_cmd_ready,
    output logic pwm_u,
    output logic pwm_v,
    output logic pwm_w,
    output logic [COUNTER_WIDTH-1:0] tbctr,
    output logic count_up,
    output logic carrier_zero,
    output logic carrier_peak,
    output logic [COUNTER_WIDTH-1:0] cmp_u_shadow,
    output logic [COUNTER_WIDTH-1:0] cmp_v_shadow,
    output logic [COUNTER_WIDTH-1:0] cmp_w_shadow,
    output logic [COUNTER_WIDTH-1:0] cmp_u_active,
    output logic [COUNTER_WIDTH-1:0] cmp_v_active,
    output logic [COUNTER_WIDTH-1:0] cmp_w_active,
    output logic shadow_pending,
    output logic compare_load_event
);
```

Use `always_ff @(posedge clk or negedge reset_n)` for registered state. Do not instantiate FPGA-specific primitives.

- [ ] **Step 2: Implement reset/disable state exactly**

Asynchronous reset sets every state/output listed in the task to zero except `count_up=1`.

When `pwm_enable=0` after reset release:

```text
tbctr=0
count_up=1
carrier_zero=0
carrier_peak=0
compare_load_event=0
pwm_u/v/w=0
shadow_pending=0 unless a command branch updates registers that edge
```

Do not clear active/shadow compare registers merely because PWM is disabled; they are configuration state.

- [ ] **Step 3: Implement carrier next-state rules**

Use next-state logic so the registered sequence is exactly:

```text
0,1,...,TBPRD,TBPRD-1,...,1,0
```

At the transition into peak, set the next direction to DOWN and pulse `carrier_peak`.

At the transition into zero, set the next direction to UP and pulse `carrier_zero`.

The startup transition from disabled stationary zero to running state is not a `carrier_zero` pulse.

- [ ] **Step 4: Extend TB with exact carrier/event checks**

After coherent preload and enable, ignore startup until the first running ZERO pulse, then assert:

```text
next PEAK pulse occurs 8 clocks later
next ZERO pulse occurs 16 clocks later
```

On each stable negedge, verify `tbctr` traverses the expected state sequence and `carrier_zero`/`carrier_peak` are never high for two consecutive clocks.

- [ ] **Step 5: Run tests**

Expected at this point: reset/disable/carrier tests PASS; compare/PWM tests not yet enabled or are expected to fail clearly because shadow/AQ behavior is incomplete.

- [ ] **Step 6: Commit**

```bash
git add motor_control_ip/pwm/rtl/motor_pwm_core.sv motor_control_ip/pwm/tb/motor_pwm_core_tb.sv
git commit -m "feat: add shared center-aligned motor PWM time base"
```

---

### Task 3: Implement atomic shadow command capture and ZERO-only loading

**Files:**
- Modify: `motor_control_ip/pwm/rtl/motor_pwm_core.sv`
- Modify: `motor_control_ip/pwm/tb/motor_pwm_core_tb.sv`

**Interfaces:**
- Consumes: `{cmp_u_cmd,cmp_v_cmd,cmp_w_cmd,cmp_cmd_valid}`.
- Produces: shadow/active U/V/W, `cmp_cmd_ready`, `shadow_pending`, `compare_load_event`.

- [ ] **Step 1: Implement ready/accept semantics**

Use behavior equivalent to:

```systemverilog
cmp_cmd_ready = reset_n && (!pwm_enable || !shadow_pending);
```

When disabled, a valid+ready command writes all three shadow and all three active registers immediately and leaves `shadow_pending=0`.

When enabled, a valid+ready command writes all three shadow registers and sets `shadow_pending=1`.

- [ ] **Step 2: Implement ZERO loading with old-pending semantics**

On an enabled running ZERO event:

```text
if shadow_pending was already 1 before this clock:
    active U/V/W <= shadow U/V/W atomically
    shadow_pending <= 0
    compare_load_event <= 1 for this clock
```

A newly accepted command on that same edge must not be forwarded into active registers. Nonblocking/next-state priority must make the documented ZERO-collision rule explicit rather than accidental.

- [ ] **Step 3: Implement disabled pending cancellation**

If PWM becomes disabled with an old pending transaction and no new disabled command is accepted, clear `shadow_pending`; do not silently apply the pending command. The next disabled command can then explicitly preload a coherent active set.

- [ ] **Step 4: Add TB tests for mid-period shadow behavior**

With active `{2,4,6}`:

```text
accept {6,2,4} away from ZERO
shadow becomes {6,2,4}
active remains {2,4,6}
pending=1
ready=0
carrier timing unchanged
```

At next ZERO:

```text
active becomes {6,2,4} all in the same clock
pending=0
compare_load_event=1 exactly one clock
```

- [ ] **Step 5: Add pending overwrite rejection test**

After the first pending command is accepted, drive a second different valid command while `cmp_cmd_ready=0` and verify the first shadow tuple remains unchanged.

- [ ] **Step 6: Add exact ZERO-collision test**

Arrange `cmp_cmd_valid && cmp_cmd_ready` on the edge that enters ZERO with no prior pending command. Verify:

```text
active tuple does not change on this ZERO
shadow tuple captures the new command
pending remains 1
compare_load_event remains 0 on this ZERO
active tuple changes only at the following ZERO
```

- [ ] **Step 7: Run and commit**

Expected: all command/atomic-load tests PASS.

```bash
git add motor_control_ip/pwm/rtl/motor_pwm_core.sv motor_control_ip/pwm/tb/motor_pwm_core_tb.sv
git commit -m "feat: add atomic three-phase shadow compare loading"
```

---

### Task 4: Implement registered three-phase PWM levels and duty boundaries

**Files:**
- Modify: `motor_control_ip/pwm/rtl/motor_pwm_core.sv`
- Modify: `motor_control_ip/pwm/tb/motor_pwm_core_tb.sv`

**Interfaces:**
- Consumes: next carrier state/direction and next active compare tuple.
- Produces: registered `pwm_u/pwm_v/pwm_w` aligned with visible carrier/active state.

- [ ] **Step 1: Add one reusable phase-level function in RTL**

Implement the exact discrete rule without signed/width ambiguity:

```systemverilog
function automatic logic phase_level(
    input logic [COUNTER_WIDTH-1:0] cmp,
    input logic [COUNTER_WIDTH-1:0] ctr,
    input logic up
);
    if (cmp == '0)
        phase_level = 1'b0;
    else if (cmp >= TBPRD[COUNTER_WIDTH-1:0])
        phase_level = 1'b1;
    else if (up)
        phase_level = (ctr < cmp);
    else
        phase_level = (ctr <= cmp);
endfunction
```

If Vivado rejects the shown parameter slice syntax, use an explicitly typed localparam for `TBPRD` rather than changing behavior.

- [ ] **Step 2: Register outputs from the same next-state view**

When enabled, calculate all three next PWM outputs from:

```text
next_tbctr
next_count_up
next cmp_*_active
```

so active compare and output change coherently on ZERO loads and there is no extra one-clock lag.

When disabled or reset, outputs are LOW regardless of compare values.

- [ ] **Step 3: Add boundary tests**

For one complete steady-state cycle at `TBPRD_TEST=8`:

```text
CMP=0 -> HIGH count 0/16
CMP=8 -> HIGH count 16/16
```

- [ ] **Step 4: Add the three independent duty test**

Load `{2,4,6}` and count one ZERO-to-ZERO cycle:

```text
U high = 4/16 clocks
V high = 8/16 clocks
W high = 12/16 clocks
```

At every stable sample, independently compare each phase against TB `expected_pwm(active_cmp,tbctr,count_up)`.

- [ ] **Step 5: Add center-alignment checks**

For interior compare values, assert transition behavior:

```text
up-count state first reaching CMP -> output LOW
down-count state first reaching CMP -> output HIGH
ZERO-side high pulse lengths match on both halves
```

Do not accept a test that only checks average duty while edge placement is wrong.

- [ ] **Step 6: Run and commit**

Expected: carrier, shadow and all 0/25/50/75/100% tests PASS.

```bash
git add motor_control_ip/pwm/rtl/motor_pwm_core.sv motor_control_ip/pwm/tb/motor_pwm_core_tb.sv
git commit -m "feat: add three-phase center-aligned PWM outputs"
```

---

### Task 5: Complete reset/disable/re-enable regressions and PASS marker

**Files:**
- Modify: `motor_control_ip/pwm/tb/motor_pwm_core_tb.sv`

**Interfaces:**
- Consumes: completed Step 6B core.
- Produces: exhaustive baseline self-check with one final PASS marker.

- [ ] **Step 1: Add asynchronous reset-during-operation test**

While active mid-cycle with nonzero outputs, assert `reset_n=0` between clock edges. After a small simulator delta/settling delay, require:

```text
pwm_u/v/w=0
tbctr=0
count_up=1
active/shadow=0
pending=0
events=0
```

Release reset while disabled and confirm state remains safe.

- [ ] **Step 2: Add disable mid-cycle test**

While running `{2,4,6}`, deassert `pwm_enable` on a negedge. At the next registered update and thereafter require:

```text
pwm_u/v/w=0
tbctr=0
count_up=1
carrier_zero=0
carrier_peak=0
shadow_pending=0
```

- [ ] **Step 3: Add disabled preload then re-enable test**

While disabled, accept `{8,4,0}` and require both shadow and active to equal the tuple immediately. Re-enable, wait for steady-state, then verify 100/50/0% outputs over a full cycle.

- [ ] **Step 4: Add event pulse sanity monitor**

A monitor must fail if any of these are high on consecutive clocks:

```text
carrier_zero
carrier_peak
compare_load_event
```

Also fail if `compare_load_event` occurs while enabled without a previously pending command.

- [ ] **Step 5: Add final result marker**

At the end:

```systemverilog
if (error_count == 0) begin
    $display("ALL STEP 6B MOTOR PWM TESTS PASSED");
    $finish;
end else begin
    $fatal(1, "STEP 6B MOTOR PWM TESTS FAILED: %0d errors", error_count);
end
```

- [ ] **Step 6: Run full behavioral simulation**

Expected log contains exactly the PASS marker and no `$error`/`$fatal` failure.

- [ ] **Step 7: Commit**

```bash
git add motor_control_ip/pwm/tb/motor_pwm_core_tb.sv
git commit -m "test: complete Step 6B motor PWM regression"
```

---

### Task 6: Add portable documentation, Vivado project, clock constraint, and automated build

**Files:**
- Create: `motor_control_ip/pwm/README.md`
- Create: `Motor_PWM/Motor_PWM.xpr`
- Create: `Motor_PWM/Motor_PWM.srcs/constrs_1/new/motor_pwm_clock.xdc`
- Create: `scripts/step6b_motor_pwm_build.tcl`

**Interfaces:**
- Consumes: portable RTL/TB.
- Produces: reproducible Vivado 2026.1 simulation/synthesis/route evidence.

- [ ] **Step 1: Write the interface README**

Document the exact carrier, compare, shadow handshake, ZERO-collision, disable/preload and deferred-feature rules from the task. Include the formulas:

```text
TBPRD = f_clk/(2*f_pwm)
HIGH duty = CMP/TBPRD
```

Do not copy unresolved DSP/MIL raw count formulas into this README.

- [ ] **Step 2: Create independent project**

Create `Motor_PWM` for `xc7a200tfbg484-2`, add the portable RTL to `sources_1`, portable TB to `sim_1`, set:

```text
design top = motor_pwm_core
simulation top = motor_pwm_core_tb
```

Ensure project paths are repository-relative/portable. Verify no developer-machine absolute path is committed.

- [ ] **Step 3: Add clock-only XDC**

Exact content:

```tcl
create_clock -name sys_clk -period 20.000 [get_ports clk]
```

Do not add package/IOSTANDARD/I/O-delay assumptions.

- [ ] **Step 4: Implement build script guardrails**

At script start require:

```tcl
require {[version -short] eq "2026.1"} "Expected Vivado 2026.1"
require {[get_property PART [current_project]] eq "xc7a200tfbg484-2"} "Wrong FPGA part"
```

Create `docs/reports/step6b/` and first write:

```text
STEP6B_BUILD_IN_PROGRESS; not a PASS result
```

to `build_result.txt`.

- [ ] **Step 5: Automate Step 6B simulation**

Run `motor_pwm_core_tb`, capture `simulate.log` into `docs/reports/step6b/motor_pwm_core_tb.txt`, and require:

```text
ALL STEP 6B MOTOR PWM TESTS PASSED
```

Fail the script on fatal/error simulation messages.

- [ ] **Step 6: Run legacy behavioral regressions without modifying them**

Run the existing:

```text
pwm_controller_tb
pwm_demo_top_tb
pwm_breathe_top_tb
```

using their existing sources/projects or a clean temporary fileset. Require their established PASS markers. If one cannot run due to an environment issue unrelated to Step 6B, record the exact reason and prove no legacy file changed; do not patch legacy RTL merely to satisfy this task.

- [ ] **Step 7: Automate synthesis and implementation**

Use real `motor_pwm_core` default `TBPRD=2500`. Run synthesis and route implementation with the 20 ns clock constraint.

Export at minimum:

```text
docs/reports/step6b/synth_utilization.rpt
docs/reports/step6b/impl_utilization.rpt
docs/reports/step6b/timing_summary.rpt
docs/reports/step6b/check_timing.rpt
```

Require completed runs and internal timing:

```text
WNS >= 0
TNS = 0
WHS >= 0
THS = 0
```

Do not generate bitstream.

- [ ] **Step 8: Write PASS only after every required gate succeeds**

Final `build_result.txt` should state a concise PASS summary including simulation, synthesis, route and timing. Otherwise leave a failure/in-progress result and make the Tcl command fail.

- [ ] **Step 9: Run the full batch build from a clean terminal**

Example:

```bash
vivado -mode batch -nojournal -log step6b_local.log -source scripts/step6b_motor_pwm_build.tcl
```

Expected: process exit success and Step 6B PASS report.

- [ ] **Step 10: Commit project/build artifacts**

Commit only source/project metadata, clock XDC, Tcl and text reports. Exclude `.runs/`, `.sim/`, `.cache/`, `.gen/`, `.ip_user_files/`, journals and transient logs.

```bash
git add motor_control_ip/pwm/README.md Motor_PWM scripts/step6b_motor_pwm_build.tcl docs/reports/step6b
git commit -m "build: add Step 6B Vivado project and routed evidence"
```

---

### Task 7: Final verification, Codex report, and PR

**Files:**
- Create: `coordination/reports/step6b_codex_report.md`
- Verify: all Step 6B scoped files.

**Interfaces:**
- Consumes: simulation/build evidence.
- Produces: review-ready PR with no hidden unresolved failure.

- [ ] **Step 1: Inspect Git scope**

Run:

```bash
git status --short
git diff --check
git diff main...HEAD --stat
git diff main...HEAD -- PWM_Controller PWM_Breathe simulink模型
```

The final command must show no Step 6B changes in the protected legacy/reference areas.

- [ ] **Step 2: Re-run the Python Step 6A vector verifier as a reference regression**

```bash
python scripts/reference_audit/verify_step6a_vectors.py
```

Expected existing result: PASS. This does not validate Step 6B PWM numerics; it verifies the accepted algorithm-reference artifacts were not damaged.

- [ ] **Step 3: Write Codex report**

Include:

```text
branch/base commit
Vivado version/part
exact RTL/project files
TBPRD_TEST and real TBPRD
all simulation case results
legacy regression results
synthesis utilization
routed utilization
WNS/TNS/WHS/THS
check_timing coverage caveats
all warnings/critical warnings/errors
confirmation: no bitstream, no physical pins, no hardware programming
confirmation: legacy PWM/Simulink references unchanged
any unresolved issue
```

Explain that Step 6B verifies raw three-phase PWM timing only; it does not yet validate `duty_to_cmp`, FOC, dead time or safe power-stage drive.

- [ ] **Step 4: Final commit**

```bash
git add coordination/reports/step6b_codex_report.md
git commit -m "docs: record Step 6B motor PWM verification"
```

- [ ] **Step 5: Push and open PR**

```text
PR title: Step 6B: Add three-phase motor PWM core
base: main
head: step6b-motor-pwm-core
```

PR body must summarize behavioral semantics, shadow/atomic tests, real 10 kHz configuration, routed timing/utilization, scope deferrals and any warning. Link the Codex report and `docs/reports/step6b/` evidence.

- [ ] **Step 6: Stop**

Do not merge the PR and do not begin Step 6C1. Wait for ChatGPT review.

---

## Plan Self-Review Checklist

Before opening the PR, verify each approved Step 6B architecture requirement maps to evidence:

```text
shared up/down carrier                 -> carrier sequence/event tests
2*TBPRD exact period                   -> zero-to-zero cycle test
0/25/50/75/100%                        -> high-clock count tests
three independent phase compares       -> {2,4,6} test
shadow not immediate                   -> mid-period test
atomic ZERO load                       -> active tuple/load-event test
carrier not reset by update            -> sequence continuity assertion
same-ZERO command deferred             -> ZERO-collision test
pending not overwritten                -> ready=0 rejection test
reset safe LOW                         -> async reset test
disable safe LOW/stationary carrier    -> disable test
disabled coherent preload              -> re-enable test
one-clock event pulses                 -> monitor
50 MHz route timing                    -> timing_summary.rpt
portable/device-independent RTL        -> source inspection/no primitives
no board/power-stage claim             -> report scope statement
```

The plan is incomplete if any row lacks an automated test or report artifact.
