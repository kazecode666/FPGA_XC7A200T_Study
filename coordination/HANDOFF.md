# ChatGPT ↔ Codex Project Handoff

GitHub is the persistent source of truth between ChatGPT (architecture/review) and Codex (implementation/verification).

## Working agreement

- ChatGPT owns architecture, task definition, design decisions, acceptance criteria and PR review.
- Codex owns local inspection, authorized RTL/TB/Tcl/XDC edits, Vivado/MATLAB/Python execution, reports, commits, pushes and implementation PRs.
- Read this index and the current repository spec/task instead of relying on copied chat text.
- Do not use SHA-256/file-hash verification. Use Git status/diff, executable tests, tool reports, waveforms and later physical behavior.
- Do not guess pins, clocks, I/O standards, mathematical equations, numeric scaling, PWM polarity or state/timing semantics.
- Preserve unrelated dirty local files. Work on a feature branch/worktree; do not destructively clean/reset them.
- Stop at the implementation PR for ChatGPT review. No automatic merge or next-stage work.

## Accepted baseline

Steps 1–4: self-checking PWM, compare boundaries, registered output/counter alignment, synthesis, 50 MHz route and timing.

Steps 5A/5B: BX72 LED blink and breathing demos, physically verified.

- Step 6A: basic PI-FOC Simulink audit, PR #10 merged.
- Step 6B: portable three-phase PWM, PR #11 merged.
- Step 6C1: fixed-point Clarke/sincos/Park/inverse Park, PR #12 merged at `1207f3870ca7fd5497b2f7374bb7287654ed8c73`.
- Step 6C2: fixed-point dq PI, feedforward and circular limiter, PR #14 merged at `da7151d773df10d7614bcc92ac453145ffda1463` on 2026-09-19.

Accepted C1 source includes `mc_fxp_pkg`, Clarke, LUT sin/cos, Park/inverse Park and `mc_current_transform`.

Accepted C2 source includes `mc_pi_fxp_pkg`, iterative integer sqrt/divider, `mc_pi_dq_eval`, `mc_dq_limiter` and `mc_pi_dq_core`. C2 core latency is 256 clocks at 50 MHz and only `output_valid && error_code==OK` is a usable voltage result.

## Reference hierarchy and protected areas

Authority order: approved FPGA architecture and stage-specific numeric contract; Step 6A audit/golden mathematical behavior; MIL/ControlCore model; proven F28335 experience; unverified F28388D integration as historical reference.

Read-only unless a task explicitly authorizes edits:

- `PWM_Controller/`, `PWM_Breathe/`, `Motor_PWM/`;
- accepted `motor_control_ip/pwm/`;
- `simulink模型/`;
- Step 6A reference/golden/verifier files;
- accepted C1 RTL/TBs/ROM/fixtures/project/scripts/reports;
- accepted C2 RTL/TBs/fixtures/project/scripts/reports.

Step 6A references:

```text
coordination/reports/step6a_pi_foc_reference_audit.md
coordination/reports/step6a_pi_foc_golden_vectors.csv
scripts/reference_audit/step6a_pi_vectors.m
scripts/reference_audit/verify_step6a_vectors.py
```

## Approved development sequence

```text
Step 6B   Motor PWM                         [MERGED]
Step 6C1  Numeric formats + transforms      [MERGED]
Step 6C2  dq PI + feedforward + limiter     [MERGED]
Step 6C3  Sector SVPWM -> normalized duty   [DESIGN REVIEW]
Step 6C4  Full PI-FOC transaction core
Step 6D   PI-FOC -> PWM timing integration
```

ADC9238, encoder, complementary gates, dead time, trip, commissioning and MPSoC interfaces remain deferred until the math/control chain is integrated and verified.

## Current task: Step 6C3 design review

Architecture:

```text
coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md
```

C3 design:

```text
coordination/specs/step6c3_sector_svpwm.md
```

The C3 goal is deliberately learning-oriented: first make the full Sector -> XYZ -> T1/T2 -> L/M/H -> U/V/W normalized-duty chain readable and working, then add focused boundary/error checks and standalone Vivado timing evidence.

Key C3 choices under review:

- inputs `v_alpha/v_beta/vdc` remain S25/F15;
- outputs `duty_u/v/w` are signed S26/F24 normalized duty;
- preserve Step 6A Sector-SVPWM instead of replacing it with Min-Max;
- evaluate 0.866/1.7321 decimal boundaries using exact integer ratios;
- reuse the accepted C2 `mc_udiv_u72_u41` twice in parallel;
- internal normalized T1/T2 are S34/F32 with nearest/ties-away rounding;
- preserve small negative mathematical dwell/duty near boundaries; no duty clamp in C3;
- normalize overmodulation when `a+b > 10000*vdc_raw`;
- one request in flight, fixed C3 response at N+128 (2.56 us @ 50 MHz);
- simple INVALID_VDC/RANGE_ERROR/INTERNAL_ERROR responses;
- verification prioritizes integer-oracle bit-exact behavior, Step 6A 160-row comparison and key directed cases rather than product-scale failure infrastructure;
- standalone C3 synthesis/route at 50 MHz; no bitstream/hardware.

Design preflight against the actual Step 6A CSV found four known sector mismatches only at explicit `edge_1_±1.732` boundary rows after F15 input quantization; the proposed normalized-duty comparison differed by about 1.2e-5 maximum, below the proposed 5e-5 algorithm-comparison gate. These are design observations, not implementation test evidence.

## Gate and next action

This branch is a documentation/design review only. No C3 RTL implementation is authorized by the document alone.

After the user reviews and accepts/merges the C3 design document, ChatGPT will create a concise C3 Codex task/implementation plan. That plan will prioritize:

```text
oracle
-> sector/XYZ
-> visible six-sector/zero-vector bring-up
-> T1/T2 and overmodulation
-> U/V/W duty
-> Step 6A comparison
-> focused boundary/reset/error checks
-> C3 synth/route
-> compact regressions
-> implementation PR
```

Do not start C3 implementation, C4, C6D, bitstream generation or hardware programming until that gate is explicitly passed.
