# Task 1 report: independent C3 integer oracle and fixtures

## Scope and commit

- Base commit: `633ffa9b81b7499bdf29353325043c6a34ad267e`
- Oracle-stage implementation commit: `TO_BE_RECORDED_AFTER_COMMIT`
- Branch: `step6c3-sector-svpwm`
- Tool: Python 3.14.6
- Scope completed: Task 1 only; no RTL, Vivado, bitstream, hardware, C4 or 6D work.

No accepted C1/C2/PWM, Step 6A source/verifier, specification, task book,
constraint or handoff file was changed.

## RED and GREEN

The explicit oracle tests were written first. The initial command

```text
python scripts/step6c3_svpwm_reference_test.py
```

exited `1` with the expected failure:

```text
ModuleNotFoundError: No module named 'step6c3_svpwm_reference'
```

After the integer oracle was implemented, the same command ran 14 tests and
reported `OK`. The tests cover the literal zero identity, six interior sectors,
exact cmp1 and cmp2 `-1/0/+1`, named cmp1 plan points, signed nearest/ties-away
rounding, isolated and full-top `SUM=BASE-1/BASE/BASE+1`, clear
overmodulation, negative unclamped dwell/duty and invalid vdc.

Fresh GREEN commands and results:

```text
python scripts/step6c3_svpwm_reference_test.py
Ran 14 tests in 0.001s — OK

python scripts/step6c3_svpwm_reference.py --generate
STEP6C3_REFERENCE_GENERATE_PASS

python scripts/step6c3_svpwm_reference.py --check
STEP6C3_REFERENCE_CHECK_PASS

python scripts/reference_audit/verify_step6a_vectors.py
PASS: 160 actual-source rows, 2926 checks, max absolute error 5.46e-12

python -m py_compile scripts/step6c3_svpwm_reference.py scripts/step6c3_svpwm_reference_test.py
exit 0

git diff --check
exit 0
```

## Oracle behavior

The implementation uses arbitrary-precision Python integers, ordinary
`divmod` and explicit signed nearest/ties-away rounding. It does not reproduce
the RTL divider state machine. The public calculation interface is:

```text
round_shift_away(x, shift)
sector_xyz(A, B)
round_div_signed(num, den, frac_bits=32)
dwell_from_ab(a_num, b_num, vdc_raw)
duty_from_sector(sector, t1, t2)
svpwm_step(A, B, vdc_raw)
```

`svpwm_step` consumes signed S25/F15 raw `v_alpha/v_beta/vdc`. Successful
results expose sector predicates, XYZ, selected `a_num/b_num`,
`SUM/BASE/denominator`, `overmodulated`, S34/F32 `t1/t2/L/M/H`, unclamped
signed S26/F24 `duty_u/v/w` and `error_code`.

## Fixture schema and counts

The exact schema, widths, signedness, count, fixed seed and numeric tag map are
recorded in `motor_control_ip/foc/tb/vectors/step6c3/manifest.json`.

```text
sector_xyz_vectors.txt (790 rows)
id tag_id v_alpha v_beta cmp0 cmp1 cmp2 b0 b1 b2 sector X Y Z a_num b_num

svpwm_vectors.txt (790 rows)
id tag_id v_alpha v_beta vdc sector overmodulated error_code
a_num b_num sum_num base denominator t1 t2 L M H duty_u duty_v duty_w
```

Counts are 22 directed plus 768 seeded valid full-top cases using seed
`0x6c32026`. The two invalid-vdc directed rows retain deterministic error
outputs; the 768 seeded rows all complete successfully.

## Actual Step 6A replay

The replay reads the committed 160-row CSV directly, quantizes only
`v_alpha/v_beta/vdc` to S25/F15 with Decimal ties-away rounding, and requires
exactly 80 rows per `parameter_profile`. The observed sector mismatches are
exactly the four authorized profile/case pairs:

```text
real_commissioning / edge_1_1.732
real_commissioning / edge_1_-1.732
MIL_PI_override / edge_1_1.732
MIL_PI_override / edge_1_-1.732
```

Maximum normalized errors against Step 6A are:

| Quantity | Maximum | Gate |
|---|---:|---:|
| t1 | 0.000015665495423478064619140625 | 0.00005 |
| t2 | 0.000008176039042934234619140625 | 0.00005 |
| duty_u | 0.0000042531884765625 | 0.00005 |
| duty_v | 0.000011942187652587890625 | 0.00005 |
| duty_w | 0.000011942187652587890625 | 0.00005 |

The complete row-by-row result is in
`coordination/reports/step6c3_svpwm_fixed_vectors.csv`.

## Independent Decimal check

Decimal uses the authoritative literal constants `0.866`, `1.7321` and `1.5`
at 90-digit working precision. Maximum errors are:

| Quantity | Maximum | Gate |
|---|---:|---:|
| t1 | 1.163756379763150214951610163E-10 | 1 F32 LSB = 2.3283064365386962890625E-10 |
| t2 | 1.163803832810451960356081654E-10 | 1 F32 LSB = 2.3283064365386962890625E-10 |
| duty_u | 2.998324514952515700490021689E-8 | 2 F24 LSB = 1.1920928955078125E-7 |
| duty_v | 2.993006103390715006609344174E-8 | 2 F24 LSB = 1.1920928955078125E-7 |
| duty_w | 2.983541967130818058279771914E-8 | 2 F24 LSB = 1.1920928955078125E-7 |

No numerical or specification conflict was found. Focused RTL mutation runs
remain later-task work; this stage supplies directed tags that target the four
specified mutation classes without adding a broad failure catalogue.
