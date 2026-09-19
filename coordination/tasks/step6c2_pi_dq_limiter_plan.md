# Step 6C2 PI and Circular Limiter Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans to execute task-by-task after design acceptance. Keep a review gate between independently testable units. This document does not start implementation.

**Goal:** Build and verify the standalone fixed-point dq PI/feedforward/limiter transaction core.

**Architecture:** Stateless PI evaluation consumes captured OLD state; the iterative limiter produces the current limited voltages and NEXT corrections. A single-in-flight core commits all state at N+256 only on success. No accepted C1 source changes.

**Tech Stack:** Python standard library, SystemVerilog, Vivado 2026.1, Tcl, XDC.

**Spec:** `coordination/specs/step6c2_pi_dq_limiter.md`.

## Global constraints

- Execution starts from accepted main containing this spec, after the user starts C2.
- `xc7a200tfbg484-2`, 20.000 ns sys_clk, no board pins/I/O standards/bitstream.
- S25/F15 current/voltage interface, S32/F16 speed, S40/F24 persistent voltage states, S32/F24 PI gains and S32/F30 motor constants.
- Fixed edge intervals: evaluator 16, sqrt 40, divider 72, limiter 160, core 256.
- Explicit OLD/NEXT semantics, one state commit per successful transaction, error state hold.
- All files/markers/protection rules in the task book apply to every task.

## Task 1 — Independent oracle, format checks and actual source replay

**Files:** Create `scripts/step6c2_pi_reference.py`, `scripts/step6c2_pi_reference_test.py`, C2 fixtures/manifest and `coordination/reports/step6c2_pi_fixed_vectors.csv`.

**Interfaces:** Python functions `round_shift_away(x:int,shift:int)->int`, `limiter_raw(ud:int,uq:int,vdc:int)->dict`, `pi_step(state:tuple[int,int,int,int,int], sample:dict, profile:int)->dict`. State tuple order is xd,xq,du_d,du_q,sat. Result includes error_code, outputs, old_state and next_state. CLI supports mutually exclusive --generate/--check; check regenerates expected data in memory without writes.

- [ ] Read actual CSV and record exact profiles, row count/order, reset fields and min/max of all relevant columns. Keep each 80-row profile sequence intact.
- [ ] Write explicit unit expectations BEFORE implementing helpers. Include:

```python
assert round_shift_away(-8060928,16) == -123
assert round_shift_away(32768,16) == 1
assert round_shift_away(-32768,16) == -1
assert round_shift_away(-(1<<95),16) == -(1<<79)
```

- [ ] Run `python scripts/step6c2_pi_reference_test.py`; capture the intended failing result.
- [ ] Implement exact constants with Decimal modes, independent integer R/isqrt/division and spec state ordering. Check physical ranges without clipping invalid CLI/fixture inputs into validity.
- [ ] Add the spec's three explicit one-amp updates and command-reset/old-du/error-hold checks. Use high-precision real equations for selected limiter boundaries and double precision only where its resolution is adequate.
- [ ] Generate deterministic fixtures. Fix seeds in code: master `0x6C22026`; derive disjoint streams by named fixed offsets. Record exact counts/schema/seed in manifest; verify manifest against regeneration, not against itself.
- [ ] Run generator twice and compare text/Git diff; run --check, explicit tests and optimized-interpreter safety tests. Report actual 160-row column maxima and any saturation-flag threshold differences.
- [ ] Commit oracle/tests/fixtures only after checks pass. Do not claim source replay from reconstructed stimuli alone.

## Task 2 — Fixed-point RTL helper package

**Files:** `mc_pi_fxp_pkg.sv`, `mc_pi_fxp_tb.sv` under the authorized RTL/TB directories.

**Interfaces:** The package supplies the literal formats/constants, `pi_round_shift_s96(value,shift)` returning signed [95:0], `pi_fits_s40(value)` and `pi_fits_s25(value)`. All callers extend operands explicitly and use literal shifts; do not edit C1 helpers.

