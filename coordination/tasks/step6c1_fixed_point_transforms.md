# Step 6C1 — Fixed-Point Clarke/Park/SinCos Foundation

This is the current ChatGPT -> Codex implementation task after Step 6B.

## Preconditions

- PR #11 (`Step 6B: Add three-phase motor PWM core`) is merged into `main`.
- The Step 6 motor-control architecture is approved.
- The user selected the DSP48-oriented fixed-point approach for Step 6C1.
- Pull latest `main` before branching.

## Governing specifications

Read in this order:

1. `coordination/HANDOFF.md`
2. `coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`
3. `coordination/specs/step6c1_fixed_point_transforms.md`
4. `coordination/reports/step6a_pi_foc_reference_audit.md`
5. `coordination/reports/step6a_pi_foc_golden_vectors.csv`

The Step 6C1 numeric spec is authoritative for bit widths, rounding, saturation, binary-angle representation and LUT behavior.

---

## Goal

Implement and verify:

- fixed-point helper package;
- Clarke transform;
- 16-bit binary-angle sine/cosine quarter-wave BRAM LUT;
- Park transform;
- inverse Park transform;
- a current-transform wrapper that launches Clarke and sin/cos coherently and feeds Park;
- deterministic software fixed-point reference;
- self-checking unit/integration testbenches;
- Vivado 2026.1 synthesis/route/timing/resource evidence.

Do not implement PI/limiter/SVPWM/PWM integration or hardware acquisition.

---

## Required portable source layout

Create:

```text
motor_control_ip/foc/
  README.md
  rom/
    sin_qw_4096x18.mem
  rtl/
    mc_fxp_pkg.sv
    mc_clarke.sv
    mc_sincos_lut.sv
    mc_park.sv
    mc_inv_park.sv
    mc_current_transform.sv
  tb/
    mc_clarke_tb.sv
    mc_sincos_lut_tb.sv
    mc_park_tb.sv
    mc_current_transform_tb.sv
```

Also create:

```text
scripts/step6c1_fixed_transform_reference.py
scripts/step6c1_foc_transforms_build.tcl
FOC_Transforms/FOC_Transforms.xpr
FOC_Transforms/FOC_Transforms.srcs/constrs_1/new/foc_transforms_clock.xdc
coordination/reports/step6c1_codex_report.md
coordination/reports/step6c1_fixed_transform_vectors.csv
docs/reports/step6c1/
```

The Vivado project must reference the portable `motor_control_ip/foc/` sources instead of copying them into project-local source directories.

---

## Frozen numeric contract

Use exactly the formats from `coordination/specs/step6c1_fixed_point_transforms.md`.

Key values:

```text
ia/ib/ic          signed 24, F=15
i_alpha/i_beta    signed 25, F=15
id/iq             signed 25, F=15
vd/vq             signed 25, F=15
v_alpha/v_beta    signed 25, F=15
coefficients       signed 18, F=16
sin/cos            signed 18, F=16
theta_e            unsigned 16-bit binary angle

C_TWO_THIRDS = 43691
C_INV_SQRT3  = 37837
SIN_COS_ONE  = 65536
```

Use full 25x18 products before accumulation. Use magnitude-based round-to-nearest/ties-away-from-zero and signed saturation. No silent wraparound.

---

## Sine/cosine contract

Generate and commit one 4096x18 quarter-wave sine ROM.

Use:

```text
quadrant = theta_e[15:14]
q        = theta_e[13:2]
```

Ignore `theta_e[1:0]` for the baseline.

Use the exact quadrant reconstruction from the Step 6C1 spec.

The reusable RTL must infer block memory; do not instantiate `RAMB36E1`.

---

## DSP48 intent

Use ordinary signed SystemVerilog multiplication with inference-friendly registered stages.

A synthesis attribute such as `(* use_dsp = "yes" *)` is allowed where it improves mapping.

Do not instantiate `DSP48E1` directly.

Target resource shape for `mc_current_transform`:

```text
Clarke ~2 DSP48E1
Park   ~4 DSP48E1
total  ~6 DSP48E1
sincos quarter-wave ROM ~2 BRAM36
```

Exact LUT/FF count is not constrained.

