# Step 6C1 Fixed-Point FOC Transform Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a bit-exact fixed-point Clarke + quarter-wave sin/cos LUT + Park/inverse-Park foundation that maps naturally to XC7A200T DSP48/BRAM resources and remains portable to later Zynq PL.

**Architecture:** Phase currents use signed 24-bit F15 and transformed quantities use signed 25-bit F15. Sin/cos use a 4096-entry signed 18-bit F16 quarter-wave ROM addressed by a 16-bit binary angle; Park/Clarke multiplications use native 25x18 arithmetic inference with full-precision products and explicit round+saturate. A Python software model is the bit-exact oracle; Step 6A floating-point vectors remain the algorithm-level comparison corpus.

**Tech Stack:** SystemVerilog, Python 3, Vivado/XSim 2026.1, Tcl, target `xc7a200tfbg484-2`.

**Spec:** `coordination/specs/step6c1_fixed_point_transforms.md`

## Global Constraints

- Start from latest `main`; PR #11 is merged.
- Branch name: `step6c1-fixed-point-transforms`.
- Do not modify `PWM_Controller/`, `PWM_Breathe/`, `simulink模型/`, Step 6A golden files, or accepted Step 6B PWM behavior.
- Use signed 24 F15 phase currents, signed 25 F15 transform data, signed 18 F16 coefficients/sin/cos, and unsigned 16-bit binary angle exactly as specified.
- Constants: `C_TWO_THIRDS=43691`, `C_INV_SQRT3=37837`, `SIN_COS_ONE=65536`.
- Use magnitude-based round-to-nearest/ties-away-from-zero and signed saturation. No silent wraparound.
- Use inferred arithmetic/memory; do not instantiate DSP48E1/RAMB36E1 primitives.
- Step 6C1 uses LUT sin/cos, not CORDIC and not floating point.
- Vivado 2026.1, 20 ns clock, no board pins/IOSTANDARD/input-output delays, no bitstream, no hardware programming.
- Stop at an open PR. Do not begin Step 6C2.

---

## File Structure

Create:

```text
motor_control_ip/foc/README.md
motor_control_ip/foc/rom/sin_qw_4096x18.mem
motor_control_ip/foc/rtl/mc_fxp_pkg.sv
motor_control_ip/foc/rtl/mc_clarke.sv
motor_control_ip/foc/rtl/mc_sincos_lut.sv
motor_control_ip/foc/rtl/mc_park.sv
motor_control_ip/foc/rtl/mc_inv_park.sv
motor_control_ip/foc/rtl/mc_current_transform.sv
motor_control_ip/foc/tb/mc_clarke_tb.sv
motor_control_ip/foc/tb/mc_sincos_lut_tb.sv
motor_control_ip/foc/tb/mc_park_tb.sv
motor_control_ip/foc/tb/mc_current_transform_tb.sv
scripts/step6c1_fixed_transform_reference.py
scripts/step6c1_foc_transforms_build.tcl
FOC_Transforms/FOC_Transforms.xpr
FOC_Transforms/FOC_Transforms.srcs/constrs_1/new/foc_transforms_clock.xdc
coordination/reports/step6c1_fixed_transform_vectors.csv
coordination/reports/step6c1_codex_report.md
docs/reports/step6c1/*
```

---

### Task 1: Branch, fixed-point software oracle, and deterministic ROM

**Files:**
- Create: `scripts/step6c1_fixed_transform_reference.py`
- Create: `motor_control_ip/foc/rom/sin_qw_4096x18.mem`
- Create later by script: `coordination/reports/step6c1_fixed_transform_vectors.csv`
- Read: `coordination/reports/step6a_pi_foc_golden_vectors.csv`

**Interfaces:**
- Consumes: Step 6C1 numeric contract and Step 6A CSV.
- Produces: deterministic ROM image and bit-exact Python functions used by all RTL testbenches.

- [ ] **Step 1: Sync and create the feature branch**

```bash
git checkout main
git pull --ff-only
git checkout -b step6c1-fixed-point-transforms
git status --short
```

Expected: clean task branch based on merged PR #11.

- [ ] **Step 2: Write the software rounding/saturation primitives first**

Implement these semantics in Python:

```python
def round_shift_away(x: int, shift: int) -> int:
    if shift == 0:
        return x
    mag = abs(x)
    rounded_mag = (mag + (1 << (shift - 1))) >> shift
    return -rounded_mag if x < 0 else rounded_mag

def sat_signed(x: int, width: int) -> int:
    lo = -(1 << (width - 1))
    hi = (1 << (width - 1)) - 1
    return min(max(x, lo), hi)
```

