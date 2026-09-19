# Step 6C3 — Fixed-Point Sector SVPWM to Normalized Duty

Date: 2026-09-19.
Baseline: PR #14 merged to `main` at `da7151d773df10d7614bcc92ac453145ffda1463`.
Status: **Design contract for review.** This document defines the learning-oriented C3 baseline. It does not authorize RTL implementation by itself.

## 1. Purpose and learning scope

Step 6C3 implements the standalone mapping

```text
v_alpha, v_beta, vdc
        |
        v
   sector selection
        |
        v
      X/Y/Z
        |
        v
       T1/T2
        |
        v
      L/M/H
        |
        v
normalized duty_u/v/w
```

The goal is to make the complete Sector-SVPWM data path visible, understandable and independently verifiable before C4 connects the full FOC chain.

This is a learning-stage implementation, not a product-hardening task. Build the mathematical framework and main function first; add only the boundary/error checks needed to make the behavior deterministic and debuggable.

C3 does **not** implement:

- C1 transforms or inverse-Park integration;
- C2 PI/limiter integration;
- duty-to-CMP conversion;
- `motor_pwm_core` integration;
- ADC/encoder interfaces;
- dead time, complementary gates or trips;
- board pin constraints;
- bitstream generation or hardware operation;
- Step 6C4 or Step 6D.

## 2. Reference priority

Use this authority order:

1. this C3 numeric/interface contract;
2. `coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`;
3. Step 6A audited Sector-SVPWM equations and actual golden CSV;
4. the accepted C1/C2 interface formats;
5. historical DSP/MIL behavior only as background.

The first FPGA baseline intentionally keeps the audited Step 6A Sector -> XYZ -> T1/T2 -> Duty algorithm. Do **not** replace it with Min-Max SVPWM.

Historical DSP/MIL raw PWM counts are not the C3 interface. C3 outputs normalized active-high duty only.

## 3. External transaction interface

Top module:

```text
mc_sector_svpwm
```

Inputs:

```text
clk
reset_n
input_valid
signed [24:0] v_alpha   // S25/F15
signed [24:0] v_beta    // S25/F15
signed [24:0] vdc       // S25/F15, valid only when > 0
```

Outputs:

```text
input_ready
output_valid
signed [25:0] duty_u    // S26/F24
signed [25:0] duty_v    // S26/F24
signed [25:0] duty_w    // S26/F24
logic [2:0] sector
logic overmodulated
logic [1:0] error_code
```

Duty representation:

```text
0.0 = 0
0.5 = 8_388_608
1.0 = 16_777_216
```

C3 deliberately keeps duty signed. It shall not silently clamp outputs into [0,1].

Error encoding:

```text
00 OK
01 INVALID_VDC
10 RANGE_ERROR
11 INTERNAL_ERROR
```

`output_valid` means the transaction completed, including error responses. A future wrapper may use a result only when:

```text
output_valid && error_code == OK
```

## 4. Sector selection

Let:

```text
A = v_alpha raw S25/F15 integer
B = v_beta  raw S25/F15 integer
```

Step 6A uses:

```text
B0 = B
B1 = 0.866*A - 0.5*B
B2 = -0.866*A - 0.5*B

b0 = (B0 > 0)
b1 = (B1 >= 0)
b2 = (B2 > 0)

sector = b0 + 2*b1 + 4*b2
```

C3 evaluates the same decimal boundaries exactly in integer form:

```text
b0 = (B > 0)
b1 = (433*A - 250*B >= 0)
b2 = (-433*A - 250*B > 0)

sector = b0 + 2*b1 + 4*b2
```

Use widened signed temporaries before the comparisons. No intermediate wrap is allowed.

At zero vector:

```text
A = 0
B = 0
sector = 2
```

The six-sector numbering/tie behavior remains the Step 6A numbering.

## 5. XYZ integer calculation

Keep the audited decimal constants exactly:

```text
0.866
1.7321
1.5
```

Use a common denominator of 10000:

```text
X_num = 17321*B
Y_num =  8660*B + 15000*A
Z_num =  8660*B - 15000*A
```

Store the selected XYZ results as signed 40-bit values after widened multiply/add calculations and explicit range checking.

Select provisional dwell numerators:

| Sector | a_num | b_num |
|---:|---|---|
| 1 | Z_num | Y_num |
| 2 | Y_num | -X_num |
| 3 | -Z_num | X_num |
| 4 | -X_num | Z_num |
| 5 | X_num | -Y_num |
| 6 | -Y_num | -Z_num |

A small negative `a_num` or `b_num` near a sector boundary is legal mathematical output. Do not clamp it to zero.

## 6. Normalized dwell and overmodulation

Define:

```text
BASE = 10000 * vdc_raw
SUM  = a_num + b_num
```

Use widened signed arithmetic for `SUM`. Validate `vdc > 0` before treating `BASE` as a positive denominator.

Linear region:

```text
SUM <= BASE

denominator = BASE
t1 = a_num / BASE
t2 = b_num / BASE
overmodulated = 0
```

Overmodulation normalization:

```text
SUM > BASE

denominator = SUM
t1 = a_num / SUM
t2 = b_num / SUM
overmodulated = 1
```

Therefore `SUM == BASE` is the non-overmodulated branch.

The normalized dwell values are:

```text
t1 = T1/T
t2 = T2/T
```

C3 shall not represent `Ts=100 us` internally and shall not use the historical `CPU_Clock=200 MHz` count scaling.

## 7. Divider reuse and dwell format

Reuse the accepted C2 divider:

```text
mc_udiv_u72_u41
```

Instantiate two dividers in parallel, one for T1 and one for T2. Do not modify the accepted divider RTL as part of C3.

Internal normalized dwell format:

```text
t1, t2 : S34/F32
```

Generate magnitude division using:

```text
numerator = abs(a_num or b_num) << 32
denominator = positive selected denominator
```

The C2 U72/U41 divider widths are sufficient for the C3 arithmetic domain.

Use quotient and remainder to implement round-to-nearest, ties-away-from-zero:

```text
q = floor(abs(num)*2^32 / den)
r = remainder

if 2*r >= den:
    q = q + 1

restore original numerator sign
```

No plain truncation is permitted for the C3 normalized dwell output.

## 8. L/M/H and phase mapping

Using S34/F32 `t1/t2`, calculate with widened signed temporaries:

```text
L = (1 - t1 - t2) / 2
M = (1 + t1 - t2) / 2
H = (1 + t1 + t2) / 2
```

Represent 1.0 as `2^32`. Divide by two with the same signed nearest/ties-away policy rather than relying on a bare arithmetic shift for negative odd values.

Map to phases:

| Sector | U | V | W |
|---:|---|---|---|
| 1 | M | L | H |
| 2 | L | H | M |
| 3 | L | M | H |
| 4 | H | M | L |
| 5 | H | L | M |
| 6 | M | H | L |

Round F32 results to S26/F24 only at the external duty outputs.

Zero-vector directed identity:

```text
v_alpha = 0
v_beta  = 0
vdc     > 0

sector = 2
t1 = 0
t2 = 0
duty_u = duty_v = duty_w = 8_388_608
```

## 9. No duty clamp in C3

C3 is the algorithm layer. It shall not perform:

```text
clamp(duty, 0, 1)
```

A later `duty_to_cmp` layer in Step 6D owns:

```text
clamp(duty,0,1)
CMP = round(duty * TBPRD)
```

This separation keeps boundary behavior visible during learning and prevents PWM endpoint policy from being hidden inside the SVPWM algorithm.

## 10. RTL structure

Keep the first version small and readable.

Create:

```text
motor_control_ip/foc/rtl/mc_svpwm_pkg.sv
motor_control_ip/foc/rtl/mc_svpwm_sector_xyz.sv
motor_control_ip/foc/rtl/mc_sector_svpwm.sv
```

Responsibilities:

```text
mc_svpwm_pkg
  constants, rounding helpers and range helpers

mc_svpwm_sector_xyz
  v_alpha/v_beta -> sector, X/Y/Z -> a_num/b_num

mc_sector_svpwm
  input capture
  vdc validation
  denominator/overmod selection
  two accepted C2 dividers
  t1/t2 rounding
  L/M/H and U/V/W mapping
  response timing/error aggregation
```

Do not split more modules unless the implementation becomes genuinely difficult to read.

## 11. Timing and reset contract

