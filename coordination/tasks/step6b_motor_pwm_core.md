# Step 6B — Motor PWM Core

This task is the current ChatGPT → Codex implementation handoff for the first reusable motor-control PWM IP.

## Preconditions

- PR #10 (`Step 6A: Audit basic PI FOC Simulink reference`) is merged into `main`.
- The user explicitly approved `coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md` on 2026-09-17.
- Step 6A audit/golden vectors are now algorithm references only; Step 6B does not implement FOC math yet.
- Pull latest `main` before creating the Step 6B branch.

## Governing architecture

Read before editing:

`coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`

Step 6B implements only Part A of that architecture: the three-phase motor PWM engine.

Do not inherit the historical F28335/F28388D/MIL raw compare-count or polarity conventions. Step 6B has its own clean FPGA contract below.

---

## Goal

Create an independent, reusable, device-portable SystemVerilog motor PWM core with:

- one shared center-aligned up/down carrier;
- real target `50 MHz -> 10 kHz` (`TBPRD=2500`);
- independent U/V/W compare commands;
- one atomic three-phase shadow transaction;
- ZERO-only shadow load for the baseline;
- deterministic ZERO/PEAK/load event pulses;
- safe reset/disable behavior;
- exact 0/25/50/75/100% behavior;
- no carrier reset/truncation when compare commands change;
- no complementary outputs, dead time, trip-zone, ADC, encoder, SVPWM, CORDIC, or physical pin mapping yet.

The old `pwm_controller` from Steps 1–5 is a historical learning core. **Do not modify it into this new engine.**

---

## Repository organization

Create a portable IP directory independent of the legacy Vivado project:

```text
motor_control_ip/
  pwm/
    README.md
    rtl/
      motor_pwm_core.sv
    tb/
      motor_pwm_core_tb.sv
```

Create an independent Vivado project for learning/inspection:

```text
Motor_PWM/
  Motor_PWM.xpr
  Motor_PWM.srcs/
    constrs_1/
      new/
        motor_pwm_clock.xdc
```

The Vivado project shall **reference** the portable RTL/TB files above rather than duplicating source files into project-local directories.

Also create:

```text
scripts/step6b_motor_pwm_build.tcl
coordination/reports/step6b_codex_report.md
docs/reports/step6b/
```

Do not modify:

- `PWM_Controller/` legacy RTL/TBs;
- `PWM_Breathe/`;
- `simulink模型/`;
- Step 6A golden/reference files except reading them when useful.

---

## Tool/device baseline

- Vivado: 2026.1.
- Synthesis target: `xc7a200tfbg484-2`.
- Fabric clock: 50 MHz, 20.000 ns.
- Real motor PWM target: 10 kHz center-aligned.
- Real `TBPRD = 2500`.
- No physical PACKAGE_PIN/IOSTANDARD assignments in Step 6B.
- Do not generate a bitstream.
- Do not program hardware.

The standalone project may contain only a 20 ns clock constraint. Do not invent input/output delays or board pins.

---

## `motor_pwm_core` parameter/interface contract

Use a parameterized core so the testbench can run a reduced carrier while synthesis uses the real value.

Required parameter intent:

```systemverilog
parameter int unsigned TBPRD = 2500;
parameter int unsigned COUNTER_WIDTH = $clog2(TBPRD + 1);
```

`TBPRD` must be at least 2 in supported use.

Required top-level ports, with equivalent exact names unless Vivado/SystemVerilog syntax requires a narrowly documented adjustment:

```systemverilog
input  logic clk;
input  logic reset_n;
input  logic pwm_enable;

input  logic [COUNTER_WIDTH-1:0] cmp_u_cmd;
input  logic [COUNTER_WIDTH-1:0] cmp_v_cmd;
input  logic [COUNTER_WIDTH-1:0] cmp_w_cmd;
input  logic                     cmp_cmd_valid;
output logic                     cmp_cmd_ready;

output logic pwm_u;
output logic pwm_v;
output logic pwm_w;

output logic [COUNTER_WIDTH-1:0] tbctr;
output logic                     count_up;
output logic                     carrier_zero;
output logic                     carrier_peak;

output logic [COUNTER_WIDTH-1:0] cmp_u_shadow;
output logic [COUNTER_WIDTH-1:0] cmp_v_shadow;
output logic [COUNTER_WIDTH-1:0] cmp_w_shadow;
output logic [COUNTER_WIDTH-1:0] cmp_u_active;
output logic [COUNTER_WIDTH-1:0] cmp_v_active;
output logic [COUNTER_WIDTH-1:0] cmp_w_active;
output logic                     shadow_pending;
output logic                     compare_load_event;
```

