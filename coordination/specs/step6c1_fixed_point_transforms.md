# Step 6C1 — Fixed-Point Numeric Format and Coordinate-Transform Foundation

Date: 2026-09-18

Status: **Approved Step 6C1 design contract.**

Parent architecture:

`coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`

Step 6B motor PWM is accepted and merged as PR #11. Step 6C1 builds the first reusable FOC arithmetic IP. It does **not** implement PI control, the dq limiter, SVPWM, ADC, encoder, or PWM integration.

---

## 1. Goal

Implement and verify a device-portable fixed-point transform foundation:

```text
ia / ib / ic + theta_e + input_valid
              |
              +----> Clarke -------- i_alpha / i_beta ----+
              |                                           |
              +----> sin/cos LUT ---- sin / cos ----------+
                                                          |
                                                          v
                                                        Park
                                                          |
                                                       id / iq
                                                       output_valid
```

Also implement a standalone inverse-Park block using the same fixed-point and sin/cos contract so later Step 6C2/6C4 can reuse it after the PI/limiter path.

The first version deliberately uses **fixed-point + inferred DSP48 multiplication + a BRAM sine lookup table**, not CORDIC and not floating-point IP.

---

## 2. Why this implementation

The XC7A200T has abundant DSP48E1 and BRAM resources. The first implementation prioritizes:

- mathematical clarity relative to the existing Simulink FOC;
- one native-width DSP multiply per transform product where practical;
- deterministic low latency;
- bit-exact fixed-point verification;
- portable RTL inference so later Zynq UltraScale+ migration can use the target device's native DSP/BRAM resources without rewriting the algorithm.

Do not instantiate `DSP48E1`, `RAMB36E1`, or other 7-series primitives in the reusable RTL. Use synthesizable arithmetic/memory inference and synthesis attributes only where necessary.

---

## 3. Golden-vector role

`coordination/reports/step6a_pi_foc_golden_vectors.csv` is the floating-point/Simulink algorithm reference corpus.

For Step 6C1 it is used primarily as a set of trusted input/output cases and conventions:

- phase-current order and signs;
- Clarke convention;
- Park convention;
- electrical-angle convention;
- representative quadrant and sector angles.

It is **not** the bit-exact RTL reference because Step 6A used Simulink double precision plus its observed 800-interval lookup behavior.

Step 6C1 must create a separate **bit-exact fixed-point software reference** using the formats and LUT defined below. RTL must match that fixed-point reference exactly. The software reference must also report bounded differences versus mathematical ideal and Step 6A values.

---

## 4. Frozen fixed-point formats

Use raw signed two's-complement integers in RTL. Do not use `real` in synthesizable modules.

| Quantity | RTL width | Fraction bits | Approximate numeric range |
|---|---:|---:|---:|
| `ia/ib/ic` | signed 24 | 15 | -256 to +255.99997 A |
| `i_alpha/i_beta` | signed 25 | 15 | -512 to +511.99997 A |
| `id/iq` | signed 25 | 15 | -512 to +511.99997 A |
| later `vd/vq` input to inverse Park | signed 25 | 15 | -512 to +511.99997 V |
| `v_alpha/v_beta` | signed 25 | 15 | -512 to +511.99997 V |
| Clarke constants | signed 18 | 16 | sufficient for +/- coefficients |
| `sin_theta/cos_theta` | signed 18 | 16 | -2 to +1.99998 |
| `theta_e` | unsigned 16 | binary angle | 0x0000 = 0, wrap at 2*pi |

The 24-bit phase-current LSB is:

```text
2^-15 A = 30.517578125 uA
```

The following constants are frozen:

```text
C_TWO_THIRDS   = round((2/3)       * 2^16) = 43691
C_INV_SQRT3    = round((1/sqrt(3)) * 2^16) = 37837
SIN_COS_ONE    = 1.0 * 2^16 = 65536
```

Do not silently change these constants to a different approximation in RTL.

---

## 5. Binary electrical angle

The internal FPGA electrical-angle interface is an unsigned 16-bit phase word:

```text
0x0000 -> 0
0x4000 -> pi/2
0x8000 -> pi
0xC000 -> 3*pi/2
wrap   -> 2*pi == 0x0000
```

