# Step 6C3 Task 3 top evidence

## Scope

Task 3 adds only the `mc_sector_svpwm` transaction top and its bit-exact
testbench. The accepted package, Sector/XYZ stage and both accepted C2 divider
instances are reused without modification. No synthesis, implementation,
bitstream, hardware, C4 or 6D work was performed.

## TDD RED

The complete top testbench was compiled before the DUT existed:

```text
xvlog -sv mc_svpwm_pkg.sv mc_svpwm_sector_xyz.sv mc_udiv_u72_u41.sv mc_sector_svpwm_tb.sv
exit 0

xelab mc_sector_svpwm_tb -s mc_sector_svpwm_tb_red
exit 1
ERROR: [VRFC 10-2063] Module <mc_sector_svpwm> not found
ERROR: [XSIM 43-3322] Static elaboration ... failed
```

The generated RED work is retained in the ignored task scratch directory
`task3_red_top/`.

## Final GREEN

Vivado Simulator 2026.1 compiled and elaborated the package, accepted
Sector/XYZ and divider RTL, the new top and the new TB. The final marker gate
required the exact PASS marker and rejected `Fatal:`, `ERROR:` and
`FATAL_ERROR`:

```text
xvlog -sv mc_svpwm_pkg.sv mc_svpwm_sector_xyz.sv mc_udiv_u72_u41.sv mc_sector_svpwm.sv mc_sector_svpwm_tb.sv
xelab mc_sector_svpwm_tb -s task3_final3_top
xsim task3_final3_top -runall -testplusarg "VECTOR_DIR=../../../../motor_control_ip/foc/tb/vectors/step6c3"
exit 0

ALL STEP 6C3 SECTOR SVPWM TESTS PASSED rows=790 accepted=791 responses=790 latency=128 aborts=1 poisoned_cycles=101120
PASS_PRESENT=True FATAL_OR_ERROR_PRESENT=False
```

Every one of the 790 fixture rows is checked bit-for-bit. The expected record
is queued only on `input_valid && input_ready`; every response must occur
exactly 128 edges later. The 22 directed tags cover zero, six sector interiors,
all named comparator boundaries, `SUM=BASE-1/BASE/BASE+1`, clear
overmodulation, negative provisional dwell/unclamped duty, and zero/negative
`vdc`. The TB also holds hostile `input_valid` with changing input buses while
busy and proves asynchronous reset aborts a pending request without a stale
response.

The accepted C3 package and Sector/XYZ TBs also passed in the final scratch
run, and the independent fixture checks remained green:

```text
ALL STEP 6C3 SVPWM PKG TESTS PASSED
ALL STEP 6C3 SECTOR XYZ TESTS PASSED rows=790 fields=16 directed=22 seeded=768
python scripts/step6c3_svpwm_reference_test.py: Ran 14 tests — OK
python scripts/step6c3_svpwm_reference.py --check: STEP6C3_REFERENCE_CHECK_PASS
```

## Focused scratch mutations

Both mutations were made only in retained scratch copies of the final RTL.
Because XSim can exit zero after SystemVerilog `$fatal`, each gate required a
failure marker and absence of the GREEN marker.

```text
remove overmodulation normalization:
FATAL_PRESENT=True PASS_PRESENT=False
Fatal: SECTOR_SVPWM_TB_FAIL: bit-exact response mismatch id=0000000d

swap sector-1 U/V mapping:
FATAL_PRESENT=True PASS_PRESENT=False
Fatal: SECTOR_SVPWM_TB_FAIL: bit-exact response mismatch id=00000002
```

## Timing and debug contract

The top captures one request at N. It schedules both dividers in parallel for
acceptance at N+2, accepts their fixed result only at parent age 74, checks
`quotient * denominator + remainder == numerator`, pipelines rounded T1/T2,
L/M/H and phase narrowing, and responds at N+128. Missing, early, late,
divide-by-zero and invariant failures become fixed-slot `INTERNAL_ERROR`
responses.

The hierarchy-visible debug names checked by the TB are:

```text
a_num_debug b_num_debug sum_num_debug base_debug denominator_debug
t1_debug t2_debug l_debug m_debug h_debug
```
