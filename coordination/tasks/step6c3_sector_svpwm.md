# Step 6C3 — Codex Task: Fixed-Point Sector SVPWM

Date: 2026-09-19.
Accepted design baseline: PR #15 merged at `b0ce6935cf5c304184da3bf5a5fc30b6c5f2490a`.

This is the implementation task book for the learning-oriented Step 6C3 design. Follow the accepted specification exactly, but keep the implementation and verification proportionate to a learning project.

## 1. Goal

Implement the standalone path:

```text
v_alpha / v_beta / vdc
        -> sector
        -> X/Y/Z
        -> T1/T2
        -> L/M/H
        -> normalized duty_u/v/w
```

The primary objective is to make this SVPWM chain readable, runnable and numerically understandable before Step 6C4 integrates the full PI-FOC path.

Do not turn C3 into a product-hardening exercise.

## 2. Read first

Read in this order:

1. `coordination/HANDOFF.md`
2. `coordination/specs/step6c3_sector_svpwm.md` — authoritative C3 contract
3. `coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`
4. Step 6A audit section 7 and the actual golden CSV
5. accepted C2 divider source/TB, read-only
6. accepted C1 inverse-Park/current-transform interfaces, read-only

If implementation pressure conflicts with the accepted C3 spec, stop and report the conflict. Do not silently change the spec to make the RTL easier.

## 3. Branch and stop point

Start from latest accepted `main` and create:

```text
step6c3-sector-svpwm
```

Expected implementation PR:

```text
Step 6C3: Add fixed-point sector SVPWM
```

Stop at the open PR for ChatGPT review.

Do not automatically merge, begin C4/6D, generate a bitstream or program hardware.

## 4. Authorized new implementation files

Create the small C3 RTL set:

```text
motor_control_ip/foc/rtl/mc_svpwm_pkg.sv
motor_control_ip/foc/rtl/mc_svpwm_sector_xyz.sv
motor_control_ip/foc/rtl/mc_sector_svpwm.sv
```

Create compact C3 tests:

```text
motor_control_ip/foc/tb/mc_svpwm_pkg_tb.sv
motor_control_ip/foc/tb/mc_svpwm_sector_xyz_tb.sv
motor_control_ip/foc/tb/mc_sector_svpwm_tb.sv
motor_control_ip/foc/tb/vectors/step6c3/sector_xyz_vectors.txt
motor_control_ip/foc/tb/vectors/step6c3/svpwm_vectors.txt
motor_control_ip/foc/tb/vectors/step6c3/manifest.json
```

Create reference/build/report files:

```text
scripts/step6c3_svpwm_reference.py
scripts/step6c3_svpwm_reference_test.py
scripts/step6c3_svpwm_build.tcl
motor_control_ip/foc/README_step6c3.md
FOC_SVPWM/FOC_SVPWM.xpr
FOC_SVPWM/FOC_SVPWM.srcs/constrs_1/new/foc_svpwm_clock.xdc
coordination/reports/step6c3_svpwm_fixed_vectors.csv
coordination/reports/step6c3_codex_report.md
docs/reports/step6c3/
```

If the top becomes genuinely difficult to read, propose a small additional dwell submodule before adding it. Do not split the design merely to create more files.

## 5. Protected/read-only sources

Do not modify:

- accepted C1 RTL/TBs/ROM/fixtures/project/scripts/reports;
- accepted C2 RTL/TBs/fixtures/project/scripts/reports;
- especially `motor_control_ip/foc/rtl/mc_udiv_u72_u41.sv`;
- accepted PWM RTL/TB;
- Step 6A golden/reference/verifier files;
- `simulink模型/`;
- prior coordination specs/tasks/reports except the new C3 execution report.

C3 may instantiate the accepted C2 divider twice. It must not edit that divider.

## 6. Non-negotiable function

Inputs:

```text
v_alpha, v_beta, vdc : S25/F15
```

Outputs:

```text
duty_u/v/w : signed S26/F24
sector      : 1..6 on successful data
overmodulated
error_code
```

Main rules:

- preserve Step 6A Sector -> XYZ -> T1/T2 -> Duty algorithm;
- do not substitute Min-Max SVPWM;
- use integer-ratio sector boundaries and XYZ coefficients from the spec;
- use S34/F32 normalized T1/T2;
- reuse two C2 U72/U41 dividers in parallel;
- nearest/ties-away rounding, not truncation;
- overmodulate only when `SUM > BASE`;
- keep small negative mathematical dwell/duty values; no C3 duty clamp;
- zero vector with valid positive bus must produce sector 2 and exact 0.5/0.5/0.5 duty;
- one request in flight;
- fixed top response at N+128;
- `vdc<=0` returns INVALID_VDC at the same response slot;
- reset aborts work and must not allow stale output.