Reference conversion from radians:

```text
theta_u16 = round(mod(theta_rad, 2*pi) * 65536 / (2*pi)) mod 65536
```

This is an interface representation only; the physical meaning and positive direction remain exactly those established in Step 6A.

---

## 6. Sine/cosine LUT

### 6.1 Architecture

Use one inferred true-dual-read quarter-wave ROM:

```text
4096 entries x signed 18 bits
```

File:

`motor_control_ip/foc/rom/sin_qw_4096x18.mem`

Each entry `k=0..4095` is:

```text
round( sin(k * (pi/2) / 4096) * 2^16 )
```

stored as signed 18-bit two's-complement data.

The exact quarter endpoint +1.0 is not stored. It is represented by constant `65536` when the symmetry mapping reaches the endpoint.

Use a deterministic Python generator. The checked-in ROM file must be regenerable without a Git diff.

### 6.2 Address resolution

Use:

```text
quadrant = theta_e[15:14]
q        = theta_e[13:2]
```

The lowest two phase bits are ignored in the first baseline.

Thus the effective full-circle angular grid is 16384 positions:

```text
360 degrees / 16384 = 0.02197265625 degrees
```

Because address selection truncates the lowest two bits, angular quantization error is less than one grid interval.

For `q != 0`:

```text
mirror = 4096 - q
```

For `q == 0`, the mirrored endpoint magnitude is exactly `SIN_COS_ONE`.

### 6.3 Quadrant reconstruction

Let:

```text
S = ROM[q]
C = (q == 0) ? SIN_COS_ONE : ROM[4096-q]
```

Then:

```text
quadrant 0: sin=+S, cos=+C
quadrant 1: sin=+C, cos=-S
quadrant 2: sin=-S, cos=-C
quadrant 3: sin=-C, cos=+S
```

Exact axes 0, pi/2, pi, 3*pi/2 must therefore produce exact fixed-point 0 and +/-1 values.

### 6.4 ROM inference

The RTL must use synchronous inferred block memory with two read addresses from the same quarter-wave contents. Prefer a coding style that maps to approximately **2 RAMB36-equivalent blocks** on XC7A200T.

A synthesis attribute such as `rom_style = "block"` is allowed. A vendor primitive is not.

If Vivado replicates the ROM and uses more BRAM than expected, document the cause and first attempt an inference-friendly synchronous dual-read coding style before accepting it.

---

## 7. Rounding and saturation

All transform outputs use explicit signed rounding and saturation.

### 7.1 Product format

A native transform multiplication is:

```text
signed 25-bit F15 * signed 18-bit F16
= signed 43-bit F31 product
```

Two such products are added in at least a signed 44-bit accumulator with F31 scaling.

Do not truncate each product to F15 before accumulation.

### 7.2 Output conversion

Convert F31 accumulator/product to F15 by shifting right 16 bits using:

**round-to-nearest, ties away from zero**.

Conceptually:

```text
if x >= 0: adjusted = x + 2^15
if x <  0: adjusted = x - 2^15
rounded = adjusted >>> 16
```

Then saturate to the destination signed width.

No control quantity may silently wrap on overflow.

The bit-exact Python model and RTL helper function must implement the same policy.

---

## 8. Clarke transform

The mathematical reference remains:

```text
i_alpha = (2/3) * (ia - 0.5*ib - 0.5*ic)
i_beta  = (ib - ic) / sqrt(3)
```

Hardware-friendly implementation:

```text
sum_bc    = sign_extend(ib) + sign_extend(ic)      // 25-bit F15
half_bc   = arithmetic_round_or_defined_shift(sum_bc / 2)
alpha_pre = sign_extend(ia) - half_bc              // 25-bit F15
beta_pre  = sign_extend(ib) - sign_extend(ic)      // 25-bit F15

alpha_product = alpha_pre * C_TWO_THIRDS           // 25x18 -> 43-bit F31
beta_product  = beta_pre  * C_INV_SQRT3            // 25x18 -> 43-bit F31

i_alpha = round+saturate(alpha_product -> signed 25 F15)
i_beta  = round+saturate(beta_product  -> signed 25 F15)
```

