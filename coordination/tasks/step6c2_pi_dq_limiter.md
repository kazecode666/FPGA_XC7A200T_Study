# Step 6C2 — Codex task: dq PI, feedforward and circular limiter

Date: 2026-09-18. This is an IMPLEMENTATION task description, not an execution report.

## Start gate and reading order

PR #12 is merged at `1207f3870ca7fd5497b2f7374bb7287654ed8c73`. Start only after the C2 documentation PR is accepted/merged and the user requests execution. Do not start from the documentation branch while its numerical decisions are still under review.

Read in order:

1. `coordination/HANDOFF.md`.
2. `coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`.
3. `coordination/specs/step6c2_pi_dq_limiter.md` (authoritative C2 arithmetic/interfaces).
4. `coordination/tasks/step6c2_pi_dq_limiter_plan.md`.
5. `coordination/reports/step6a_pi_foc_reference_audit.md` sections 5–6 and `scripts/reference_audit/step6a_pi_vectors.m` read-only.
6. The actual Step 6A golden CSV, its Python verifier, accepted C1 specification/source/README and `coordination/reports/step6c2_design_rationale.md`.

The design preflight is NOT a replacement for reading/checking the actual golden CSV.

## Goal and non-negotiable behavior

Implement a standalone S25/F15 measured-current/reference to S25/F15 limited-dq-voltage core. It owns S40/F24 PI and delayed-correction states, uses both elaboration-time gain profiles, retains feedforward signs and one-CONTROL-transaction anti-windup delay, and commits state atomically only on successful completion.

Core latency is exactly 256 rising-edge intervals; evaluator 16, sqrt 40, divider 72, limiter 160. These requirements must be measured with scoreboards, not inferred from a stage count. There is one request in flight, no output backpressure, and error responses are not usable voltage commands.

All literals, rounding points, intermediate widths, epsilon handling, conservative limiter quantization, command reset priority and error behavior come from the C2 spec. Do not alter them to obtain green tests or DSP counts. Stop and report a conflict with concrete evidence rather than silently changing the algorithm.

## Authorized files

Create the six C2 RTL files and six TBs enumerated in the spec. Create:

```text
motor_control_ip/foc/README_step6c2.md
motor_control_ip/foc/tb/vectors/step6c2/manifest.json
motor_control_ip/foc/tb/vectors/step6c2/*_vectors.txt
scripts/step6c2_pi_reference.py
scripts/step6c2_pi_reference_test.py
scripts/step6c2_pi_build.tcl
FOC_PI/FOC_PI.xpr
FOC_PI/FOC_PI.srcs/constrs_1/new/foc_pi_clock.xdc
coordination/reports/step6c2_pi_fixed_vectors.csv
coordination/reports/step6c2_codex_report.md
docs/reports/step6c2/
```

The manifest declares every generated fixture and exact count; generator/checker reject extra or missing C2 numerical artifacts. At minimum provide sqrt, divider, evaluator, limiter, core golden and stateful/error-stream fixtures. Profile identity and transaction IDs must be explicit. Preserve full OLD/NEXT state expectations, not just voltage outputs.

Protect/read-only: `PWM_Controller/`, `PWM_Breathe/`, `Motor_PWM/`, accepted `motor_control_ip/pwm/`, `simulink模型/`, all Step 6A source/golden/verifier files, the six accepted C1 RTL files, its four TBs/ROM/fixtures, `FOC_Transforms/`, C1 reference/build scripts and accepted reports. Do not expand this task to fix PR #12's non-blocking P3 comment; apply strict parsing/count checks to NEW C2 tests and retain the C1 issue as follow-up.

Do not modify frozen specifications or this task to match the implementation. Report proposed deviations for review. The completion report, not a premature HANDOFF edit, records implementation progress.

## Implementation and verification order

Execute the companion plan task-by-task. Write the independent Python integer oracle and tests before RTL; use Python `math.isqrt` and integer division as independent arithmetic references, not a translation of the RTL digit algorithms. Test expected constants using Decimal and distinct real-equation comparisons. Never generate expected outputs by reading the DUT.

Each RTL unit has a self-checking TB and an observed failing-before/fixed-after test cycle. A missing-module elaboration failure is scaffold evidence; retain at least one functional negative control/mutation for rounding, old-state ordering, fixture truncation and delayed anti-windup so green tests cannot be explained by missing checks. Mutations are disposable scratch files, never committed DUT changes.

Then integrate the persistent-state core, run all golden/stateful/error/protocol/reset cases, and perform the final full build and both-profile timing gates. Fresh scratch projects must not duplicate tracked source or disturb dirty local board/project files.

## Commands to deliver and support

From repository root, after creating the corresponding scripts:

```text
python scripts/step6c2_pi_reference_test.py
python scripts/step6c2_pi_reference.py --generate
python scripts/step6c2_pi_reference.py --check
python scripts/reference_audit/verify_step6a_vectors.py
python scripts/step6c1_fixed_transform_reference.py --check
vivado -mode batch -nojournal -log .Xil/step6c2_build.log -source scripts/step6c2_pi_build.tcl
```

Document the actual Vivado executable location on the execution machine; do not assume another user's drive path. The build must invoke/check these steps, six C2 TBs, four C1 TBs, Step 6B PWM TB and two independent PI-profile routes. It must use the checked-in portable sources and audit XPR relocation/source staging. The final end-to-end command must run after the last build-script edit.

Required markers:

```text
ALL STEP 6C2 FXP TESTS PASSED
ALL STEP 6C2 ISQRT TESTS PASSED
ALL STEP 6C2 UDIV TESTS PASSED
ALL STEP 6C2 PI EVAL TESTS PASSED
ALL STEP 6C2 LIMITER TESTS PASSED
ALL STEP 6C2 PI DQ CORE TESTS PASSED
STEP6C2_BUILD_PASS
```

Require correct exact fixture counts, no fatal/error marker and successful exit. A single PASS substring anywhere in an old log is not evidence. Build results are tagged by fresh run and profile; IN_PROGRESS/FAILED cannot be interpreted as PASS.

## Acceptance report checklist

- Explain every integer format, literal, rounding point, OLD/NEXT update and reset/error priority.
- Actual 160-row CSV ranges, both independent 80-row replays, maxima versus source per column with worst rows; <=0.002 V gates and delayed-column alignment.
- Independent integer-equality results for all outputs/state snapshots, successful/error/aborted transaction counts, exact latencies and idle invariance.
- Limiter maximum ideal component error, norm excess, scale threshold and full-rail behavior; no claim of a motor current operating limit.
- Both PI-profile synthesis and route results, DSP/BRAM/LUT/FF hierarchy and actual setup/hold/pulse-width/route completeness; preserved board I/O warnings.
- Portable XPR relocation and source/ROM/fixture staging evidence, strict simulator failure detection and final script rerun.
- All legacy/C1 regressions unchanged; Git diff scope audit and preserved local dirty files.
- No physical hardware, no bitstream, no C3/C4/6D integration; list failures and unexecuted checks honestly.

## Branch, PR and stop point

Pull latest accepted main, create `step6c2-pi-dq-limiter`, and commit small tested units. Do not use destructive checkout/reset/clean to remove unrelated local modifications. Use an isolated worktree when needed. No SHA-256/file-hash validation.

Open PR `Step 6C2: Add fixed-point dq PI and circular limiter`, link the execution report and evidence, and STOP for ChatGPT review. Do not merge automatically, begin C3 or modify physical outputs.