Also implement the one-bit division rule with the same magnitude principle.

- [ ] **Step 3: Add exact fixed-point transform functions**

Required formulas:

```python
C_TWO_THIRDS = 43691
C_INV_SQRT3 = 37837
SIN_COS_ONE = 65536

def clarke_raw(ia, ib, ic):
    sum_bc = ib + ic
    half_bc = round_shift_away(sum_bc, 1)
    alpha_pre = ia - half_bc
    beta_pre = ib - ic
    i_alpha = sat_signed(round_shift_away(alpha_pre * C_TWO_THIRDS, 16), 25)
    i_beta  = sat_signed(round_shift_away(beta_pre  * C_INV_SQRT3, 16), 25)
    return i_alpha, i_beta
```

Implement Park/inverse Park using 43-bit-equivalent integer products, 44-bit-equivalent sums, then `round_shift_away(...,16)` and 25-bit saturation.

- [ ] **Step 4: Generate the quarter-wave ROM**

For `k=0..4095`:

```python
raw = round(math.sin(k * (math.pi / 2) / 4096) * (1 << 16))
```

Write each signed 18-bit value as a fixed-width 5-hex-digit two's-complement word suitable for `$readmemh`.

Example checks:

```python
assert values[0] == 0
assert 0 < values[1] < values[-1] < 65536
assert len(values) == 4096
```

- [ ] **Step 5: Implement binary-angle LUT reconstruction in Python**

Use:

```python
quadrant = (theta >> 14) & 0x3
q = (theta >> 2) & 0xFFF
S = values[q]
C = SIN_COS_ONE if q == 0 else values[4096 - q]
```

Then apply the four quadrant sign/permutation rules exactly from the spec.

- [ ] **Step 6: Generate Step 6C1 fixed vectors from Step 6A inputs**

The CSV must include at least:

```text
case_id
ia_raw ib_raw ic_raw theta_u16
i_alpha_raw i_beta_raw
sin_raw cos_raw
id_raw iq_raw
ia_A ib_A ic_A theta_rad
i_alpha_A i_beta_A id_A iq_A
```

Quantize Step 6A inputs to 24 F15 and binary angle before evaluating the fixed model.

- [ ] **Step 7: Add command-line self-check mode**

Required commands:

```bash
python scripts/step6c1_fixed_transform_reference.py --generate
python scripts/step6c1_fixed_transform_reference.py --check
```

`--check` must regenerate in memory, compare against the checked-in ROM/vector files, validate exact axes/quadrants, and exit nonzero on any mismatch.

- [ ] **Step 8: Run and commit**

```bash
python scripts/step6c1_fixed_transform_reference.py --generate
python scripts/step6c1_fixed_transform_reference.py --check
git diff --check
git add scripts/step6c1_fixed_transform_reference.py motor_control_ip/foc/rom/sin_qw_4096x18.mem coordination/reports/step6c1_fixed_transform_vectors.csv
git commit -m "test: add Step 6C1 fixed-point reference"
```

Expected: software oracle passes before any RTL exists.

---

### Task 2: Fixed-point package and Clarke RTL

**Files:**
- Create: `motor_control_ip/foc/rtl/mc_fxp_pkg.sv`
- Create: `motor_control_ip/foc/rtl/mc_clarke.sv`
- Create: `motor_control_ip/foc/tb/mc_clarke_tb.sv`

**Interfaces:**
- Consumes: 24-bit F15 `ia/ib/ic`, `input_valid`.
- Produces: 25-bit F15 `i_alpha/i_beta`, `output_valid`.

- [ ] **Step 1: Write a failing Clarke TB before the module**

The TB must read reference rows or hard-code exact raw cases including:

```text
zero
common mode
ia=+1, ib=-0.5, ic=-0.5
negative/sign cases
near positive/negative 24-bit limits
```

Use transaction IDs and assert exact integer outputs.

Required temporary failure: elaboration fails because `mc_clarke` does not exist.

- [ ] **Step 2: Run the RED test**

Use XSim command-line flow or a minimal temporary Vivado project. Capture evidence under:

`docs/reports/step6c1/tdd_clarke_red.txt`

Expected: explicit missing-module failure.

