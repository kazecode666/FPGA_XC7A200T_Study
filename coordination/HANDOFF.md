# ChatGPT ↔ Codex Project Handoff

GitHub is the persistent source of truth between ChatGPT (architecture/review) and Codex (implementation/verification).

## Working agreement

- ChatGPT owns architecture, task definition, design decisions, acceptance criteria and PR review.
- Codex owns local inspection, authorized RTL/TB/Tcl/XDC edits, Vivado/Python execution, reports, commits, pushes and implementation PRs.
- Read this file and the current stage spec/task/plan instead of relying on copied chat text.
- Do not use SHA-256/file-hash verification. Use Git status/diff, executable tests, tool reports, waveforms and later physical behavior.
- Do not guess pins, clocks, I/O standards, mathematical equations, numeric scaling, PWM polarity or state/timing semantics.
- Preserve unrelated dirty local files. Work on a feature branch/worktree; do not destructively clean/reset them.
- Stop at the implementation PR for ChatGPT review. No automatic merge or next-stage work.

## Accepted baseline

- Steps 1–4: PWM learning baseline, synthesis, 50 MHz route/timing.
- Steps 5A/5B: BX72 LED blink/breathing demos, physically verified.
- Step 6A: basic PI-FOC Simulink audit, PR #10 merged.
- Step 6B: portable three-phase motor PWM, PR #11 merged.
- Step 6C1: fixed-point transforms, PR #12 merged.
- Step 6C2: fixed-point dq PI/feedforward/circular limiter, PR #14 merged at `da7151d773df10d7614bcc92ac453145ffda1463`.
- Step 6C3 design: simplified learning-oriented Sector-SVPWM contract, PR #15 merged at `b0ce6935cf5c304184da3bf5a5fc30b6c5f2490a`.

Accepted C2 divider `motor_control_ip/foc/rtl/mc_udiv_u72_u41.sv` is a read-only dependency for C3.

## Reference hierarchy and protected areas

Authority order:

1. stage-specific accepted FPGA spec;
2. Step 6 architecture;
3. Step 6A audited/golden mathematical behavior;
4. accepted C1/C2 interfaces;
5. historical DSP/MIL behavior as background only.

Read-only unless the current task explicitly authorizes edits:

- `PWM_Controller/`, `PWM_Breathe/`, `Motor_PWM/`;
- accepted `motor_control_ip/pwm/`;
- `simulink模型/`;
- Step 6A reference/golden/verifier files;
- accepted C1 RTL/TBs/ROM/fixtures/project/scripts/reports;
- accepted C2 RTL/TBs/fixtures/project/scripts/reports.

## Approved development sequence

```text
Step 6B   Motor PWM                         [MERGED]
Step 6C1  Numeric formats + transforms      [MERGED]
Step 6C2  dq PI + feedforward + limiter     [MERGED]
Step 6C3  Sector SVPWM -> normalized duty   [IMPLEMENTATION PLANNED]
Step 6C4  Full PI-FOC transaction core
Step 6D   PI-FOC -> PWM timing integration
```

ADC9238, encoder, complementary gates, dead time, trip, commissioning and MPSoC interfaces remain deferred.

## Current task: Step 6C3 implementation

Authoritative design:

```text
coordination/specs/step6c3_sector_svpwm.md
```

Codex task:

```text
coordination/tasks/step6c3_sector_svpwm.md
```

Implementation plan:

```text
coordination/tasks/step6c3_sector_svpwm_plan.md
```

The C3 implementation is deliberately learning-first. The goal is to visibly build and understand:

```text
v_alpha/v_beta/vdc
-> sector
-> X/Y/Z
-> T1/T2
-> L/M/H
-> normalized duty_u/v/w
```

Key frozen choices:

- inputs S25/F15;
- signed S26/F24 normalized duty outputs;
- Step 6A Sector-SVPWM, not Min-Max;
- exact integer-ratio treatment of the audited decimal constants;
- two parallel instances of accepted C2 U72/U41 divider;
- internal S34/F32 T1/T2;
- nearest/ties-away rounding;
- overmodulation only when `SUM > BASE`;
- no duty clamp in C3;
- one request in flight;
- fixed response N+128 = 2.56 us at 50 MHz;
- simple error handling and focused verification rather than product-scale hardening.

## Codex start command

After this implementation-plan documentation is accepted/merged and the user explicitly starts C3:

```text
Read coordination/HANDOFF.md first.

Then read:
  coordination/specs/step6c3_sector_svpwm.md
  coordination/tasks/step6c3_sector_svpwm.md
  coordination/tasks/step6c3_sector_svpwm_plan.md
  coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md
  coordination/reports/step6a_pi_foc_reference_audit.md

Also inspect the actual Step 6A golden CSV and accepted C2 divider source/TB read-only.

Start from latest accepted main and create branch:
  step6c3-sector-svpwm

Follow the learning-first five-stage plan:
  1. Python integer oracle and compact fixtures.
  2. Sector/XYZ RTL and six-sector/zero-vector bring-up.
  3. Full N+128 SVPWM top using two accepted C2 dividers.
  4. Actual Step 6A 160-row comparison plus focused boundary/reset/error tests.
  5. Standalone 50 MHz Vivado synth/route plus compact regressions.

Keep the implementation small and readable.
Do not modify accepted C1/C2/PWM/Step6A sources.
Do not add product-scale failure infrastructure unless a real discovered bug needs a targeted check.
Do not clamp duty in C3.
Do not replace the algorithm with Min-Max SVPWM.

Write:
  coordination/reports/step6c3_codex_report.md
and fresh evidence under:
  docs/reports/step6c3/

Open PR:
  Step 6C3: Add fixed-point sector SVPWM

STOP for ChatGPT review.
Do not merge automatically.
Do not start C4 or 6D.
Do not generate a bitstream or program hardware.
```
