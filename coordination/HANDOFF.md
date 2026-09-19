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
- Step 6C1: fixed-point Clarke/sincos/Park/inverse Park, PR #12 merged at `1207f3870ca7fd5497b2f7374bb7287654ed8c73` on 2026-09-18.

Accepted C1 source/evidence: `motor_control_ip/foc/rtl/mc_fxp_pkg.sv`, `mc_clarke.sv`, `mc_sincos_lut.sv`, `mc_park.sv`, `mc_inv_park.sv`, `mc_current_transform.sv`; existing ROM/TBs/fixtures; `FOC_Transforms/`; C1 scripts and reports. Its six-DSP result applies to the current-transform synthesis top, not a complete PI-FOC controller.

The non-blocking PR #12 P3 standalone-test fixture-count suggestion remains follow-up; do not silently alter accepted C1 tests as part of C2.

## Reference hierarchy and protected areas

Authority order: approved FPGA architecture and stage-specific numeric contract; Step 6A audit/golden mathematical behavior; MIL/ControlCore model; proven F28335 experience; unverified F28388D integration as historical reference.

Read-only unless a task explicitly says otherwise: `PWM_Controller/`, `PWM_Breathe/`, `Motor_PWM/`, accepted `motor_control_ip/pwm/`, `simulink模型/`, all Step 6A references/golden/verifier files, and accepted C1 sources/ROM/TBs/fixtures/project/scripts/reports.

Step 6A reference files:

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
Step 6C2  dq PI + feedforward + limiter     [DESIGN PREPARED]
Step 6C3  Sector SVPWM -> normalized duty
Step 6C4  Full PI-FOC transaction core
Step 6D   PI-FOC -> PWM timing integration
```

All C2 inputs remain testbench/golden driven. ADC9238, encoder, complementary gates, dead time, trip, commissioning and MPSoC interfaces remain deferred.

## Current task: Step 6C2 design/implementation handoff

Architecture: `coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`.

C2 documents:

```text
coordination/specs/step6c2_pi_dq_limiter.md
coordination/tasks/step6c2_pi_dq_limiter.md
coordination/tasks/step6c2_pi_dq_limiter_plan.md
coordination/reports/step6c2_design_rationale.md
```

**Gate:** merging the C2 documentation PR accepts the written design. It does not itself run implementation or certify tests. Codex begins only when the user starts the C2 implementation task from accepted main. The previous C1-only start command is superseded by this stage-specific gate.

Key C2 choices: separate S32/F24 PI gains and S32/F30 motor constants; S40/F24 voltage/integrator/correction state; C1-compatible S25/F15 external currents/voltages; S32/F16 electrical speed; exact iterative isqrt/division; one request in flight; core output at N+256; successful atomic state commit; explicit invalid-bus/overflow responses with state hold. Both gain profiles must be independently simulated and routed. No fixed DSP count is promised.

The C1 format remains unchanged: phase currents S24/F15, transform values S25/F15, sin/cos S18/F16, 16-bit binary angle. Do not impose C1's sin/cos coefficient width on Kp or claim its throughput/latency for the recursive PI core.

## Codex start command (after design acceptance and user instruction)

```text
Read coordination/HANDOFF.md first.
Read the Step 6 architecture, coordination/specs/step6c2_pi_dq_limiter.md,
coordination/tasks/step6c2_pi_dq_limiter.md and its _plan.md companion.
Then read the actual Step 6A audit/golden CSV/verifier, its stimulus-generation
source read-only, accepted C1 interfaces, and C2 design rationale.

Start from latest accepted main and create branch step6c2-pi-dq-limiter.
Execute only Step 6C2 using the frozen specification and test-first plan.
Implement independent Python oracle first, then C2 fixed-point helpers,
iterative isqrt/division, stateless PI evaluator, circular limiter and
single-in-flight persistent-state core. Preserve OLD/NEXT state semantics,
command reset behavior, fixed completion slots and atomic error-safe updates.

Run all C2 tests, the actual 160-row reference comparison, unchanged Step 6A/
6B/C1 regressions, and Vivado 2026.1 synthesis/route for BOTH PI profiles.
Use fresh scratch work and new C2 evidence; do not overwrite accepted reports.
Write coordination/reports/step6c2_codex_report.md and evidence under
 docs/reports/step6c2/.
Open PR "Step 6C2: Add fixed-point dq PI and circular limiter" and STOP.
Do not merge, start C3, edit protected references, generate a bitstream,
or program hardware. Report any spec conflict instead of changing a gate.
```
