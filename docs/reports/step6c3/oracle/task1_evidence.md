# Step 6C3 Task 1 oracle evidence

Date: 2026-09-19

Base: `633ffa9b81b7499bdf29353325043c6a34ad267e`

Tool: Python 3.14.6

## RED

Command:

```text
python scripts/step6c3_svpwm_reference_test.py
```

Observed exit code: `1`.

Observed failure before the oracle existed:

```text
ModuleNotFoundError: No module named 'step6c3_svpwm_reference'
```

This was the expected missing-production-code failure after the tests had been
written and before `scripts/step6c3_svpwm_reference.py` was created.

## GREEN

```text
python scripts/step6c3_svpwm_reference_test.py
Ran 14 tests in 0.001s
OK

python scripts/step6c3_svpwm_reference.py --generate
STEP6C3_REFERENCE_GENERATE_PASS
fixtures: 22 directed + 768 seeded = 790

python scripts/step6c3_svpwm_reference.py --check
STEP6C3_REFERENCE_CHECK_PASS
fixtures: 22 directed + 768 seeded = 790

python scripts/reference_audit/verify_step6a_vectors.py
PASS: 160 actual-source rows, 2926 checks, max absolute error 5.46e-12

python -m py_compile scripts/step6c3_svpwm_reference.py scripts/step6c3_svpwm_reference_test.py
exit 0

git diff --check
exit 0
```

## Numerical gates

The actual Step 6A replay used the committed CSV directly and verified exactly
80 rows for each `parameter_profile`.

| Quantity | Maximum normalized error | Limit |
|---|---:|---:|
| t1 | 0.000015665495423478064619140625 | 0.00005 |
| t2 | 0.000008176039042934234619140625 | 0.00005 |
| duty_u | 0.0000042531884765625 | 0.00005 |
| duty_v | 0.000011942187652587890625 | 0.00005 |
| duty_w | 0.000011942187652587890625 | 0.00005 |

The observed sector mismatch set was exactly:

```text
real_commissioning / edge_1_1.732
real_commissioning / edge_1_-1.732
MIL_PI_override / edge_1_1.732
MIL_PI_override / edge_1_-1.732
```

The independent Decimal check maxima were:

| Quantity | Maximum error | Limit |
|---|---:|---:|
| t1 | 1.163756379763150214951610163E-10 | 1 F32 LSB = 2.3283064365386962890625E-10 |
| t2 | 1.163803832810451960356081654E-10 | 1 F32 LSB = 2.3283064365386962890625E-10 |
| duty_u | 2.998324514952515700490021689E-8 | 2 F24 LSB = 1.1920928955078125E-7 |
| duty_v | 2.993006103390715006609344174E-8 | 2 F24 LSB = 1.1920928955078125E-7 |
| duty_w | 2.983541967130818058279771914E-8 | 2 F24 LSB = 1.1920928955078125E-7 |

## Fixture interface

Both text fixtures use fixed-width lowercase hexadecimal, exact-width two's
complement for signed fields, one `#` column header and no blank rows. The
manifest is the machine-readable authority for widths, signedness, counts,
seed `0x6c32026` and numeric directed-tag meanings.

`sector_xyz_vectors.txt` columns:

```text
id tag_id v_alpha v_beta cmp0 cmp1 cmp2 b0 b1 b2 sector X Y Z a_num b_num
```

`svpwm_vectors.txt` columns:

```text
id tag_id v_alpha v_beta vdc sector overmodulated error_code
a_num b_num sum_num base denominator t1 t2 L M H duty_u duty_v duty_w
```

Each fixture has 790 rows: 22 directed rows and 768 deterministic seeded valid
full-top rows. Directed tags cover zero, all six sector interiors, exact cmp1
and cmp2 values `-1/0/+1`, the named cmp1 plan points `+250/0/-250`, full-top
`SUM=BASE-1/BASE/BASE+1`, clear overmodulation, a negative unclamped result,
and zero/negative vdc.