C3 is single-request-in-flight.

Acceptance occurs only when:

```text
reset_n && input_valid && input_ready
```

Freeze the top response interval:

```text
accepted at N
response at N+128
```

At 50 MHz this is:

```text
128 clocks = 2.56 us
```

Normal, boundary and error paths use the same response slot.

The earliest next acceptance is the clock after completion.

Asynchronous `reset_n=0`:

- aborts pending work;
- clears visible outputs and response valid;
- clears transaction-control state;
- must prevent stale completion after release.

System integration remains responsible for synchronous reset deassertion.

## 12. Error behavior

### INVALID_VDC

If captured `vdc <= 0`:

```text
error_code = INVALID_VDC
duty_u/v/w = 0
sector = 0
overmodulated = 0
```

The response still occurs at N+128.

### RANGE_ERROR

Use RANGE_ERROR only for explicit representability failures such as:

- widened XYZ result cannot fit the specified stored S40 domain;
- normalized dwell cannot fit S34/F32;
- final duty cannot fit S26/F24.

Never wrap.

### INTERNAL_ERROR

Use INTERNAL_ERROR for transaction/invariant failures such as:

- illegal sector value;
- invalid denominator on a supposedly valid path;
- reused divider not ready when scheduled;
- missing/late divider response;
- divider reports divide-by-zero;
- quotient/remainder invariants are violated.

This is a learning baseline; do not build a product-style sticky fault subsystem.

## 13. Verification philosophy

The project goal is framework/function learning first, not exhaustive product qualification.

Verification has three useful levels:

### A. RTL vs independent integer oracle — mandatory bit exact

Create:

```text
scripts/step6c3_svpwm_reference.py
scripts/step6c3_svpwm_reference_test.py
```

The Python oracle uses arbitrary-precision integer arithmetic and normal integer division/modulo; it shall not reproduce the RTL divider state machine.

Compare exactly:

```text
sector
overmodulated
t1/t2 debug values
L/M/H debug values if exposed through hierarchy
duty_u/v/w
error_code
latency/protocol behavior
```

No numerical tolerance applies to integer equality.

### B. Integer oracle vs high-precision Decimal — small precision check

Use the audited decimal constants as Decimal literals.

Target numerical gates:

```text
normalized t1/t2 error <= 1 F32 LSB
duty_u/v/w error <= 2 F24 LSB
```

This checks the chosen fixed-point algorithm itself.

### C. Actual Step 6A 160-row algorithm comparison

Read the committed:

```text
coordination/reports/step6a_pi_foc_golden_vectors.csv
```

Use its `v_alpha`, `v_beta`, `vdc` directly; do not rerun C1/C2 for this standalone comparison.

Compare:

```text
normalized t1/t2 error <= 5e-5
normalized duty_u/v/w error <= 5e-5
```

Normalize Step 6A source duty as:

```text
duty_norm = raw_source_count / 10000
```

Design preflight on the current 160-row CSV found a maximum normalized duty difference of about `1.2e-5` and no overmodulated source rows.

Sector comparison is exact except for four already identified Step 6A boundary rows:

```text
real_commissioning / edge_1_1.732
real_commissioning / edge_1_-1.732
MIL_PI_override / edge_1_1.732
MIL_PI_override / edge_1_-1.732
```

These differences arise after F15 input quantization at intentionally ambiguous boundaries. C3 verification must explicitly list these four rows and fail if an additional sector mismatch appears.

## 14. Minimal directed tests

The first implementation must clearly demonstrate:

1. zero vector -> sector 2 and duty 0.5/0.5/0.5;
2. one interior point for each of the six sectors;
3. exact sector boundary checks at comparator value -1/0/+1;
4. one normal linear-region dwell case;
5. `SUM=BASE-1`, `SUM=BASE`, `SUM=BASE+1`;
6. one clear overmodulation case;
7. a boundary case with negative provisional dwell proving no clamp;
8. `vdc=0` and negative `vdc` error responses;
9. busy-input changes do not alter a captured transaction;
10. reset aborts pending work without stale response;
11. measured acceptance-to-response interval is exactly 128 clocks.

Add approximately 512–1024 deterministic seeded valid vectors for wider arithmetic/sector coverage. Do not make huge random campaigns a prerequisite for the learning baseline.

