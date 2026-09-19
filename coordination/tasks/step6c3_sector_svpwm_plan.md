# Step 6C3 Fixed-Point Sector SVPWM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a readable standalone fixed-point Sector-SVPWM core that converts S25/F15 `v_alpha/v_beta/vdc` into signed S26/F24 normalized U/V/W duty and proves the main algorithm against an independent integer oracle and Step 6A reference data.

**Architecture:** Keep the RTL small: one package, one Sector/XYZ block and one transaction top. The top reuses two accepted C2 U72/U41 dividers in parallel, pads all paths to N+128, and stops before duty-to-CMP/PWM integration.

**Tech Stack:** Python standard library, SystemVerilog, Tcl, Vivado/XSim 2026.1, XDC.

**Spec:** `coordination/specs/step6c3_sector_svpwm.md`

## Global Constraints

- Start from accepted `main` containing merged PR #15.
- Use `xc7a200tfbg484-2` and a single 20.000 ns `sys_clk`.
- Inputs `v_alpha/v_beta/vdc` are signed S25/F15.
- Outputs `duty_u/v/w` are signed S26/F24.
- Internal normalized `t1/t2` are S34/F32.
- Preserve the audited Step 6A Sector-SVPWM algorithm; do not substitute Min-Max SVPWM.
- Reuse accepted `mc_udiv_u72_u41.sv` without modification.
- No duty clamp in C3.
- One request in flight; fixed top response N+128.
- No bitstream, hardware programming, C4 or 6D work.
- Accepted C1/C2/PWM and Step 6A sources are read-only.

## Review Focus

- Exact sector boundary equality: `b1 >= 0` must differ from the two strict-`>` predicates.
- Overmodulation boundary: `SUM == BASE` remains linear; only `SUM > BASE` sets `overmodulated`.
- Negative provisional dwell/duty must survive C3 without an implicit clamp.
- Busy-input changes must not replace the captured transaction.
- Error completion must not be mistaken for a usable PWM command.

---

### Task 1: Independent C3 integer oracle and fixtures

**Files:**
- Create: `scripts/step6c3_svpwm_reference.py`
- Create: `scripts/step6c3_svpwm_reference_test.py`
- Create: `motor_control_ip/foc/tb/vectors/step6c3/sector_xyz_vectors.txt`
- Create: `motor_control_ip/foc/tb/vectors/step6c3/svpwm_vectors.txt`
- Create: `motor_control_ip/foc/tb/vectors/step6c3/manifest.json`
- Create: `coordination/reports/step6c3_svpwm_fixed_vectors.csv`

**Interfaces:**
- Consumes: actual Step 6A CSV `v_alpha/v_beta/vdc` columns.
- Produces: deterministic integer expected values for Sector/XYZ and full C3 outputs.

- [ ] **Step 1: Write explicit oracle tests before the oracle implementation**

Add tests for these literal identities:

```python
def test_zero_vector():
    r = svpwm_step(0, 0, 48 << 15)
    assert r["sector"] == 2
    assert r["t1"] == 0
    assert r["t2"] == 0
    assert (r["duty_u"], r["duty_v"], r["duty_w"]) == (
        1 << 23, 1 << 23, 1 << 23
    )

def test_sector_equality_boundary():
    # 433*A - 250*B == 0
    A, B = 25000, 43300
    r = sector_xyz(A, B)
    assert r["cmp1"] == 0
    assert r["b1"] == 1

def test_overmod_exact_boundary():
    r = dwell_from_ab(a_num=500000, b_num=500000, vdc_raw=100)
    assert r["sum_num"] == r["base"]
    assert r["overmodulated"] == 0
```

Also test nearest/ties-away signed division on positive and negative half-remainder cases.

- [ ] **Step 2: Run the tests and confirm RED**

Run:

```text
python scripts/step6c3_svpwm_reference_test.py
```

Expected: fail because the C3 oracle functions do not yet exist.