If Vivado maps a constant Clarke multiplier into LUT logic despite a correct portable implementation, document that result and the inference attempt instead of breaking portability.

---

## Functional interfaces

Use explicit `clk`, `reset_n`, `input_valid`, `output_valid`.

### `mc_clarke`

Inputs:

```text
clk
reset_n
input_valid
signed [23:0] ia
signed [23:0] ib
signed [23:0] ic
```

Outputs:

```text
output_valid
signed [24:0] i_alpha
signed [24:0] i_beta
```

### `mc_sincos_lut`

Inputs:

```text
clk
reset_n
input_valid
logic [15:0] theta_e
```

Outputs:

```text
output_valid
signed [17:0] sin_theta
signed [17:0] cos_theta
```

### `mc_park`

Inputs:

```text
clk
reset_n
input_valid
signed [24:0] i_alpha
signed [24:0] i_beta
signed [17:0] sin_theta
signed [17:0] cos_theta
```

Outputs:

```text
output_valid
signed [24:0] id
signed [24:0] iq
```

### `mc_inv_park`

Same valid/reset style.

Inputs are signed [24:0] `vd/vq` and signed [17:0] `sin_theta/cos_theta`; outputs signed [24:0] `v_alpha/v_beta`.

### `mc_current_transform`

Inputs:

```text
clk
reset_n
input_valid
signed [23:0] ia
signed [23:0] ib
signed [23:0] ic
logic [15:0] theta_e
```

Outputs at minimum:

```text
output_valid
signed [24:0] i_alpha_dbg
signed [24:0] i_beta_dbg
signed [17:0] sin_theta_dbg
signed [17:0] cos_theta_dbg
signed [24:0] id
signed [24:0] iq
```

The wrapper must preserve transaction identity under back-to-back valid inputs.

---

## Verification

The Python reference is the bit-exact oracle for Step 6C1.

Required self-checking tests:

- Clarke zero/common-mode/balanced/sign/full-range cases;
- sin/cos exact axes and quadrant boundaries;
- sin/cos ideal absolute error <= `5e-4`;
- Park theta=0 and theta=pi/2 identities/sign convention;
- inverse-Park equation tests;
- Park -> inverse-Park round-trip error report;
- all usable Step 6A transform vectors after input quantization;
- back-to-back transactions with IDs proving no cross-sample mixing.

Required final marker:

```text
ALL STEP 6C1 TRANSFORM TESTS PASSED
```

Also rerun:

- Step 6A fixed-vector verifier;
- Step 6B motor PWM self-checking regression.

Do not require bit-exact equality to the Step 6A Simulink sine lookup. Report the difference instead.

---

## Vivado/build acceptance

- Vivado 2026.1.
- Part: `xc7a200tfbg484-2`.
- Clock: 20.000 ns.
- Standalone project: `FOC_Transforms/FOC_Transforms.xpr`.
- Synthesis top: `mc_current_transform`.
- No physical pin/IOSTANDARD constraints.
- No bitstream.
- No hardware programming.
- Route and internal setup/hold timing must pass.
- No inferred latches, combinational loops, unresolved references or multiple drivers.
- Record DSP48/BRAM/LUT/FF utilization.
- Preserve and describe expected external-I/O timing/DRC warnings instead of inventing constraints.

Required report directory:

`docs/reports/step6c1/`

Required final report:

`coordination/reports/step6c1_codex_report.md`

The report must document:

- actual pipeline latency for each block and full `mc_current_transform`;
- actual DSP48/BRAM inference;
- fixed-point-vs-ideal maximum errors;
- fixed-point-vs-Step6A transform differences;
- all regression results;
- routed timing.

---

## Protected areas

Do not modify:

- `PWM_Controller/`;
- `PWM_Breathe/`;
- accepted `motor_control_ip/pwm/` behavior except read-only regression use;
- `simulink模型/`;
- Step 6A reference/golden files.

---

## Git workflow

Branch:

```text
step6c1-fixed-point-transforms
```

PR title:

```text
Step 6C1: Add fixed-point FOC transform foundation
```

Stop at the open PR for ChatGPT review.

Do not merge automatically.

Do not begin Step 6C2.
