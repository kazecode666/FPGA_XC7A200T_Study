# Step 6C1 Task 2 report — fixed-point package and Clarke RTL

Date: 2026-09-18

## Scope and result

Implemented only the shared fixed-point package, the pipelined Clarke transform, and its
self-checking unit test. No sin/cos LUT RTL, Park, inverse Park, integration top, Vivado
project, constraints, synthesis, implementation, bitstream, or Step 6C2 work was added.
Existing dirty `.xpr` and `.xlsx` files were preserved and are not part of the commit.

The tracked testbench was written first and an actual RED elaboration was run before the
DUT existed. The final test is bit-exact against every row in the Task 1 Clarke fixture.

## Implementation

- `motor_control_ip/foc/rtl/mc_fxp_pkg.sv` defines the frozen widths, fraction counts, and
  literal signed-18 constants `43691`, `37837`, and `65536`.
- Package helpers perform magnitude-based F31-to-integer rounding with ties away from zero,
  signed-25 saturation, combined rounding/saturation, and magnitude-based signed division
  by two. The signed-44 minimum is handled by sign-extending before magnitude conversion.
- `motor_control_ip/foc/rtl/mc_clarke.sv` uses an explicit signed-25 `sum_bc`, signed-25
  `alpha_pre`/`beta_pre`, signed-43 full-precision products, and two inference-friendly
  constant multiplications marked `use_dsp = "yes"`.
- Data registers update only when their corresponding valid stage is active. Active-low
  reset is asynchronously asserted and clears all valid stages and registered data outputs.
- The three registered operations are preadd, multiply, and round/saturate. An input sampled
  at edge N produces `output_valid` and its result immediately after edge N+2. The TB checks
  this edge-index contract automatically.

## RED evidence

The complete evidence is in `docs/reports/step6c1/tdd_clarke_red.txt`. A temporary ignored
package signature stub allowed compilation to reach the intended missing-DUT elaboration
failure; it is not tracked.

```text
E:\AMDDesignTools\2026.1\Vivado\bin\xvlog.bat -sv red_stub_pkg.sv ..\..\motor_control_ip\foc\tb\mc_clarke_tb.sv
E:\AMDDesignTools\2026.1\Vivado\bin\xelab.bat mc_clarke_tb -s mc_clarke_tb_sim
RED_XVLOG_EXIT=0
RED_XELAB_EXIT=1
ERROR: [VRFC 10-2063] Module <mc_clarke> not found while processing module instance <dut>
```

Result: expected RED passed because the failure was specifically the missing `mc_clarke`.

## GREEN command and exact gate

All simulation artifacts were created only under ignored `.Xil/step6c1_clarke`. Commands
were run there, with the repository's `motor_control_ip` visible at the default fixture path:

```text
E:\AMDDesignTools\2026.1\Vivado\bin\xvlog.bat -sv ..\..\motor_control_ip\foc\rtl\mc_fxp_pkg.sv ..\..\motor_control_ip\foc\rtl\mc_clarke.sv ..\..\motor_control_ip\foc\tb\mc_clarke_tb.sv
E:\AMDDesignTools\2026.1\Vivado\bin\xelab.bat mc_clarke_tb -s mc_clarke_tb_sim -debug typical
E:\AMDDesignTools\2026.1\Vivado\bin\xsim.bat mc_clarke_tb_sim --runall
```

The TB also accepts `+VECTOR_DIR=<path>` through `$value$plusargs`; without it, it reads
`motor_control_ip/foc/tb/vectors`.

The gate requires all three process exit codes to be zero, exactly one PASS marker, and no
`CLARKE_TB_FAIL` marker. This content gate is required because xsim can return zero after a
SystemVerilog fatal.

```text
GREEN_XVLOG_EXIT=0
GREEN_XELAB_EXIT=0
GREEN_XSIM_EXIT=0
PASS_COUNT=1
CLARKE_TB_FAIL_COUNT=0
ALL STEP 6C1 CLARKE TESTS PASSED rows=165 checked=175 latency_edges=2
```

A debug-only force of incorrect `i_alpha=1` verified the negative gate:

```text
FAULT_XSIM_EXIT=0
PASS_COUNT=0
CLARKE_TB_FAIL_COUNT=1
Fatal: CLARKE_TB_FAIL: transaction 0 mismatch got (1,0) expected (0,0)
```

## Coverage

The test reads and drives all 165 non-comment fixture rows: the five directed cases followed
by all 160 Step 6A-derived rows. It checks exact signed integer alpha/beta outputs, full-rate
back-to-back transactions, bubbles, reset asserted with two transactions in flight, recovery
after reset, transaction order, and fixed N-to-N+2 edge latency.

Direct helper checks cover positive and negative half-LSB ties and each adjacent raw count,
exact positive and negative multiples, signed-44 minimum magnitude, both signed-25 saturation
rails, even division, positive odd division, and negative odd division.

## Limits and follow-on work

Task 2 is simulation-only. DSP mapping, utilization, timing, and route evidence belong to the
later authorized Step 6C1 build task. The `use_dsp` attributes express inference intent; this
task does not claim a synthesized DSP48 count.