## 7. Learning-first implementation order

Follow the companion plan in this order:

1. independent Python oracle;
2. Sector/XYZ RTL and visible six-sector/zero-vector bring-up;
3. full top with the two accepted dividers, T1/T2, L/M/H and phase mapping;
4. actual Step 6A 160-row comparison plus focused boundary/reset/error tests;
5. standalone Vivado synthesis/route and compact regressions.

Do not build extensive malformed-file/fault-injection infrastructure before the main function works.

## 8. Required functional checks

At minimum prove:

- zero vector -> sector 2 -> duty 0.5/0.5/0.5;
- one clear interior vector for every sector;
- exact comparator boundary -1/0/+1 around the sector inequalities;
- one linear dwell case;
- `SUM=BASE-1`, `SUM=BASE`, `SUM=BASE+1`;
- one obvious overmodulation case;
- a negative provisional dwell case remains unclamped;
- `vdc=0` and negative `vdc` return INVALID_VDC;
- busy input changes do not affect accepted data;
- reset aborts pending work;
- exact N+128 response timing.

Use roughly 512–1024 deterministic seeded valid cases, not an unnecessarily huge random campaign.

## 9. Numerical comparison gates

### RTL vs C3 integer oracle

Must be bit-exact for all checked integer fields.

### Integer oracle vs Decimal

Require:

```text
t1/t2 error <= 1 F32 LSB
duty_u/v/w error <= 2 F24 LSB
```

### C3 vs actual Step 6A CSV

Use actual CSV `v_alpha/v_beta/vdc` directly.

Require:

```text
normalized t1 error <= 5e-5
normalized t2 error <= 5e-5
normalized duty_u/v/w error <= 5e-5
```

Only these four known boundary sector mismatches are allowed:

```text
real_commissioning / edge_1_1.732
real_commissioning / edge_1_-1.732
MIL_PI_override / edge_1_1.732
MIL_PI_override / edge_1_-1.732
```

Any additional sector mismatch is a review stop.

## 10. Small negative-control requirement

Use disposable scratch mutations only. Prove the tests catch at least three of these four mistakes:

- `b1 >= 0` changed to `b1 > 0`;
- overmodulation normalization removed;
- one U/V/W phase mapping swapped;
- negative duty clamped to zero.

Do not commit mutated RTL.

No broad catalogue of parser/build-failure probes is required.

## 11. Vivado acceptance

Use Vivado 2026.1, part:

```text
xc7a200tfbg484-2
```

Clock:

```text
20.000 ns / 50 MHz
```

Standalone top:

```text
mc_sector_svpwm
```

Run synthesis and route. Do not generate a bitstream.

Record actual LUT/FF/DSP/BRAM resources and hierarchy.

Require:

```text
WNS >= 0
TNS = 0
WHS >= 0
THS = 0
routing errors = 0
no inferred latch
no unresolved/black-box module
no internal combinational loop
```

Retain board-only/core-I/O warnings and describe this as internal core timing, not board timing signoff.

No exact resource-count target is imposed.

## 12. Compact regression set

Final build should run:

- all three new C3 TBs;
- accepted C2 divider TB;
- accepted C2 core TB;
- accepted C1 current-transform TB;
- accepted Step 6B motor PWM TB;
- C3 Python unit/check;
- C2 Python check;
- C1 Python check;
- Step 6A verifier.

Do not rerun C1/C2/PWM synthesis/route unless those accepted sources changed.

## 13. Required markers

Use concise success markers:

```text
ALL STEP 6C3 SVPWM PKG TESTS PASSED
ALL STEP 6C3 SECTOR XYZ TESTS PASSED
ALL STEP 6C3 SECTOR SVPWM TESTS PASSED
STEP6C3_BUILD_PASS
```

The final build checks process success, exact expected markers and absence of simulation Fatal/Error diagnostics.

## 14. Completion report

Write:

```text
coordination/reports/step6c3_codex_report.md
```

Record:

- base/head commits and tool versions;
- readable description of the implemented SVPWM chain;
- exact formats and latency;
- directed/seeded test counts;
- actual Step 6A comparison maxima and the four known boundary rows;
- mutation checks performed;
- final routed resources/timing;
- compact regression results;
- retained warnings and limitations;
- explicit statement that no bitstream/hardware/C4/6D work was done.

Then open the implementation PR and stop.