`reset_n` is an active-LOW asynchronous-assert reset at the portable RTL boundary. A real board wrapper is responsible for appropriate reset-release synchronization; Step 6B has no board wrapper.

---

## Carrier contract

When enabled, registered carrier states are exactly:

```text
0,1,2,...,TBPRD-1,TBPRD,TBPRD-1,...,2,1,0,...
```

Direction meaning:

- `count_up=1`: current state is on the up-count half and the next interior movement is upward;
- `count_up=0`: current state is on the down-count half and the next interior movement is downward;
- when the carrier reaches ZERO, direction becomes UP;
- when the carrier reaches TBPRD, direction becomes DOWN.

Steady-state ZERO-to-ZERO interval:

```text
2*TBPRD clocks
```

For real `TBPRD=2500`:

```text
5000 clocks * 20 ns = 100 us = 10 kHz
```

### Event-pulse definition

`carrier_peak`:

- one clock wide;
- asserted on the registered clock where the carrier **enters** `TBPRD`;
- no repeated pulse while sitting at an endpoint.

`carrier_zero`:

- one clock wide;
- asserted on the registered clock where the running carrier **returns into** `0` from the down-count half;
- enabling from a disabled stationary ZERO state does not itself count as a recurring ZERO event.

When disabled, ZERO/PEAK event pulses remain LOW.

---

## Compare/PWM semantics

The core accepts integer compare counts. The later `duty_to_cmp` stage is not implemented in Step 6B.

For a valid interior compare:

```text
0 < CMP < TBPRD
```

the raw phase PWM must be equivalent to ePWM-like center-aligned actions:

```text
ZERO                     -> HIGH
up-count reaches CMP     -> LOW
down-count reaches CMP   -> HIGH
```

Therefore:

```text
HIGH duty = CMP / TBPRD
```

Explicit boundaries:

```text
CMP = 0       -> constant LOW
CMP >= TBPRD  -> constant HIGH
```

For registered-state implementation, a direction-aware level rule is allowed and recommended because it is exactly testable and avoids a one-clock visual offset:

```text
if CMP == 0:
    pwm = 0
else if CMP >= TBPRD:
    pwm = 1
else if count_up:
    pwm = (tbctr < CMP)
else:
    pwm = (tbctr <= CMP)
```

When implemented as registered next-state logic, evaluate this rule using the **next carrier state/direction and next active compare** so `tbctr`, active compare and output are visibly aligned after each clock.

This rule is functionally the required ZERO-set / up-clear / down-set action sequence for the discrete registered carrier.

All U/V/W channels share one carrier but use independent active compare values.

---

## Three-phase shadow-command contract

A compare command is one atomic transaction:

```text
{cmp_u_cmd, cmp_v_cmd, cmp_w_cmd}
```

A command is accepted only when:

```text
cmp_cmd_valid && cmp_cmd_ready
```

### Enabled operation

- If no command is pending, `cmp_cmd_ready=1`.
- An accepted command latches all U/V/W values into shadow registers on one clock and sets `shadow_pending=1`.
- While `shadow_pending=1`, `cmp_cmd_ready=0`; later commands cannot overwrite the pending transaction.
- The pending shadow set becomes active atomically on the next running `carrier_zero` event.
- U/V/W active registers update on the same clock.
- `compare_load_event` pulses exactly one clock on that atomic enabled load.
- Loading compare values must never reset, shorten, lengthen, or phase-jump the carrier.

### ZERO-collision rule

If a new command is accepted on the **same edge** that produces a ZERO event and there was no command pending before that edge, it is too late for that ZERO.

It must remain pending and load on the **following** ZERO.

Do not implement same-edge bypass/forwarding.

### Disabled operation

While `pwm_enable=0`:

- outputs are forced LOW;
- carrier is held at ZERO, direction UP;
- ZERO/PEAK/load event pulses are LOW;
- any stale `shadow_pending` is cleared/discarded because no running carrier boundary exists;
- `cmp_cmd_ready=1` after reset is released;
- an accepted command writes **both shadow and active U/V/W registers immediately**, with `shadow_pending=0`;
- this disabled preload does not assert `compare_load_event`.

Thus enabling always starts from a complete coherent active command, never from a half-written phase set.

---

## Reset contract