- [ ] **Step 3: Implement the integer oracle**

Implement these functions with Python arbitrary-precision integers:

```python
round_shift_away(x, shift)
sector_xyz(A, B)
round_div_signed(num, den, frac_bits=32)
dwell_from_ab(a_num, b_num, vdc_raw)
duty_from_sector(sector, t1, t2)
svpwm_step(A, B, vdc_raw)
```

Use exactly:

```text
b0 = B > 0
b1 = 433*A - 250*B >= 0
b2 = -433*A - 250*B > 0

X = 17321*B
Y = 8660*B + 15000*A
Z = 8660*B - 15000*A
```

Use `Decimal` for the independent high-precision check; do not emulate the restoring divider loop in Python.

- [ ] **Step 4: Add actual Step 6A replay**

Read the committed 160-row CSV and quantize only `v_alpha/v_beta/vdc` to the C3 input format.

Require:

```text
t1 normalized error <= 5e-5
t2 normalized error <= 5e-5
duty_u/v/w error <= 5e-5
```

Allow sector mismatch only for the four accepted `edge_1_±1.732` rows named in the spec.

Write the comparison output to `coordination/reports/step6c3_svpwm_fixed_vectors.csv`.

- [ ] **Step 5: Generate a compact deterministic fixture set**

Generate:

- directed zero/six-sector/boundary/overmodulation/no-clamp cases;
- 512–1024 seeded valid full-top cases;
- exact schema/counts/seeds in `manifest.json`.

Support:

```text
python scripts/step6c3_svpwm_reference.py --generate
python scripts/step6c3_svpwm_reference.py --check
```

`--check` regenerates expected text in memory and compares it to checked-in files.

- [ ] **Step 6: Run and commit the oracle stage**

Run:

```text
python scripts/step6c3_svpwm_reference_test.py
python scripts/step6c3_svpwm_reference.py --generate
python scripts/step6c3_svpwm_reference.py --check
python scripts/reference_audit/verify_step6a_vectors.py
```

Expected: all pass with the specified Step 6A tolerances and only the four known sector-boundary differences.

Commit the oracle/fixtures/comparison before RTL work.

---

### Task 2: Sector/XYZ RTL bring-up

**Files:**
- Create: `motor_control_ip/foc/rtl/mc_svpwm_pkg.sv`
- Create: `motor_control_ip/foc/rtl/mc_svpwm_sector_xyz.sv`
- Create: `motor_control_ip/foc/tb/mc_svpwm_pkg_tb.sv`
- Create: `motor_control_ip/foc/tb/mc_svpwm_sector_xyz_tb.sv`

**Interfaces:**
- Consumes: S25/F15 `v_alpha/v_beta`.
- Produces: sector plus signed S40 `a_num/b_num` and debug X/Y/Z values.

- [ ] **Step 1: Write failing directed TBs**

The package TB must check signed nearest/ties-away rounding used by later C3 narrowing.

The Sector/XYZ TB must check:

```text
A=0, B=0 -> sector 2

A=25000, B=43299
A=25000, B=43300
A=25000, B=43301
```

and one interior vector per sector.

Load and bit-compare `sector_xyz_vectors.txt` against the independent oracle.

- [ ] **Step 2: Run RED elaboration/simulation**

Compile with the new TBs before the RTL exists.

Expected: missing module/package or failing functional checks.

- [ ] **Step 3: Implement the package and Sector/XYZ block**

Use widened signed temporaries before multiplication/addition/negation.

Do not use real numbers or floating point in synthesizable RTL.

Do not clamp `a_num/b_num`.

- [ ] **Step 4: Run GREEN tests**

Required markers:

```text
ALL STEP 6C3 SVPWM PKG TESTS PASSED
ALL STEP 6C3 SECTOR XYZ TESTS PASSED
```

- [ ] **Step 5: Run one focused mutation**

In a disposable scratch copy change:

```text
b1 = (cmp1 >= 0)
```

