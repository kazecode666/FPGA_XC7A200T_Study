# ChatGPT ↔ Codex Project Handoff

This file is the persistent coordination index for the FPGA learning / motor-control project. GitHub is the source of truth between ChatGPT (architecture/review) and Codex (execution).

## Working agreement

- ChatGPT owns architecture, task definition, design decisions, acceptance criteria, and PR review.
- Codex owns local repository inspection, RTL/testbench/Tcl/XDC edits when authorized, Vivado/MATLAB execution, reports, commits, pushes, and PR creation.
- Read this file and the current task/spec from the repository instead of relying on copied chat text.
- Do not use SHA-256/file-hash verification for this learning project. Use Git status/diff, simulation, synthesis, implementation, timing, DRC/report evidence, and physical behavior when a hardware step is authorized.
- Do not guess board pins, clocks, I/O standards, algorithm equations, PWM polarity/count semantics, numeric formats, or timing semantics.
- Each implementation/audit task uses a feature branch and stops at an open PR for ChatGPT review unless explicitly instructed otherwise.

## Accepted baseline

Completed and accepted:

- Step 1: self-checking PWM testbench.
- Step 2: compare-value semantics and boundaries.
- Step 2.5: registered PWM output/counter alignment.
- Step 3: synthesis baseline.
- Step 4: 50 MHz constraint, implementation and post-route timing.
- Step 5A: BX72 LED blink board bring-up, physically verified.
- Step 5B: BX72 breathing LED demo, physically verified.
- Step 6A: basic PI-FOC Simulink reference audit, PR #10 merged.

Step 6A accepted reference artifacts on `main`:

- `coordination/reports/step6a_pi_foc_reference_audit.md`
- `coordination/reports/step6a_pi_foc_golden_vectors.csv`
- `scripts/reference_audit/step6a_pi_vectors.m`
- `scripts/reference_audit/verify_step6a_vectors.py`

The advanced DPCC/DPICC/PICDO branches are not part of the first FPGA current-loop baseline.

## Frozen BX72 hardware facts

- Target learning-board part: `xc7a200tfbg484-2`.
- Physical JTAG detection: `xc7a200t`.
- Board clock: 50 MHz.
- `clk`: Y18, Bank 14, LVCMOS33.
- `key2_n`: V17, Bank 14, LVCMOS33, active LOW.
- `led1`: AA18, Bank 14, LVCMOS33, active HIGH.
- `CFGBVS = VCCO`.
- `CONFIG_VOLTAGE = 3.3`.

Step 6B does not use physical pins except the logical 50 MHz clock constraint in its standalone project; no board pin mapping is authorized.

## Protected legacy/reference areas

- `PWM_Controller/` contains the Steps 1–5 learning PWM core/demos.
- `PWM_Breathe/` contains the accepted breathing demo.
- `simulink模型/` contains algorithm/reference assets.

Do not mutate the legacy `pwm_controller` into the motor-control PWM engine. Its old `counter >= compare` / `config_en`-resets-counter semantics remain a historical learning baseline only.

## Motor-control reference priority

When references disagree:

1. approved FPGA motor-control architecture contract;
2. Step 6A PI-FOC audit/golden vectors for math;
3. MIL/ControlCore Simulink for algorithm/closed-loop reference;
4. proven F28335 physical experience;
5. unverified F28388D code-generation integration as historical reference only.

Do not inherit unresolved historical DSP/MIL raw PWM count or polarity conventions into the new FPGA motor PWM.

## Approved Step 6 architecture

The user explicitly approved:

`coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`

on 2026-09-17.

Implementation decomposition:

```text
Step 6B   Motor PWM Core
Step 6C1  Numeric format + Clarke/Park/sincos foundation
Step 6C2  PI + dq limiter
Step 6C3  Sector SVPWM -> normalized duty
Step 6C4  Full PI-FOC transaction core
Step 6D   PI-FOC -> PWM timing integration
```

First FPGA PI-FOC inputs will come from testbench/golden vectors. ADC9238 and encoder interfaces are intentionally deferred until the math chain is verified.

## Current task

**Step 6B — Motor PWM Core**

Governing task specification:

`coordination/tasks/step6b_motor_pwm_core.md`

Implementation plan:

`coordination/tasks/step6b_motor_pwm_core_plan.md`

Approved architecture:

`coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`

### Frozen Step 6B contract

- Vivado 2026.1.
- Target part `xc7a200tfbg484-2`.
- 50 MHz fabric clock / 20 ns.
- 10 kHz center-aligned PWM.
- Real default `TBPRD=2500`.
- One shared U/V/W up/down carrier.
- Integer compare semantics: `HIGH duty = CMP/TBPRD`.
- `CMP=0` -> constant LOW.
- `CMP>=TBPRD` -> constant HIGH.
- Atomic three-phase shadow command.
- Enabled shadow load: next ZERO only.
- A command accepted on the same ZERO edge is deferred to the following ZERO.
- Pending command cannot be overwritten.
- Disable/reset force raw outputs LOW and hold carrier at ZERO/UP.
- Disabled command may preload complete active+shadow U/V/W immediately.
- No `duty_to_cmp`, FOC, SVPWM, dead time, complementary outputs, trip, ADC, encoder, AXI, physical pin mapping, bitstream or hardware programming in Step 6B.

### Required portable source layout

```text
motor_control_ip/pwm/README.md
motor_control_ip/pwm/rtl/motor_pwm_core.sv
motor_control_ip/pwm/tb/motor_pwm_core_tb.sv
Motor_PWM/Motor_PWM.xpr
Motor_PWM/Motor_PWM.srcs/constrs_1/new/motor_pwm_clock.xdc
scripts/step6b_motor_pwm_build.tcl
```

Primary verification marker:

```text
ALL STEP 6B MOTOR PWM TESTS PASSED
```

Required final report:

`coordination/reports/step6b_codex_report.md`

Required routed evidence directory:

`docs/reports/step6b/`

Branch:

`step6b-motor-pwm-core`

PR title:

`Step 6B: Add three-phase motor PWM core`

Codex must stop at the open PR and must not continue to Step 6C1.

## Codex start command

```text
Read coordination/HANDOFF.md first.
Then read:
  coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md
  coordination/tasks/step6b_motor_pwm_core.md
  coordination/tasks/step6b_motor_pwm_core_plan.md

Execute Step 6B exactly as specified and plan-driven/TDD where practical.
Start from latest main, create branch step6b-motor-pwm-core, keep legacy PWM/Simulink assets unchanged, implement the portable three-phase center-aligned shadow-compare motor PWM core, run the required self-checking and legacy regressions, run Vivado 2026.1 synthesis/route/timing, write the required reports, open PR "Step 6B: Add three-phase motor PWM core", and stop for ChatGPT review.

Do not merge automatically. Do not begin Step 6C1.
```