- [ ] Write a failing TB that checks all constants, both profiles, R ties/exact multiples/S96 minimum, shifts 0/9/15/24/32/37/95 and signed destination rail +/-1 predicates.
- [ ] Run it and retain RED evidence; implement magnitude-based 97-bit abs/round and explicit signed comparisons.
- [ ] Check no unknown helper result on valid data; run all directed cases. In a scratch mutation, use arithmetic shift for a negative tie and confirm TB failure.
- [ ] Capture GREEN marker `ALL STEP 6C2 FXP TESTS PASSED`; commit the tested helper unit.

## Task 3 — Exact iterative square root and divider

**Files:** `mc_isqrt_u80.sv`, `mc_isqrt_u80_tb.sv`, `mc_udiv_u72_u41.sv`, `mc_udiv_u72_u41_tb.sv`.

**Interfaces:** Use the spec's U80->U40/U41 and U72/U41->U72/U41 interfaces with valid/ready, async-abort control and fixed +40/+72 response timing.

- [ ] Write independent fixtures/TBs checking integer results, remainders, readiness, exact latency, idle hold, ignored busy input and reset abort. Run each against its absent/failing unit first.
- [ ] Implement one digit-pair per clock for sqrt; below is algorithm pseudocode, not a combinational RTL loop:

```python
root = rem = 0
for i in range(39,-1,-1):
    rem = (rem << 2) | ((radicand >> (2*i)) & 3)
    trial = (root << 2) | 1
    if rem >= trial:
        rem -= trial
        root = (root << 1) | 1
    else:
        root <<= 1
```

- [ ] Use a 44-bit working remainder/trial path, 40-bit root plus explicit temporary growth, and verify returned U41 remainder. Check `root^2 <= radicand < (root+1)^2` in sufficiently wide TB arithmetic.
- [ ] Implement unsigned restoring division, one numerator bit per clock:

```python
quotient = rem = 0
for i in range(71,-1,-1):
    rem = (rem << 1) | ((numerator >> i) & 1)
    if rem >= denominator:
        rem -= denominator
        quotient |= 1 << i
```

- [ ] Use 42-bit shifted remainder and full U72 quotient. Denominator zero returns zero data/error at +72, without entering a divide loop that depends on zero comparisons.
- [ ] Exhaust low-domain cases and test full-width maxima, square/quotient neighbors and at least 1024 seeded random inputs per primitive. Fixed fixture count must be checked exactly.
- [ ] Capture both required GREEN markers; commit sqrt and divider independently so either unit can be reviewed/rejected separately.

## Task 4 — Stateless PI evaluator

**Files:** `mc_pi_dq_eval.sv`, `mc_pi_dq_eval_tb.sv`.

**Consumes:** captured currents/references/speed, reset commands and OLD S40 xd/xq/du states, `PI_PROFILE` parameter. **Produces:** S40 raw voltages and tentative next integral states/error_code at +16; no persistent integrator owned here.

- [ ] Write TB for both elaborated profiles, explicit one-amp rows, feedforward signs, q-zero preserving d cross term, old-versus-new state and final sum range checks. Drive deliberately large but canceling wide intermediate terms to ensure no premature S40 cast.
- [ ] Observe RED; implement full-width products/pipelining and the exact R points from spec section 4. Apply resets before selected final-range checks. Never fold a current saturation correction into this evaluator's old-du input.
- [ ] Verify successful values bit-exactly and error responses at the same +16 interval. Check most-negative operands and S26 error formation.
- [ ] Mutation checks: replace old x with candidate x, or multiply Kaw by Ts; both must fail directed expectations. Keep mutations outside tracked sources.
- [ ] Retain GREEN evidence for both profiles and commit.

## Task 5 — Standalone circular limiter

**Files:** `mc_dq_limiter.sv`, `mc_dq_limiter_tb.sv`.

**Consumes:** S40 raw voltages and signed S25 bus. **Produces:** high-resolution limited values/corrections, F15 outputs, U33 scale, flags/error at +160.