to:

```text
b1 = (cmp1 > 0)
```

The boundary TB must fail.

Restore the real RTL and commit Task 2.

---

### Task 3: Full N+128 Sector-SVPWM transaction top

**Files:**
- Create: `motor_control_ip/foc/rtl/mc_sector_svpwm.sv`
- Create: `motor_control_ip/foc/tb/mc_sector_svpwm_tb.sv`

**Interfaces:**
- Consumes: `mc_svpwm_sector_xyz` outputs and two read-only instances of accepted `mc_udiv_u72_u41`.
- Produces: S26/F24 `duty_u/v/w`, sector, overmodulated, error_code at fixed N+128.

- [ ] **Step 1: Write the top-level scoreboard before the DUT is complete**

Queue expected transactions only on actual:

```text
input_valid && input_ready
```

Require:

```text
response_edge - accept_edge == 128
```

Check bit-exact top fields from `svpwm_vectors.txt`.

The TB must explicitly include:

- zero vector;
- six sector interior vectors;
- `SUM=BASE-1/BASE/BASE+1`;
- overmodulation;
- negative provisional dwell/no-clamp;
- `vdc=0` and negative `vdc`;
- busy-time input poisoning;
- reset abort with no stale response.

- [ ] **Step 2: Observe RED**

Compile/elaborate/simulate the top TB.

Expected: missing/incomplete DUT or functional mismatch.

- [ ] **Step 3: Implement capture and scheduling**

At acceptance capture:

```text
v_alpha
v_beta
vdc
```

Run Sector/XYZ from captured data.

For valid positive bus, form:

```text
BASE = 10000*vdc_raw
SUM  = a_num+b_num
den  = (SUM > BASE) ? SUM : BASE
```

Use magnitudes for the two divider numerators:

```text
abs(a_num)<<32
abs(b_num)<<32
```

Instantiate two accepted C2 dividers in parallel.

- [ ] **Step 4: Implement divider-result rounding and duty mapping**

Use quotient/remainder to perform nearest/ties-away F32 rounding, restore sign, then calculate:

```text
L = (1-t1-t2)/2
M = (1+t1-t2)/2
H = (1+t1+t2)/2
```

Map U/V/W by sector and narrow F32 -> F24 only at the outputs.

Do not clamp duty.

- [ ] **Step 5: Pad all paths to N+128 and implement error responses**

`INVALID_VDC`, `RANGE_ERROR` and `INTERNAL_ERROR` all respond at N+128.

Error response:

```text
duty_u/v/w = 0
sector = 0
overmodulated = 0
```

Reset aborts pending work.

- [ ] **Step 6: Run GREEN and focused mutations**

Required marker:

```text
ALL STEP 6C3 SECTOR SVPWM TESTS PASSED
```

Run at least two disposable mutations:

- remove overmodulation normalization;
- clamp negative duty to zero or swap a phase mapping.

Each must make the top TB fail.

Restore real RTL and commit Task 3.

---

### Task 4: Step 6A comparison and focused learning checks

**Files:**
- Modify as needed: `scripts/step6c3_svpwm_reference.py`
- Modify as needed: `motor_control_ip/foc/tb/mc_sector_svpwm_tb.sv`
- Create/modify: `coordination/reports/step6c3_svpwm_fixed_vectors.csv`

**Interfaces:**
- Consumes: completed C3 integer oracle and full RTL.
- Produces: algorithm-comparison evidence and final directed-case summary.

- [ ] **Step 1: Run the actual 160-row source comparison**

Run:

```text
python scripts/step6c3_svpwm_reference.py --check
```

Record maxima for t1, t2, duty_u, duty_v and duty_w.

Explicitly print the four allowed boundary sector rows and fail on any additional mismatch.

- [ ] **Step 2: Run the seeded RTL fixture stream**

The full TB must bit-match every seeded expected row from the integer oracle.

Keep the seeded count in the agreed 512–1024 range.

