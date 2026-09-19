# Step 6C3 Task 2 Sector/XYZ evidence

## Provenance and scope

- Branch: `step6c3-sector-svpwm`
- Base: `0ca48c060b576b4dd632ffd50339448c7aa364be`
- Simulator: Vivado Simulator 2026.1, SW build 6511674
- Launcher: `E:/AMDDesignTools/2026.1/Vivado/bin`
- Flow: non-project `xvlog` -> `xelab` -> `xsim`
- Changed design scope: package, combinational Sector/XYZ RTL and their two TBs only

No accepted C1/C2/PWM source, oracle, fixture, specification, task book or
handoff file was changed. No synthesis, implementation, bitstream or hardware
operation was run in this task.

## RED observed before RTL

The package TB was compiled before `mc_svpwm_pkg.sv` existed:

```text
xvlog -sv motor_control_ip/foc/tb/mc_svpwm_pkg_tb.sv
exit 1
ERROR: [VRFC 10-2989] 'mc_svpwm_pkg' is not declared
```

The Sector/XYZ TB compiled, then failed elaboration before the DUT existed:

```text
xvlog -sv motor_control_ip/foc/tb/mc_svpwm_sector_xyz_tb.sv
xelab mc_svpwm_sector_xyz_tb -s task2_red_sector
combined exit 1
ERROR: [VRFC 10-2063] Module <mc_svpwm_sector_xyz> not found while processing module instance <dut>
ERROR: [XSIM 43-3322] Static elaboration of top level Verilog design unit(s) in library work failed.
```

Generated RED work is retained under the ignored task scratch directories
`task2_red_pkg/` and `task2_red_sector/`.

## Final GREEN

The final fresh invocation compiled all four Task 2 files, elaborated both
tops, and simulated both snapshots:

```text
xvlog -sv mc_svpwm_pkg.sv mc_svpwm_sector_xyz.sv mc_svpwm_pkg_tb.sv mc_svpwm_sector_xyz_tb.sv
xelab mc_svpwm_pkg_tb -s task2_final_pkg
xelab mc_svpwm_sector_xyz_tb -s task2_final_sector
xsim task2_final_pkg -runall
xsim task2_final_sector -runall -testplusarg "VECTOR_DIR=../../../../motor_control_ip/foc/tb/vectors/step6c3"
exit 0

ALL STEP 6C3 SVPWM PKG TESTS PASSED
ALL STEP 6C3 SECTOR XYZ TESTS PASSED rows=790 fields=16 directed=22 seeded=768
```

The package TB covers positive and negative ties, negative odd values,
below/above-half cases, shift zero, both S96 rails, and exact S40/S34/S26 rail
and rail-neighbor predicates. The Sector/XYZ TB uses indexed-byte tokenization,
requires the exact header, exactly 16 fields per row, exactly 790 rows, exact
canonical IDs/tags, and all 22 directed tags. Every RTL field is compared
bit-for-bit with the independent fixture. This includes zero, six interior
sectors, cmp1 and cmp2 at -1/0/+1, and the named `A=25000` points at
`B=43299/43300/43301`.

The independent fixture regeneration check was also fresh:

```text
python scripts/step6c3_svpwm_reference.py --check
STEP6C3_REFERENCE_CHECK_PASS
fixtures: 22 directed + 768 seeded = 790
```

## Focused mutation

A disposable scratch copy changed only:

```text
b1 = (cmp1_w >= 0)
```

to:

```text
b1 = (cmp1_w > 0)
```

The mutant passed `xvlog` and `xelab`, then the boundary TB emitted:

```text
Fatal: SVPWM_SECTOR_XYZ_TB_FAIL: zero vector cmp1=0 sector=0 range_ok=0 expected=0/2/1
Time: 1 ns
```

XSim returns process status zero after this SystemVerilog `$fatal`, so the
mutation gate reads the log and requires the Fatal marker while rejecting the
GREEN marker. Its actual result was:

```text
TASK2_MUTATION_DETECTED boundary Fatal present; PASS marker absent
exit 1
```

The committed RTL remained `b1 = (cmp1_w >= 0)` throughout the mutation run.

## Contract handed to Task 3

`mc_svpwm_pkg` exposes the C3 format/coefficient constants,
`svpwm_round_shift_s96(value, shift)` and signed-fit predicates for S40, S34
and S26. The rounding helper accepts shifts 0 through 95 and returns signed
nearest with half ties away from zero; an invalid larger shift returns X.

`mc_svpwm_sector_xyz` is purely combinational and has no clock, reset or
transaction state. It consumes signed S25/F15 `v_alpha/v_beta` and exposes:

```text
cmp0:S25 cmp1:S36 cmp2:S36 b0 b1 b2 sector:U3
x_num/y_num/z_num/a_num/b_num:S40 xyz_range_ok
```

Task 3 should capture the external input pair, then consume this combinational
stage from the captured values inside its N+128 transaction schedule. All
operands are sign-extended before multiplication, addition/subtraction and
negation. `xyz_range_ok` is asserted only when the three XYZ values, selected
`a_num/b_num`, and sector are representable/legal. A failed check clears the
five stored S40 outputs instead of exposing truncated values. For the complete
S25 input domain the independently checked bounds are below the S40 rails.
