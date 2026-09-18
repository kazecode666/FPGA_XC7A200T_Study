# Step 6C1 Task 1 report — fixed-point software oracle

Date: 2026-09-18

## Scope and result

Implemented only the Step 6C1 software reference and deterministic data artifacts. No RTL,
Vivado project, constraints, PI, SVPWM, ADC, PWM integration, bitstream, or hardware work was
added. Existing dirty `.xpr` and `.xlsx` files were preserved and are not part of the commit.

The oracle implements signed 24-bit F15 phase-current quantization, signed 25-bit F15
transform values, signed 18-bit F16 coefficients, unsigned 16-bit binary angle, full-precision
products/accumulators, magnitude-based round-to-nearest/ties-away-from-zero, and explicit
signed saturation. The authoritative ROM formula is used as written; its final ten entries
round to 65536, so the generator checks `values[-1] <= 65536` rather than the erroneous strict
inequality from the initial plan example.

## Generated artifacts

- `motor_control_ip/foc/rom/sin_qw_4096x18.mem`: 4096 uppercase five-hex-digit 18-bit words.
- `coordination/reports/step6c1_fixed_transform_vectors.csv`: all 160 Step 6A rows, including
  quantized inputs, Clarke, LUT sin/cos, Park, and inverse-Park from `ud_lim/uq_lim`, plus the
  corresponding Step 6A `i_alpha/i_beta/id/iq/v_alpha/v_beta` values.
- `motor_control_ip/foc/tb/vectors/clarke_vectors.txt`: decimal rows
  `ia_raw ib_raw ic_raw i_alpha_raw i_beta_raw`; five directed rows plus all 160 Step 6A rows.
- `motor_control_ip/foc/tb/vectors/sincos_all_phases.txt`: decimal rows
  `theta_u16 sin_raw cos_raw` for every phase word 0 through 65535.
- `motor_control_ip/foc/tb/vectors/park_vectors.txt`: decimal rows
  `i_alpha_raw i_beta_raw theta_u16 sin_raw cos_raw id_raw iq_raw`; directed axes,
  positive/negative saturation, exact half-LSB and adjacent rounding cases, plus 128 vectors
  from fixed seed `0x6C1`. For standalone rounding rows, explicit sin/cos columns are the DUT
  inputs and the theta column is descriptive.
- `motor_control_ip/foc/tb/vectors/inv_park_vectors.txt`: decimal rows
  `d_raw q_raw theta_u16 sin_raw cos_raw alpha_raw beta_raw`; Park round-trip inputs plus
  independent positive/negative saturation cases.
- `motor_control_ip/foc/tb/vectors/current_transform_transactions.txt`: decimal rows
  `transaction_id ia_raw ib_raw ic_raw theta_u16 i_alpha_raw i_beta_raw sin_raw cos_raw id_raw iq_raw`;
  all 160 Step 6A rows followed by 96 fixed-seed distinct consecutive transactions.

Lines beginning with `#` are schema comments. All numeric fixture fields are plain signed or
unsigned decimal integers, one transaction per line, so SystemVerilog `$fscanf` readers do not
need hexadecimal or CSV parsing.

## Self-check coverage

`--check` regenerates every artifact in memory and compares it byte-for-byte with the checked-in
file. It also checks ROM length/order/endpoints, exact axes and all 65536 phase words against
ideal sine/cosine, Clarke balanced input, Park and inverse-Park saturation, and helper corner
cases. Helper checks include exact negative multiples, positive and negative half-LSB ties,
one raw count below and above each tie, signed-44 most-negative magnitude, one-bit division,
and both signed 25-bit clipping rails.

## Numeric bounds measured by the oracle

All errors below are maxima over the 160 Step 6A rows unless noted. Physical values use F15;
ideal transform comparisons use the quantized physical inputs and mathematical sine/cosine at
the Step 6A electrical angle.

| Quantity | Maximum absolute error |
|---|---:|
| sin/cos versus mathematical ideal, all 65536 phases | 0.000295057788 |
| i_alpha versus ideal | 0.0000101725261 A |
| i_beta versus ideal | 0.0000100701378 A |
| id versus ideal | 0.0000101725261 A |
| iq versus ideal | 0.0000256175067 A |
| v_alpha versus ideal | 0.00198968832 V |
| v_beta versus ideal | 0.00461102494 V |
| i_alpha versus Step 6A | 0.000012207031 A |
| i_beta versus Step 6A | 0.0000135940039 A |
| id versus Step 6A | 0.0000135940039 A |
| iq versus Step 6A | 0.0000217200291 A |
| v_alpha versus Step 6A | 0.00182476465 V |
| v_beta versus Step 6A | 0.00469674940 V |

The Step 6A comparison is a bounded algorithm-level comparison, not bit-exact acceptance,
because Step 6A used its Simulink lookup behavior. Inverse-Park comparison explicitly uses
Step 6A `ud_lim/uq_lim` as inputs and `v_alpha/v_beta` as references.

The separate unsaturated Park-to-inverse-Park test uses 1000 fixed-seed vectors limited to
plus/minus 8 physical units. No intermediate or returned output reaches a 25-bit rail. Its
maximum round-trip error is 5 raw F15 LSBs, or 0.000152587891 physical units. Deliberate
saturation tests are excluded from that round-trip bound and checked separately against the
positive and negative 25-bit rails.

## Commands and result

```text
python scripts/step6c1_fixed_transform_reference.py --generate
python scripts/step6c1_fixed_transform_reference.py --check
git diff --check
```

Result: PASS — 4096 ROM entries, all 65536 phase words, all 160 Step 6A rows, deterministic
fixture comparisons, ideal error bound, helper corner cases, saturation cases, and unsaturated
round-trip checks.

Task 1 intentionally provides software expectations only. RTL latency, HDL bit-exact matches,
DSP/BRAM inference, Vivado timing, and integration-marker evidence remain for later authorized
Step 6C1 tasks.
