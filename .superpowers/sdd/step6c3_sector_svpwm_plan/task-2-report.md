# Task 2 report: SVPWM package and Sector/XYZ RTL

## Scope and commits

- Base commit: `0ca48c060b576b4dd632ffd50339448c7aa364be`
- Task 2 implementation commit: `db386042d400e031c5b341ec3982756e58ece3fe`
- Branch: `step6c3-sector-svpwm`
- Simulator: Vivado Simulator 2026.1, SW build 6511674
- Completed scope: package helpers, combinational Sector/XYZ RTL, and their two
  testbenches only.

No accepted C1/C2/PWM source, Task 1 oracle or fixture, specification, task
book, plan, handoff, top SVPWM module, synthesis project, bitstream or hardware
operation was changed or created.

## TDD evidence

Both TBs existed before the RTL. The package compile exited 1 with:

```text
ERROR: [VRFC 10-2989] 'mc_svpwm_pkg' is not declared
```

The Sector/XYZ TB compiled and its elaboration exited 1 with:

```text
ERROR: [VRFC 10-2063] Module <mc_svpwm_sector_xyz> not found while processing module instance <dut>
ERROR: [XSIM 43-3322] Static elaboration of top level Verilog design unit(s) in library work failed.
```

After implementation, a fresh combined three-step run compiled all four files,
elaborated both tops and simulated both snapshots. It exited 0 with:

```text
ALL STEP 6C3 SVPWM PKG TESTS PASSED
ALL STEP 6C3 SECTOR XYZ TESTS PASSED rows=790 fields=16 directed=22 seeded=768
```

The actual commands and output excerpts are retained in
`docs/reports/step6c3/sector_xyz/task2_evidence.md`. Ignored XSim work/log
directories remain under this task scratch directory.

## Package helper contract

`mc_svpwm_pkg.sv` defines the fixed formats and exact integer coefficients used
by C3. It exposes:

```text
svpwm_round_shift_s96(value:S96, shift:0..95) -> S96
svpwm_fits_s40(value:S96) -> bit
svpwm_fits_s34(value:S96) -> bit
svpwm_fits_s26(value:S96) -> bit
```

The rounding helper performs signed nearest rounding with exact ties away from
zero. It explicitly widens before absolute value, so the S96 negative rail is
defined. An invalid shift greater than 95 returns X. The TB verifies positive
and negative ties, negative odd values, below/above-half values, shift zero,
both S96 rails, and exact S40/S34/S26 rails plus their outside neighbors.

## Sector/XYZ module interface and timing

`mc_svpwm_sector_xyz` is a pure combinational module with no clock, reset,
valid/ready handshake, local storage or cycle latency. Task 3 owns capture and
the fixed N+128 transaction schedule. Task 3 should drive this stage from the
captured transaction's `v_alpha/v_beta`, then consume the settled outputs.

Inputs:

```text
v_alpha signed [24:0]  S25/F15
v_beta  signed [24:0]  S25/F15
```

Outputs:

```text
cmp0 signed [24:0]
cmp1 signed [35:0]
cmp2 signed [35:0]
b0, b1, b2
sector [2:0]
x_num, y_num, z_num signed [39:0]
a_num, b_num signed [39:0]
xyz_range_ok
```

The exact predicate is preserved: `b0=(B>0)`, `b1=(cmp1>=0)`,
`b2=(cmp2>0)`. Every input is sign-extended before multiply; arithmetic is
widened before add/subtract and negate. XYZ and selected dwell values are
computed in S41, checked against the S40 rails, then stored as S40. If the
range/legal-sector check fails, `xyz_range_ok=0` and the five S40 outputs are
zero instead of wrapped. There is no clamp.

The independent whole-domain bounds supplied during review are:

```text
|X| <= 290598158336
|Y|, |Z| <= 396948930560
S40 maximum = 549755813887
|cmp1|, |cmp2| <= 11458838528, within S36
```

## Fixture and directed coverage

The fixture parser uses indexed-byte tokenization before one numeric conversion
per token. It avoids XSim 2026.1's unsafe missing multi-string `sscanf` path.
It requires the exact header, exactly 16 fields per row, exactly 790 rows,
canonical IDs/tags, lowercase fixed-width hex and no blank rows. It then
bit-compares every exposed result with the independent oracle fixture.

Observed coverage is 22 directed plus 768 seeded rows. Directed tags prove:

- zero vector gives sector 2;
- one interior vector for each sector 1 through 6;
- cmp1 and cmp2 each hit -1, 0 and +1;
- `A=25000` with `B=43299/43300/43301` preserves the equality tie;
- all X/Y/Z and selected a/b values match the fixture bit-for-bit.

A fresh fixture regeneration check reported:

```text
STEP6C3_REFERENCE_CHECK_PASS
fixtures: 22 directed + 768 seeded = 790
```

## Focused mutation

Only a disposable scratch copy changed `b1 = (cmp1_w >= 0)` to
`b1 = (cmp1_w > 0)`. It compiled and elaborated, then the first equality
boundary failed at 1 ns:

```text
Fatal: SVPWM_SECTOR_XYZ_TB_FAIL: zero vector cmp1=0 sector=0 range_ok=0 expected=0/2/1
```

Because XSim returns zero after this HDL `$fatal`, a log marker gate required
the Fatal and absence of the GREEN marker. The marker gate exited 1 with:

```text
TASK2_MUTATION_DETECTED boundary Fatal present; PASS marker absent
```

The production RTL was never mutated and the final fresh GREEN was run after
the scratch experiment.

## Final checks

```text
git diff --check
exit 0

python scripts/step6c3_svpwm_reference.py --check
exit 0
STEP6C3_REFERENCE_CHECK_PASS
```

Task 2 is ready for scoped review. Task 3 can consume the package and module
contracts above without changing the Task 2 interface.