- [ ] **Step 3: Implement `mc_fxp_pkg.sv`**

Define widths/fraction constants and signed helper functions. The rounding helper must use magnitude-based rounding, not a negative-bias arithmetic shortcut.

Constants must literally equal:

```systemverilog
localparam logic signed [17:0] C_TWO_THIRDS = 18'sd43691;
localparam logic signed [17:0] C_INV_SQRT3  = 18'sd37837;
localparam logic signed [17:0] SIN_COS_ONE  = 18'sd65536;
```

- [ ] **Step 4: Implement minimal pipelined Clarke RTL**

Use explicit signed extension:

```systemverilog
logic signed [24:0] sum_bc;
logic signed [24:0] alpha_pre;
logic signed [24:0] beta_pre;
logic signed [42:0] alpha_product;
logic signed [42:0] beta_product;
```

Use `(* use_dsp = "yes" *)` only if needed for the two multiplies. Register valid alongside data.

- [ ] **Step 5: Run Clarke TB to GREEN**

Required marker:

```text
ALL STEP 6C1 CLARKE TESTS PASSED
```

- [ ] **Step 6: Commit**

```bash
git add motor_control_ip/foc/rtl/mc_fxp_pkg.sv motor_control_ip/foc/rtl/mc_clarke.sv motor_control_ip/foc/tb/mc_clarke_tb.sv docs/reports/step6c1/tdd_clarke_red.txt
git commit -m "feat: add fixed-point Clarke transform"
```

---

### Task 3: Quarter-wave sin/cos LUT RTL

**Files:**
- Create: `motor_control_ip/foc/rtl/mc_sincos_lut.sv`
- Create: `motor_control_ip/foc/tb/mc_sincos_lut_tb.sv`
- Use: `motor_control_ip/foc/rom/sin_qw_4096x18.mem`

**Interfaces:**
- Consumes: `theta_e[15:0]`, `input_valid`.
- Produces: signed 18 F16 `sin_theta/cos_theta`, `output_valid`.

- [ ] **Step 1: Write the failing sine/cosine TB**

Required exact-axis assertions:

```text
theta 0000 -> sin=0       cos=+65536
theta 4000 -> sin=+65536  cos=0
theta 8000 -> sin=0       cos=-65536
theta C000 -> sin=-65536  cos=0
```

Also test `q=1,4094,4095`, both sides of every quadrant boundary, `FFFF`, and a broad phase sweep.

For every swept value, compare exact raw output to the Python fixed model.

Also compute ideal double sine/cos and require absolute error <= `5e-4`.

- [ ] **Step 2: Run RED and capture missing-module evidence**

Save:

`docs/reports/step6c1/tdd_sincos_red.txt`

- [ ] **Step 3: Implement synchronous dual-read ROM inference**

Use one ROM array initialized with:

```systemverilog
(* rom_style = "block" *) logic signed [17:0] sin_qw_rom [0:4095];

initial begin
    $readmemh("sin_qw_4096x18.mem", sin_qw_rom);
end
```

Use two synchronous reads for `q` and `mirror`. Register quadrant/`q==0` metadata through the same latency.

Do not create two independent full ROM copies unless Vivado inference proves unavoidable.

- [ ] **Step 4: Implement quadrant reconstruction**

Use the exact four mappings from the spec and constant endpoint `65536`.

- [ ] **Step 5: Run GREEN and commit**

Required marker:

```text
ALL STEP 6C1 SINCOS TESTS PASSED
```

Then:

```bash
git add motor_control_ip/foc/rtl/mc_sincos_lut.sv motor_control_ip/foc/tb/mc_sincos_lut_tb.sv docs/reports/step6c1/tdd_sincos_red.txt
git commit -m "feat: add quarter-wave sincos LUT"
```

---

### Task 4: Park and inverse-Park RTL

**Files:**
- Create: `motor_control_ip/foc/rtl/mc_park.sv`
- Create: `motor_control_ip/foc/rtl/mc_inv_park.sv`
- Create: `motor_control_ip/foc/tb/mc_park_tb.sv`

**Interfaces:**
- Park consumes signed 25 F15 alpha/beta and signed 18 F16 sin/cos.
- Inverse Park consumes signed 25 F15 d/q-like values and the same sin/cos format.
- Both produce signed 25 F15 outputs plus valid.

- [ ] **Step 1: Write RED tests for exact known rotations**

At theta=0:

```text
Park(alpha,beta) -> (alpha,beta)
InvPark(d,q) -> (d,q)
```

At theta=pi/2:

```text
id = beta
iq = -alpha
v_alpha = -vq
v_beta = vd
```

Use fixed reference integers, not floating-point literals at the RTL comparison boundary.

- [ ] **Step 2: Add randomized/reference-vector tests**

Drive at least 100 deterministic seeded raw vectors in safe ranges and compare bit-exactly to the Python model.

Add Park->InvPark round-trip measurements and print max physical-unit error.

- [ ] **Step 3: Run RED**

Save:

`docs/reports/step6c1/tdd_park_red.txt`

- [ ] **Step 4: Implement four parallel 25x18 products per transform**

Park product structure:

```systemverilog
p_ac = i_alpha * cos_theta;
p_bs = i_beta  * sin_theta;
p_as = i_alpha * sin_theta;
p_bc = i_beta  * cos_theta;
```

Accumulate in signed >=44-bit registers before calling package round+saturate helpers.

Do the analogous structure for inverse Park.

- [ ] **Step 5: Run GREEN**

Required marker:

```text
ALL STEP 6C1 PARK TESTS PASSED
```

- [ ] **Step 6: Commit**

```bash
git add motor_control_ip/foc/rtl/mc_park.sv motor_control_ip/foc/rtl/mc_inv_park.sv motor_control_ip/foc/tb/mc_park_tb.sv docs/reports/step6c1/tdd_park_red.txt
git commit -m "feat: add Park transform pair"
```

---

### Task 5: Integrate coherent current transform

**Files:**
- Create: `motor_control_ip/foc/rtl/mc_current_transform.sv`
- Create: `motor_control_ip/foc/tb/mc_current_transform_tb.sv`

**Interfaces:**
- Consumes one coherent `{ia,ib,ic,theta_e,input_valid}` transaction.
- Produces `i_alpha_dbg/i_beta_dbg/sin_theta_dbg/cos_theta_dbg/id/iq/output_valid`.
- Supports back-to-back valid transactions.

- [ ] **Step 1: Write a transaction-ID scoreboard before integration RTL**

Drive at least 64 consecutive valid cycles whose currents and theta encode different IDs.

Queue expected fixed-model results in TB.

On each `output_valid`, pop exactly one expected transaction and compare every debug/output field.

Fail on missing output, extra output, reordering, mixed transaction fields, or variable latency after pipeline fill.

- [ ] **Step 2: Run RED**

Save:

`docs/reports/step6c1/tdd_transform_red.txt`

- [ ] **Step 3: Implement wrapper and explicit alignment**

Instantiate Clarke and sincos in parallel.

If their latencies differ, delay the earlier branch with explicit data+valid registers until both refer to the same transaction.

Then launch Park.

- [ ] **Step 4: Measure and assert deterministic latency**

TB records input-valid clock index and output-valid clock index.

Require constant full latency < 32 clocks and print the measured latency.

- [ ] **Step 5: Compare Step 6A corpus**

Feed every applicable Step 6A row after the same quantization used by the Python reference.

RTL must be bit-exact to Step 6C1 fixed vectors.

Report expected small differences from Step 6A's 800-interval Simulink sine lookup without treating them as bit-exact failures.

- [ ] **Step 6: Run GREEN**

Required marker:

```text
ALL STEP 6C1 TRANSFORM TESTS PASSED
```

- [ ] **Step 7: Commit**

```bash
git add motor_control_ip/foc/rtl/mc_current_transform.sv motor_control_ip/foc/tb/mc_current_transform_tb.sv docs/reports/step6c1/tdd_transform_red.txt
git commit -m "feat: integrate fixed-point current transform"
```

---

### Task 6: Portable README and standalone Vivado project

**Files:**
- Create: `motor_control_ip/foc/README.md`
- Create: `FOC_Transforms/FOC_Transforms.xpr`
- Create: `FOC_Transforms/FOC_Transforms.srcs/constrs_1/new/foc_transforms_clock.xdc`

**Interfaces:**
- Project references portable RTL/TB/ROM files.
- Synthesis top: `mc_current_transform`.

- [ ] **Step 1: Write clock-only XDC**

Exactly:

```tcl
create_clock -name sys_clk -period 20.000 [get_ports clk]
```

- [ ] **Step 2: Create the project with external source references**

Part: `xc7a200tfbg484-2`.

