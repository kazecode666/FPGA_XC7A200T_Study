# ChatGPT ↔ Codex Project Handoff

This file is the persistent coordination index for the FPGA learning / motor-control project. GitHub is the source of truth between ChatGPT (architecture/review) and Codex (execution).

## Working agreement

- ChatGPT owns architecture, task definition, design decisions, acceptance criteria, and PR review.
- Codex owns local repository inspection, RTL/testbench/Tcl/XDC edits when authorized, Vivado/MATLAB/Python execution, reports, commits, pushes, and PR creation.
- Read this file and the current task/spec from the repository instead of relying on copied chat text.
- Do not use SHA-256/file-hash verification. Use Git status/diff, executable tests, synthesis/implementation/timing reports, waveforms, and later physical behavior.
- Do not guess board pins, clocks, I/O standards, algorithm equations, PWM polarity/count semantics, numeric formats, or timing semantics.
- Each implementation task uses a feature branch and stops at an open PR for ChatGPT review unless explicitly instructed otherwise.

## Accepted baseline

Completed and accepted:

- Step 1: self-checking PWM testbench.
- Step 2: compare semantics and boundaries.
- Step 2.5: registered PWM output/counter alignment.
- Step 3: synthesis baseline.
- Step 4: 50 MHz constraint, route and post-route timing.
- Step 5A: BX72 LED blink bring-up, physically verified.
- Step 5B: BX72 breathing LED demo, physically verified.
- Step 6A: basic PI-FOC Simulink reference audit, PR #10 merged.
- Step 6B: portable three-phase motor PWM core, PR #11 merged.

Accepted Step 6B motor PWM source:

`motor_control_ip/pwm/rtl/motor_pwm_core.sv`

Step 6A reference artifacts remain:

- `coordination/reports/step6a_pi_foc_reference_audit.md`
- `coordination/reports/step6a_pi_foc_golden_vectors.csv`
- `scripts/reference_audit/step6a_pi_vectors.m`
- `scripts/reference_audit/verify_step6a_vectors.py`

## Protected/reference areas

Do not modify unless a task explicitly authorizes it:

- `PWM_Controller/`
- `PWM_Breathe/`
- `simulink模型/`
- accepted `motor_control_ip/pwm/` behavior
- Step 6A golden/reference files

## Motor-control reference priority

When references disagree:

1. approved FPGA motor-control architecture/spec;
2. Step 6A audit/golden vectors for mathematical convention;
3. MIL/ControlCore model as algorithm/closed-loop reference;
4. proven F28335 physical experience;
5. unverified F28388D code-generation integration as historical reference only.

## Approved Step 6 decomposition

```text
Step 6B   Motor PWM Core                         [MERGED]
Step 6C1  Numeric format + Clarke/Park/sincos   [CURRENT]
Step 6C2  PI + dq limiter
Step 6C3  Sector SVPWM -> normalized duty
Step 6C4  Full PI-FOC transaction core
Step 6D   PI-FOC -> PWM timing integration
```

First FPGA current-loop inputs are still testbench/golden-vector driven. ADC9238 and encoder interfaces remain deferred until the math chain is verified.

## Current task

**Step 6C1 — Fixed-Point FOC Transform Foundation**

Approved architecture:

`coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`

Authoritative Step 6C1 numeric/transform spec:

`coordination/specs/step6c1_fixed_point_transforms.md`

Task:

`coordination/tasks/step6c1_fixed_point_transforms.md`

Implementation plan:

`coordination/tasks/step6c1_fixed_point_transforms_plan.md`

### Frozen Step 6C1 numeric contract

```text
ia/ib/ic            signed 24, F=15
i_alpha/i_beta      signed 25, F=15
id/iq               signed 25, F=15
vd/vq, v_alpha/beta signed 25, F=15
coefficients         signed 18, F=16
sin/cos              signed 18, F=16
theta_e              unsigned 16-bit binary angle

C_TWO_THIRDS = 43691
C_INV_SQRT3  = 37837
SIN_COS_ONE  = 65536
```

Implementation choice:

- quarter-wave `4096 x 18` sine ROM;
- 16-bit binary angle, LUT address from `theta_e[15:2]` with quadrant symmetry;
- no CORDIC in Step 6C1;
- no floating-point IP;
- 25x18 signed multiplication inference targeting DSP48-class resources;
- full-precision products/accumulators before round+saturate;
- magnitude-based round-to-nearest, ties away from zero;
- no silent wraparound;
- fixed-point Python model is the bit-exact oracle;
- Step 6A Simulink vectors are algorithm/reference comparisons, not bit-exact sine lookup targets.

Expected `mc_current_transform` resource shape is approximately 6 DSP48E1 and 2 BRAM36, but portability is more important than forcing an exact primitive count.

### Step 6C1 scope

Implement:

- `mc_fxp_pkg`
- `mc_clarke`
- `mc_sincos_lut`
- `mc_park`
- `mc_inv_park`
- `mc_current_transform`
- deterministic ROM/reference generator
- self-checking TBs
- standalone `FOC_Transforms` Vivado project
- synthesis/route/timing/resource evidence

Do not implement:

- PI / feedforward / anti-windup
- dq limiter
- SVPWM
- duty-to-CMP or PWM integration
- ADC9238
- encoder/QEP
- dead time/trip
- bitstream/hardware
- Step 6C2

Required integration marker:

```text
ALL STEP 6C1 TRANSFORM TESTS PASSED
```

Branch:

```text
step6c1-fixed-point-transforms
```

PR title:

```text
Step 6C1: Add fixed-point FOC transform foundation
```

Codex stops at the open PR.

## Codex start command

```text
Read coordination/HANDOFF.md first.

Then read, in order:
  coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md
  coordination/specs/step6c1_fixed_point_transforms.md
  coordination/tasks/step6c1_fixed_point_transforms.md
  coordination/tasks/step6c1_fixed_point_transforms_plan.md
  coordination/reports/step6a_pi_foc_reference_audit.md

Execute Step 6C1 exactly as specified and plan-driven/TDD.

Start from latest main and create branch step6c1-fixed-point-transforms.
Build the deterministic fixed-point Python oracle and quarter-wave ROM first, then Clarke, sincos LUT, Park/inverse Park, and coherent mc_current_transform.
Keep transaction valid/data aligned and prove back-to-back transaction identity.
Use portable signed SystemVerilog inference; do not instantiate Artix-7 DSP/BRAM primitives.
Run Step 6C1 unit/integration tests, Step 6A verifier and Step 6B PWM regression.
Run Vivado 2026.1 synthesis/route/internal timing and audit DSP48/BRAM inference.
Write coordination/reports/step6c1_codex_report.md and evidence under docs/reports/step6c1/.
Open PR "Step 6C1: Add fixed-point FOC transform foundation" and stop for ChatGPT review.

Do not merge automatically.
Do not begin Step 6C2.
Do not modify protected legacy/Simulink/PWM reference assets.
Do not generate a bitstream or program hardware.
```