## 15. Small negative-control set

Keep negative testing focused. In disposable scratch mutations, prove that tests catch a few high-value mistakes:

- change `b1 >= 0` to `b1 > 0`;
- remove overmodulation normalization;
- swap a U/V/W phase mapping;
- clamp negative duty to zero.

These mutations are not committed product code. A large catalog of malformed-fixture/build-failure probes is not required for C3.

## 16. Fixtures and parsing

Create C3 fixtures under:

```text
motor_control_ip/foc/tb/vectors/step6c3/
```

Keep the set small, for example:

```text
sector_xyz_vectors.txt
svpwm_vectors.txt
manifest.json
```

The manifest records exact schema, widths, counts and fixed seeds.

Testbenches must reject missing/extra fixture rows and malformed field counts. Avoid weak gates such as `count >= 100`.

The Python `--check` path regenerates expected fixture text in memory and compares it to checked-in fixtures.

## 17. Vivado learning-stage acceptance

Create a standalone project:

```text
FOC_SVPWM/FOC_SVPWM.xpr
```

Part:

```text
xc7a200tfbg484-2
```

Synthesis top:

```text
mc_sector_svpwm
```

Clock-only XDC:

```text
create_clock -name sys_clk -period 20.000 [get_ports clk]
```

Do not generate a bitstream.

Record actual:

- routed Slice LUT count;
- FF count;
- DSP48 count;
- BRAM count;
- hierarchy;
- WNS/TNS;
- WHS/THS;
- routing completeness.

Hard gates:

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

Retain expected board-only warnings from the clock-only core project. This is internal core timing evidence, not board timing signoff.

No exact DSP count is specified. Let Vivado map constant multipliers naturally and report the result.

## 18. Regression scope

Keep regressions useful but compact.

C3 final work should run:

- C3 package/sector/full SVPWM tests;
- accepted C2 divider TB;
- accepted C2 core TB;
- accepted C1 current-transform TB;
- accepted Step 6B motor PWM TB;
- C3 Python oracle tests/check;
- C2 Python check;
- C1 Python check;
- Step 6A verifier.

Do not rerun synthesis/route for accepted C1/C2/PWM designs unless their sources changed. C3 standalone synthesis/route is sufficient.

Accepted C1/C2/PWM sources are read-only for this task.

## 19. C3 to C4 interface boundary

C4 will later connect:

```text
C1 current transform
        |
        v
C2 PI + limiter
        |
        v
C1 inverse Park
        |
        v
C3 Sector SVPWM
        |
        v
S26/F24 normalized duty
```

C3 receives the same captured transaction's `vdc` that C2 used. A future C4 wrapper must preserve that coherent sample identity.

C2 error responses must not be launched into inverse-Park/C3 as a valid zero-voltage command.

Likewise C3 `output_valid` is completion observability, not automatically a PWM command. Future command validity is equivalent to:

```text
C3 output_valid && C3 error_code == OK
```

Duty-to-CMP and motor PWM timing remain Step 6D responsibilities.

## 20. Completion boundary

Step 6C3 is ready for review when the implementation demonstrates:

- readable Sector -> XYZ -> T1/T2 -> L/M/H -> U/V/W structure;
- exact RTL agreement with the independent integer oracle;
- Step 6A 160-row comparison within the stated tolerance;
- correct six-sector, boundary, overmodulation, invalid-bus, reset and fixed-latency behavior;
- standalone 50 MHz synthesis/route timing closure;
- the compact accepted regressions remain green.

Expected implementation PR title:

```text
Step 6C3: Add fixed-point sector SVPWM
```

Codex stops at the open PR for ChatGPT review. Do not merge automatically or begin C4/C6D.

## 21. Documentation gate

This design document is intentionally simpler than the C2 product-style acceptance book.

After this design PR is reviewed/merged, create a concise C3 Codex task/implementation plan from this contract. The implementation plan should follow the learning-first order:

```text
Python oracle
-> sector/XYZ RTL
-> six-sector/zero-vector bring-up
-> divider + T1/T2
-> duty mapping
-> Step 6A comparison
-> focused boundary/reset/error tests
-> Vivado synth/route
-> compact regressions
-> implementation PR
```