- [ ] **Step 3: Verify protocol learning cases**

Demonstrate in the TB/log:

- accepted inputs are immune to busy-time bus changes;
- completion occurs exactly at N+128;
- earliest next acceptance is after the completion edge;
- async reset cancels pending work and no stale response appears.

- [ ] **Step 4: Commit comparison/test finalization**

Do not add broader failure-probe infrastructure unless a real implementation bug shows it is necessary.

---

### Task 5: Standalone Vivado build, compact regressions and PR

**Files:**
- Create: `scripts/step6c3_svpwm_build.tcl`
- Create: `motor_control_ip/foc/README_step6c3.md`
- Create: `FOC_SVPWM/FOC_SVPWM.xpr`
- Create: `FOC_SVPWM/FOC_SVPWM.srcs/constrs_1/new/foc_svpwm_clock.xdc`
- Create: `coordination/reports/step6c3_codex_report.md`
- Create: `docs/reports/step6c3/`

**Interfaces:**
- Consumes: final C3 RTL/tests plus accepted C1/C2/PWM regression sources.
- Produces: routed 50 MHz evidence and the implementation PR.

- [ ] **Step 1: Create the standalone external-source Vivado project**

Use:

```text
part = xc7a200tfbg484-2
top  = mc_sector_svpwm
clock = 20.000 ns
```

Exact XDC:

```tcl
create_clock -name sys_clk -period 20.000 [get_ports clk]
```

No bitstream step.

- [ ] **Step 2: Implement a simple fail-closed build**

The script must run:

```text
python scripts/step6c3_svpwm_reference_test.py
python scripts/step6c3_svpwm_reference.py --check
python scripts/step6c2_pi_reference.py --check
python scripts/step6c1_fixed_transform_reference.py --check
python scripts/reference_audit/verify_step6a_vectors.py
```

Then run:

- all three C3 TBs;
- C2 divider TB;
- C2 core TB;
- C1 current-transform TB;
- Step 6B motor PWM TB.

Require the exact expected success marker and reject Fatal/Error text. Do not create the large C2-style catalogue of intentional build failures.

- [ ] **Step 3: Synthesize, route and record resources/timing**

Record actual:

```text
Slice LUT
FF
DSP48E1
BRAM
WNS/TNS
WHS/THS
routable/routed/error nets
```

Require:

```text
WNS >= 0
TNS = 0
WHS >= 0
THS = 0
routing errors = 0
no latch
no black box/unresolved module
no internal combinational loop
```

Retain board/core-I/O warnings and state that this is internal core timing only.

- [ ] **Step 4: Run the final build after the last source/script edit**

The final run must produce:

```text
STEP6C3_BUILD_PASS
```

Save fresh evidence under `docs/reports/step6c3/`.

- [ ] **Step 5: Write the concise execution report**

`coordination/reports/step6c3_codex_report.md` must include:

- implementation structure;
- numeric formats;
- measured N+128 latency;
- directed + seeded counts;
- Step 6A numerical maxima and the four known boundary rows;
- focused mutation checks;
- routed resources and timing;
- compact regression results;
- known warnings/limitations;
- no bitstream/hardware/C4/6D statement.

- [ ] **Step 6: Scope check and open PR**

Run:

```text
git diff --check
git status --short
```

Confirm accepted C1/C2/PWM/Step 6A files are unchanged.

Open:

```text
Step 6C3: Add fixed-point sector SVPWM
```

Stop for ChatGPT review. Do not merge or start C4.

## Design Coverage Check

- Spec sections 3–9: Tasks 1–3.
- Timing/reset/error contract: Task 3.
- Verification philosophy and minimal directed tests: Tasks 1–4.
- Vivado learning-stage acceptance/regression: Task 5.
- C3->C4 boundary remains documentation-only in this task; no C4 code is created.

No product-scale parser/fault-injection framework is part of the baseline unless an actual discovered bug requires a targeted addition.