On `reset_n=0`, immediately force:

```text
tbctr = 0
count_up = 1
cmp_*_shadow = 0
cmp_*_active = 0
shadow_pending = 0
carrier_zero = 0
carrier_peak = 0
compare_load_event = 0
pwm_u = 0
pwm_v = 0
pwm_w = 0
```

After reset release, with `pwm_enable=0`, remain safely stationary until a command is optionally preloaded and PWM is enabled.

---

## Testbench contract

Use:

```text
TBPRD_TEST = 8
```

so one full carrier cycle is 16 clocks.

Drive stimulus on `negedge clk` and inspect stable registered outputs on `negedge clk` where practical, following the project's established race-free self-checking style.

The testbench must be fully self-checking and end with an unambiguous marker:

```text
ALL STEP 6B MOTOR PWM TESTS PASSED
```

Any failure must use `$error`/`$fatal` or equivalent so batch regression cannot silently pass.

### Required cases

1. **Reset/disabled safety**
   - asynchronous reset during arbitrary activity immediately makes all outputs LOW and state deterministic;
   - disabled state holds `tbctr=0`, direction UP and event pulses LOW.

2. **Disabled preload**
   - preload `{0,4,8}` while disabled;
   - verify shadow and active all update together;
   - verify no pending/load event;
   - enable and verify coherent start.

3. **Carrier/event timing**
   - verify successive running ZERO pulses are separated by exactly 16 clocks;
   - verify PEAK occurs exactly 8 clocks after ZERO;
   - verify `tbctr` sequence is `0..8..0` without duplicate interior counts or missing endpoint states.

4. **Boundary duty**
   - `CMP=0` => 0% HIGH;
   - `CMP=8` => 100% HIGH.

5. **Independent three-phase duty**
   - load U/V/W = `{2,4,6}`;
   - over a full ZERO-to-ZERO cycle verify HIGH clocks `{4,8,12}` out of 16 => `{25%,50%,75%}`;
   - every sampled PWM state must match the direction-aware reference rule.

6. **Mid-period shadow update**
   - while active `{2,4,6}`, accept `{6,2,4}` away from ZERO;
   - verify shadow changes immediately, active remains old, pending=1, ready=0;
   - verify the carrier sequence continues uninterrupted;
   - verify all three active values switch together on the next ZERO and load event pulses once.

7. **Pending overwrite rejection**
   - while pending, present a different command;
   - verify it is not accepted because ready=0 and shadow content remains the first pending transaction.

8. **ZERO-collision rule**
   - arrange valid+ready acceptance on the same clock that enters ZERO with no prior pending command;
   - verify active compares do not change on that ZERO;
   - verify the new command remains pending for one full carrier cycle;
   - verify it loads atomically at the next ZERO.

9. **Disable/re-enable**
   - disable mid-cycle and verify immediate safe LOW plus stationary ZERO state;
   - preload a new full command while disabled;
   - re-enable and verify the new command is the coherent active starting set.

10. **Pulse-width/event pulse sanity**
    - `carrier_zero`, `carrier_peak`, `compare_load_event` are one clock wide only;
    - no repeated load event occurs without a pending command.

The testbench may include reusable tasks/functions such as:

```text
apply_reset
send_cmp_command
wait_for_zero
check_full_cycle_counts
check_reference_levels
expect_active_compare
```

Keep it readable; do not introduce UVM.

---

## Vivado project/build contract

Create independent project:

```text
Motor_PWM/Motor_PWM.xpr
```

- design top: `motor_pwm_core`;
- simulation top: `motor_pwm_core_tb`;
- part: `xc7a200tfbg484-2`;
- target language: Verilog/SystemVerilog-compatible Vivado project;
- RTL/TB referenced from `motor_control_ip/pwm/...`;
- no copy of legacy `pwm_control.sv` inside this project.

Clock-only constraint:

```tcl
create_clock -name sys_clk -period 20.000 [get_ports clk]
```

No package pin, IOSTANDARD, input delay, output delay, false path or multicycle path may be invented.

### Required automated build

Create:

`scripts/step6b_motor_pwm_build.tcl`

Follow the evidence-oriented style of the Step 5 build scripts:

- require Vivado 2026.1;
- require correct part;
- make/add project files reproducibly;
- run Step 6B behavioral simulation and verify PASS marker;
- run legacy core/Step5A/Step5B simulations as regression if their existing projects/sources are available unchanged;
- synthesize the standalone motor PWM core;
- implement through route with the 20 ns clock constraint;
- save text evidence under `docs/reports/step6b/`;
- do not generate bitstream;
- do not program hardware.

