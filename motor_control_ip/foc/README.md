# Step 6C1 fixed-point FOC transforms

Portable, inferred SystemVerilog for Clarke, LUT sine/cosine, Park, inverse Park,
and the coherent current-transform pipeline. Open
`../../FOC_Transforms/FOC_Transforms.xpr` in Vivado 2026.1. The synthesis top is
`mc_current_transform`, part `xc7a200tfbg484-2`; the default simulation top is
`mc_current_transform_tb`. The XPR references six RTL files, four testbenches and
one ROM externally. Keep the repository directory structure when moving it.
The package `mc_fxp_pkg.sv` compiles first. Only a 20 ns `sys_clk` constraint is
provided; there are no board pin, I/O standard, or input/output delay constraints.

## Integer formats and transform contract

All signed values use two's complement. F15/F16 give the number of fractional
bits, independent of total width.

| Value | Width / format | Physical value / range |
|---|---|---|
| Phase currents `ia,ib,ic` | signed 24 F15 | raw / 32768 A; -256 through 255.999969482421875 A |
| Transform currents / voltages | signed 25 F15 | raw / 32768 A or V; -512 through 511.999969482421875 |
| Coefficients, sine, cosine | signed 18 F16 | raw / 65536; -2 through 1.9999847412109375 |
| `theta_e` | unsigned 16-bit binary angle | raw * 2*pi / 65536 radians, modulo one revolution |

The literal signed-18 constants are `C_TWO_THIRDS=43691`,
`C_INV_SQRT3=37837`, and `SIN_COS_ONE=65536`. There is no additional per-unit
normalization. For example, current raw 32768 is 1 A, coefficient raw 65536 is
1.0, and voltage raw 32768 is 1 V.

Clarke implements alpha = (2/3)*(ia - (ib+ic)/2), beta = (ib-ic)/sqrt(3),
using the quantized constants above. The raw `(ib+ic)/2` preadd rounds odd
positive and negative ties away from zero. Park computes
`id=alpha*cos+beta*sin`, `iq=beta*cos-alpha*sin`; inverse Park computes
`v_alpha=vd*cos-vq*sin`, `v_beta=vd*sin+vq*cos`.

Products retain all 43 signed F31 bits; Park sums/differences sign-extend into
44 bits before accumulation. F31-to-F15 conversion rounds the magnitude with
`(abs(value)+32768)>>16`, restores the sign, then saturates to signed 25-bit
rails [-16777216,16777215]. Thus exact ties round away from zero, negative
exact multiples stay exact, and overflow clips instead of wrapping.

## Angle and quarter-wave ROM

Angle examples: `0000` = 0 degrees, `4000` = 90 degrees, `8000` = 180 degrees,
`C000` = 270 degrees, and `FFFF` is just below 360 degrees. `theta_e[15:14]`
selects the quadrant, `theta_e[13:2]` selects q=0..4095, and the low two bits
are discarded. The ROM contains
`round(65536*sin(pi*q/8192))`, stored as 4096 five-hex-digit words in
`rom/sin_qw_4096x18.mem`. Several final entries round to 65536.

Let S=LUT[q] and C=LUT[4096-q] for q>0; at q=0, C is exactly 65536 rather
than an out-of-range ROM read. Quadrants reconstruct (sin,cos) as (S,C),
(C,-S), (-S,-C), and (-C,S). The single ROM array has two synchronous read
ports. LUT plus inferred DSP arithmetic was deliberately selected instead of
CORDIC; no DSP48E1 or RAMB primitive is instantiated.

## Valid, reset and measured latency

Inputs are accepted on rising edge N when `input_valid=1`. There is no ready
signal or backpressure; every clock can accept a transaction. Output fields
are meaningful when `output_valid=1`, with all debug fields aligned to that
same transaction. Invalid cycles insert bubbles; stage data holds until its
valid enable. Active-low asynchronous reset flushes valid state and resets
visible output data. Internal ROM read-data registers intentionally have no
asynchronous reset for memory inference; reset valid state masks those values.

The self-checking RTL scoreboards measured these edge intervals:

| Module | Output edge | Latency at 50 MHz |
|---|---|---|
| Clarke | N+2 | 40 ns |
| sin/cos LUT | N+1 | 20 ns |
| Park / inverse Park, standalone | N+2 | 40 ns |
| Current transform | N+5 | 100 ns |

These are acceptance-to-output rising-edge intervals, not counts of register
stages. Every module sustains one transaction per clock. In the current top,
sin/cos receives one alignment register, Park accepts the matched Clarke and
sin/cos tuple at N+3, and three debug registers align alpha/beta/sin/cos with
id/iq at N+5. The standalone Park-to-inverse-Park test cascade also measures N+5.

## Simulation and reference checks