Do not duplicate portable sources into project-local source directories. Ensure the ROM memory file is available to simulation and synthesis.

- [ ] **Step 3: Document the numeric/angle/valid contract**

README must contain raw integer formats and physical scaling, binary-angle examples, quarter-wave LUT symmetry, rounding/saturation, actual measured pipeline latency, and the explicit choice of LUT+DSP rather than CORDIC.

- [ ] **Step 4: Commit**

```bash
git add motor_control_ip/foc/README.md FOC_Transforms
git commit -m "build: add Step 6C1 Vivado project"
```

---

### Task 7: Automated regression, synthesis, route and resource audit

**Files:**
- Create: `scripts/step6c1_foc_transforms_build.tcl`
- Create/update: `docs/reports/step6c1/*`

**Interfaces:**
- Consumes portable Step 6C1 sources and accepted Step 6A/6B regressions.
- Produces text evidence for PR review.

- [ ] **Step 1: Implement build guards**

Require Vivado 2026.1, part `xc7a200tfbg484-2`, top `mc_current_transform`, and one 20.000 ns clock.

- [ ] **Step 2: Run all Step 6C1 simulations**

Capture separate logs for `mc_clarke_tb`, `mc_sincos_lut_tb`, `mc_park_tb`, and `mc_current_transform_tb`.

Require exact PASS markers and reject `$error/$fatal` text.

- [ ] **Step 3: Run accepted regressions**

Run:

```bash
python scripts/reference_audit/verify_step6a_vectors.py
python scripts/step6c1_fixed_transform_reference.py --check
```

Also run the accepted Step 6B `motor_pwm_core_tb` without modifying its source.

- [ ] **Step 4: Synthesize and route**

Run through `route_design` and generate at minimum:

```text
docs/reports/step6c1/build_result.txt
docs/reports/step6c1/synth_utilization.rpt
docs/reports/step6c1/impl_utilization.rpt
docs/reports/step6c1/timing_summary.rpt
docs/reports/step6c1/check_timing.rpt
docs/reports/step6c1/route_status.rpt
docs/reports/step6c1/messages.txt
docs/reports/step6c1/resource_audit.txt
```

- [ ] **Step 5: Enforce internal timing**

Require WNS >= 0, TNS == 0, WHS >= 0, THS == 0, and no unconstrained internal endpoints.

- [ ] **Step 6: Audit DSP/BRAM inference**

Record DSP48E1, BRAM36/RAMB36, LUT/FF and latch counts.

Expected shape for `mc_current_transform`: approximately 6 DSP48E1 and 2 BRAM36. If mapping differs, inspect synthesized hierarchy and explain before accepting.

- [ ] **Step 7: Run the full batch build**

Example:

```powershell
& E:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat -mode batch -nojournal -log .Xil/step6c1_build.log -source scripts/step6c1_foc_transforms_build.tcl
```

Required build marker:

```text
STEP6C1_BUILD_PASS
```

- [ ] **Step 8: Commit evidence**

```bash
git add scripts/step6c1_foc_transforms_build.tcl docs/reports/step6c1
git commit -m "test: verify Step 6C1 transforms in Vivado"
```

---

### Task 8: Final report, scope audit and PR

**Files:**
- Create: `coordination/reports/step6c1_codex_report.md`

**Interfaces:**
- Produces review handoff only; no Step 6C2 code.

- [ ] **Step 1: Write the report**

Include exact measured block/full latency, max sin/cos ideal error, max fixed-point-vs-Step6A alpha/beta/id/iq differences, DSP48/BRAM/LUT/FF counts, route/timing, regressions, and any inference deviation.

- [ ] **Step 2: Scope check**

```bash
git status --short
git diff --check main...HEAD
git diff --name-only main...HEAD
```

Confirm no protected-area changes and no Step 6C2 functionality.

- [ ] **Step 3: Commit**

```bash
git add coordination/reports/step6c1_codex_report.md
git commit -m "docs: report Step 6C1 transform results"
```

- [ ] **Step 4: Push and open PR**

```bash
git push -u origin step6c1-fixed-point-transforms
```

PR title:

```text
Step 6C1: Add fixed-point FOC transform foundation
```

PR body must state the LUT+DSP48 architecture, exact formats, measured latency, fixed-reference/Step6A comparisons, simulations/regressions, resource/timing results, and that no Step 6C2/ADC/PWM-integration/bitstream/hardware work was performed.

Stop at the open PR for ChatGPT review.