- [ ] Write TB before DUT: zero/axis/quadrant/boundary, maximum S40 square sum, epsilon, tiny/invalid/dynamic bus, exact scale and old-vs-current flag distinctions.
- [ ] Implement U80 squared norm, root ceiling, EPS=17, Umax floor, full U72/U41 quotient and signed-74 scaled products. Stage multiply results and launches; use the tested primitives. Pad shortcuts/errors to +160.
- [ ] Check bit-exact internal/external values, <=2 F15 LSB ideal component error and <=1 F15 LSB norm excess; use independent math references, not DUT intermediate values as the expected answer.
- [ ] Run at least 4096 seeded full-width valid limiter cases plus directed bus errors. Enforce each fixture's exact count and fail every malformed non-comment row.
- [ ] Mutation checks: signed S80 norm sum, dropped epsilon or F15 feedback must fail the relevant tests. Retain GREEN and commit.

## Task 6 — Persistent-state core and transaction proof

**Files:** `mc_pi_dq_core.sv`, `mc_pi_dq_core_tb.sv`.

**Consumes:** spec top interface and the stateless evaluator/limiter. **Produces:** voltage/error response and one atomic successful state commit at +256.

- [ ] Build TB queue on actual valid&&ready edges, capturing transaction IDs and OLD states. Expected completion is accepted_edge+256. Expected state changes only on a successful completion; reset abort removes queued work.
- [ ] Write reset/error/early-commit tests before implementation and observe RED.
- [ ] Implement capture, evaluator/limiter scheduling, private tentative results, fixed-slot response and atomic five-state commit. Error responses zero functional voltages/flags and preserve persistent state. No acceptance on the completion edge.
- [ ] Compare every functional output plus named debug OLD/NEXT snapshot; check errors, delayed sat flag, and unknowns. Run 160 source rows, >=1024 successful seeded transactions/profile and >=128 error transactions/profile; count accepted/completed/aborted requests independently.
- [ ] Repeat an identical accepted sequence with different idle gaps, including >=5000 idle clocks; outputs/states must match. Hold valid through busy, change ignored inputs, and reset during every substage and final padding.
- [ ] Mutation checks for same-transaction du feedback, repeated per-clock integration, early state commit and truncated fixture must fail. Retain GREEN marker and commit.

## Task 7 — Portable project and final regression/route acceptance

**Files:** `FOC_PI/`, `scripts/step6c2_pi_build.tcl`, `motor_control_ip/foc/README_step6c2.md`, new C2 report directory and execution report.

- [ ] Create external-source XPR with package first, core profile 0 synthesis top and core TB simulation top. Exactly one XDC: `create_clock -name sys_clk -period 20.000 [get_ports clk]`. Stage C2 fixtures and existing C1 ROM without modifying originals.
- [ ] Implement a build that starts IN_PROGRESS, invokes fresh Python tests/checkers, runs all six C2/four C1/one PWM TBs with strict marker/error/exit validation, and creates independent scratch profile-0/profile-1 synth/route runs.
- [ ] Audit actual primitive counts/hierarchy, loops/latches/drivers, clocks, no unconstrained internal endpoints, setup/hold/pulse-width metrics and raw worst paths, route completeness and non-board DRC blockers. Preserve all warnings with categories; do not impose a made-up resource count.
- [ ] Open a relocated minimal project/source tree and verify every source path, file type, compile order and fixture staging. Record the actual result, not an XML-only assertion that relocation would work.
- [ ] Exercise failure paths using disposable malformed/truncated fixture, missing source and failed-marker cases; build must not report PASS.
- [ ] Run the FINAL full build after all script edits. Save distinct evidence for profiles and regressions; do not overwrite prior accepted reports. A killed process/native crash is not success.
- [ ] Run `git diff --check`; audit all changed paths against task authorization. Record versions, latency measurements, exact test counts, numerical maxima and both routed profiles in `step6c2_codex_report.md`.
- [ ] Commit; open the specified implementation PR; stop for ChatGPT review without merge or C3 work.

## Design coverage check

Spec 1–3 -> task 1/2; spec 4 -> task 4; spec 5 -> tasks 3/5; spec 6–7 -> tasks 4/5/6; spec 8 -> tasks 2–7; spec 9–10 -> tasks 1/6/7. Any discovered contradiction or unattainable numerical/timing gate is reported with evidence; it is not resolved by editing the frozen gate.