From the repository root, run `python scripts/step6c1_fixed_transform_reference.py --check`.
It compares the checked-in ROM and decimal fixtures against deterministic
regeneration and validates rounding, saturation and algorithm error bounds.

The four simulation tops are `mc_clarke_tb`, `mc_sincos_lut_tb`, `mc_park_tb`,
and `mc_current_transform_tb`. In Vivado, select a top on `sim_1`, then launch
behavioral simulation and run all. The testbenches accept `+VECTOR_DIR=<path>`;
do not save an absolute fixture path into the portable XPR. The robust Windows
alternative is to copy fixture text files from `tb/vectors/` into the generated
simulation working directory at `motor_control_ip/foc/tb/vectors/` before
launch, for example beneath `FOC_Transforms/FOC_Transforms.sim/sim_1/behav/xsim/`.
These are disposable runtime copies, not project-local source duplicates.
The ROM is registered as a Memory Initialization File, enabled for both
simulation and synthesis, so Vivado stages its required basename
`sin_qw_4096x18.mem`. A direct xvlog/xelab/xsim invocation must copy that ROM
basename into its working directory itself and compile the package first.

Prior RTL test results: Clarke 165 fixture rows, sin/cos all 65536 phases,
Park 1141 and inverse Park 1143 fixtures, and 1000 independent unsaturated
Park/inverse-Park round trips (maximum 5 raw F15 LSB). The current-transform
scoreboard passed all 256 rows, including 96 continuous distinct transactions,
valid gaps, and four reset-flushed pending transactions. Require the appropriate
`ALL STEP 6C1 ... TESTS PASSED` marker and no fatal/error marker; simulator exit
status alone is insufficient. Park and current-transform GREEN logs are in
`../../docs/reports/step6c1/`.

The all-angle LUT maximum absolute error versus ideal sine/cosine is
0.000295057788. Over 160 Step 6A rows, maximum absolute current differences
from Step 6A are alpha 0.000012207031 A, beta 0.0000135940039 A,
id 0.0000135940039 A, and iq 0.0000217200291 A. Step 6A's 800-interval
Simulink lookup is an algorithm comparison; the quantized Python fixtures are
the bit-exact RTL target. Saturating cases are checked separately from the
unsaturated round-trip error bound.

## Build scope and evidence

Project creation and read-only relocation checks are recorded in
`../../docs/reports/step6c1/project_portability.txt`. Reproduce the full automated
regression and route build from the repository root:

```powershell
& E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat -mode batch -nojournal -log .Xil/step6c1_build.log -source scripts/step6c1_foc_transforms_build.tcl
```

The build audits the portable XPR XML and clock constraint, runs both Python
checks, rejects optimized Python (which would disable acceptance assertions),
runs all four FOC testbenches and the unchanged Step 6B PWM testbench, then
synthesizes and routes `mc_current_transform`. Unique generated scratch projects
and runs under `.Xil` preserve the tracked projects and prior run directories.
`build_result.txt` starts IN_PROGRESS and only reports `STEP6C1_BUILD_PASS` after
all gates pass; a Tcl failure writes FAILED. An externally killed or native-crash
process can leave IN_PROGRESS, which is never a successful build.

Measured Vivado 2026.1 results at 50 MHz:

| Measure | Synthesis | Routed |
|---|---:|---:|
| Slice LUTs | 735 | 732 |
| Flip-flops | 580 | 580 |
| DSP48E1 | 6 | 6 |
| RAMB36E1 / RAMB18E1 | 2 / 0 | 2 / 0 |
| Latches | 0 | 0 |

The two Clarke and four Park products account for all six DSPs. Two initialized
RAMB36E1 primitives implement the quarter-wave ROM; no mapping deviation was
observed. The synthesis audit also lists 888 logical LUT primitives, before
packing into the Slice LUT totals above.

Routed internal timing: WNS **10.548 ns**, TNS **0 ns**, WHS **0.118 ns**, THS
**0 ns**. The raw worst-path properties and real endpoints are preserved in
`worst_paths.txt`; there are no internal unconstrained endpoints, missing clocks,
combinational loops or latch loops. All 1455 routable nets are fully routed.
Resource hierarchy, initialized ROM properties, timing, DRC, methodology and
warning reports are under `../../docs/reports/step6c1/`.

The clock-only build intentionally retains 88 input ports and 137 output ports
without I/O delays, UCIO-1/NSTD-1/CFGBVS-1 board-constraint findings, and DSP
pipelining advisories (DPIP-1/DPOP-2). Synthesis warns that the two intentionally
discarded angle LSBs have no load. These findings are recorded without suppressing
or downgrading them. This is internal core timing evidence, not board timing
sign-off. No bitstream or hardware test was performed. PI, SVPWM, ADC and PWM
integration are outside Step 6C1.