For the division by two in `half_bc`, freeze a symmetric signed rounding rule in the fixed-point software model and use exactly the same RTL rule. Do not rely on implementation-defined signed truncation.

Target: two inferred DSP multipliers for the two coefficient products.

---

## 9. Park transform

Inputs:

- `i_alpha/i_beta`: signed 25 F15;
- `sin_theta/cos_theta`: signed 18 F16;
- coherent `input_valid`.

Equations:

```text
id =  i_alpha*cos_theta + i_beta*sin_theta
iq = -i_alpha*sin_theta + i_beta*cos_theta
```

Use four parallel 25x18 multiplications.

Keep full product precision before signed accumulation.

Target: four DSP48-class multipliers for Park.

---

## 10. Inverse Park transform

Inputs:

- `vd/vq`: signed 25 F15;
- the same signed 18 F16 `sin_theta/cos_theta` convention;
- coherent `input_valid`.

Equations:

```text
v_alpha = vd*cos_theta - vq*sin_theta
v_beta  = vd*sin_theta + vq*cos_theta
```

Use the same 25x18 / 44-bit-accumulate / round+saturate policy as Park.

This block is implemented and unit-tested in Step 6C1 but is not yet connected to PI/SVPWM.

---

## 11. Pipeline and valid contract

All Step 6C1 modules are synchronous to 50 MHz `clk`.

Use active-LOW reset `reset_n` with asynchronous assertion. Reset must clear valid pipeline state; data outputs may reset to zero.

Submodules use `input_valid` / `output_valid`, not a 10 kHz clock enable.

They must support back-to-back valid inputs at one transaction per fabric clock even though the first integrated FOC controller will initially allow only one control transaction in flight.

No module may infer state that updates every clock independent of valid input.

### Alignment requirement

`mc_clarke` and `mc_sincos_lut` are launched by the same accepted input transaction and must reach `mc_park` coherently.

The implementation must use explicit registered valid/data pipelines. Never pair:

```text
i_alpha[k], i_beta[k]
```

with:

```text
sin(theta[k+1]), cos(theta[k+1])
```

Exact pipeline latency is allowed to be selected by the RTL implementation for clean DSP/BRAM inference, but it must be:

- deterministic;
- documented in the README/report;
- automatically checked by transaction IDs in the testbench;
- less than 32 fabric clocks for the complete Clarke + sincos + Park path.

At 50 MHz this upper bound is 640 ns, far below the future 50 us integration deadline.

---

## 12. Portable module structure

Create:

```text
motor_control_ip/
  foc/
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

Responsibilities:

- `mc_fxp_pkg.sv`: widths, fraction-bit constants, coefficient constants, reusable signed round/saturate helpers.
- `mc_clarke.sv`: phase currents -> alpha/beta.
- `mc_sincos_lut.sv`: binary angle -> sin/cos.
- `mc_park.sv`: alpha/beta + sin/cos -> d/q.
- `mc_inv_park.sv`: d/q-like voltage + sin/cos -> alpha/beta.
- `mc_current_transform.sv`: launch Clarke and sincos in parallel, align them, run Park, expose debug outputs and valid.

Do not mix PI, limiter, SVPWM, PWM, ADC, or encoder logic into these files.

---

## 13. Software fixed-point reference

Create:

`scripts/step6c1_fixed_transform_reference.py`

It must:

1. regenerate the quarter-wave LUT using the exact rule in this spec;
2. implement binary-angle conversion;
3. implement the same signed rounding/saturation rules as RTL;
4. implement bit-exact Clarke, LUT sincos, Park and inverse Park calculations;
5. read `coordination/reports/step6a_pi_foc_golden_vectors.csv`;
6. emit a Step 6C1 fixed-point comparison CSV/report;
7. report max error versus ideal mathematical sin/cos and Step 6A transform columns;
8. never overwrite Step 6A source/golden files.

Bit-exact RTL acceptance is against this fixed-point reference.

---

## 14. Verification requirements

### 14.1 Clarke

Check at least:

- zero input;
- common mode `(+1,+1,+1)` -> approximately zero alpha/beta under fixed-point rules;
- balanced `(1,-0.5,-0.5)`;
- positive/negative near full-scale patterns;
- all Step 6A transform-relevant rows after quantizing their inputs.

### 14.2 Sin/cos

Check:

- exact axes `0x0000/0x4000/0x8000/0xC000`;
- all four quadrants;
- values adjacent to quadrant boundaries;
- addresses `q=0,1,4094,4095`;
- wrapping across `0xFFFF -> 0x0000`;
- sweep enough phase words to verify signs/symmetry;
- absolute error versus ideal sine/cosine no greater than `5e-4`.

### 14.3 Park

Check:

- theta=0 identity;
- theta=pi/2 axis rotation;
- sign convention;
- Step 6A angle cases;
- randomized/reference-vector cases;
- bit-exact integer match to the Python fixed-point model.

### 14.4 Inverse Park

Check the inverse equations bit-exactly against the fixed model.

Also run Park -> inverse-Park round-trip vectors and report error relative to original alpha/beta. Round-trip need not be bit-identical because LUT/rounding quantization is expected.

### 14.5 Pipeline association

Drive multiple consecutive transactions with distinct transaction IDs and values.

Assert that each output corresponds to the same input transaction after one deterministic latency. No cross-sample mixing is allowed.

Required integration test marker:

```text
ALL STEP 6C1 TRANSFORM TESTS PASSED
```

---

## 15. Vivado build and resource evidence

Create an independent project:

```text
FOC_Transforms/FOC_Transforms.xpr
```

Target:

`xc7a200tfbg484-2`

Clock-only constraint:

```tcl
create_clock -name sys_clk -period 20.000 [get_ports clk]
```

Create:

`scripts/step6c1_foc_transforms_build.tcl`

The automated build must:

- require Vivado 2026.1;
- run all Step 6C1 self-checking tests;
- run Step 6B motor PWM regression and the existing Step 6A fixed-reference verifier;
- synthesize and route the default Step 6C1 current-transform top;
- report utilization, route status and 50 MHz timing;
- preserve expected unconstrained external-I/O warnings rather than invent board constraints;
- generate no bitstream;
- perform no hardware programming.

Expected resource shape for `mc_current_transform`:

- Park: approximately 4 DSP48E1;
- Clarke: target approximately 2 DSP48E1;
- total transform datapath: target approximately 6 DSP48E1;
- quarter-wave dual-read LUT: target approximately 2 BRAM36;
- zero inferred latches.

Exact LUT/FF counts are not acceptance limits.

If DSP count is unexpectedly zero or a 25x18 product is split into multiple DSP blocks, inspect signed widths and inference before accepting.

If constant Clarke multiplication is optimized to logic despite an inference-friendly implementation, report it explicitly; do not instantiate Artix-7-specific DSP primitives merely to force a count.

---

## 16. Scope exclusions

Step 6C1 does **not** implement:

- PI d/q controller;
- decoupling/feedforward;
- dq voltage limiter;
- anti-windup state;
- SVPWM;
- normalized duty or duty-to-CMP;
- motor PWM integration;
- ADC9238;
- current calibration;
- encoder/QEP;
- speed/position loops;
- CORDIC;
- floating-point IP;
- dead time/trip;
- board pin mapping or bitstream.

---

## 17. Acceptance

Step 6C1 is accepted when:

1. fixed-point formats/constants in this document are implemented exactly;
2. the 16-bit binary-angle convention is implemented exactly;
3. the checked-in LUT regenerates deterministically;
4. Clarke is bit-exact to the fixed-point software model;
5. sin/cos axes, quadrants, symmetry and error bounds pass;
6. Park and inverse Park are bit-exact to the fixed-point model;
7. pipeline transaction association passes under consecutive valid inputs;
8. the integration test reports `ALL STEP 6C1 TRANSFORM TESTS PASSED`;
9. Step 6A/Step 6B regressions remain passing;
10. Vivado 2026.1 synthesis/route meets internal 50 MHz timing;
11. resource mapping demonstrates sensible DSP48/BRAM inference and zero latches;
12. no protected legacy/reference assets are modified;
13. no Step 6C2 or later functionality is started.