Required Step 6B report files at minimum:

```text
docs/reports/step6b/motor_pwm_core_tb.txt
docs/reports/step6b/synth_utilization.rpt
docs/reports/step6b/impl_utilization.rpt
docs/reports/step6b/timing_summary.rpt
docs/reports/step6b/check_timing.rpt
docs/reports/step6b/build_result.txt
```

`build_result.txt` must say PASS only if simulation, synthesis, route and internal 50 MHz timing all succeed.

Because Step 6B intentionally has no board I/O contract, do not claim full board-level I/O timing sign-off. Any no-input-delay/no-output-delay coverage finding must be described rather than hidden with invented constraints.

---

## Portable-IP README

Create `motor_control_ip/pwm/README.md` documenting concisely:

- purpose of the core;
- 50 MHz / 10 kHz real baseline and parameterization;
- compare-to-duty convention;
- up/down endpoint sequence;
- shadow command handshake/load timing;
- ZERO-collision rule;
- enable/reset semantics;
- deliberate deferrals: duty fixed-point adapter, dead time, complementary outputs, trip, ADC, FOC.

This README is a technical interface note, not a tutorial essay.

---

## Synthesis/implementation acceptance

Step 6B does not optimize LUT/FF usage, but it must be structurally clean:

- no inferred latches;
- no multiple drivers;
- no combinational loops;
- no unresolved references;
- no width/sign warnings attributable to the new RTL;
- no vendor-specific primitive instantiations in `motor_pwm_core.sv`;
- no BRAM/DSP requirement expected for this PWM engine;
- routed internal timing at 50 MHz must pass (`WNS >= 0`, `TNS = 0`, `WHS >= 0`, `THS = 0`).

Report actual utilization; do not set a pass/fail resource ceiling yet.

---

## Explicitly deferred

Do not implement in Step 6B:

- normalized fixed-point `duty_to_cmp`;
- CORDIC/sin/cos;
- Clarke/Park/inverse Park;
- PI current control;
- SVPWM;
- complementary high/low outputs;
- dead time;
- trip/fault zone;
- minimum pulse width;
- ADC9238;
- encoder/Hall;
- 40-pin physical output mapping;
- AXI;
- Zynq/R5/A53 integration.

---

## Git workflow

Start from latest `main` after verifying PR #10 is merged and this task/spec are present.

Create branch:

`step6b-motor-pwm-core`

Do not include unrelated local changes. Existing local `.xpr`/spreadsheet edits must be preserved outside the task diff.

Suggested implementation commits may be split logically, for example:

```text
test: add Step 6B motor PWM self-checking testbench
feat: add three-phase center-aligned motor PWM core
build: add Step 6B Vivado project and routed evidence
docs: record Step 6B execution report
```

Final report:

`coordination/reports/step6b_codex_report.md`

Create PR:

`Step 6B: Add three-phase motor PWM core`

Stop at the open PR for ChatGPT review.

Do not merge automatically and do not continue to Step 6C1.

---

## Acceptance criteria

Step 6B is ready for ChatGPT review only when all are true:

1. The portable core is independent of legacy `pwm_controller`.
2. Real default parameters correspond to 50 MHz / 10 kHz / `TBPRD=2500`.
3. Testbench proves a 16-clock cycle at test `TBPRD=8`.
4. 0/25/50/75/100% behavior is automatically checked.
5. U/V/W independent compares share one carrier.
6. Mid-period command updates shadow only and never reset/truncate carrier.
7. Three active compares load atomically at ZERO.
8. ZERO-collision command waits until the following ZERO.
9. Pending command cannot be overwritten.
10. Reset and disable always force raw outputs LOW.
11. Disabled preload starts from one coherent three-phase active command.
12. Event pulses have deterministic one-clock behavior.
13. Vivado behavioral simulation passes with `ALL STEP 6B MOTOR PWM TESTS PASSED`.
14. Legacy regressions still pass or, if a local environment prevents one, the precise limitation is reported without modifying the legacy design.
15. Synthesis and routed implementation complete on `xc7a200tfbg484-2`.
16. Internal 50 MHz setup/hold timing passes.
17. No bitstream or physical pin mapping is added.
18. Only Step 6B scoped files are changed.
19. Codex report records exact commands, results, utilization, timing, warnings and any unresolved issue.
20. PR is left open for ChatGPT review.
