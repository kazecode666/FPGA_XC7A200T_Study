# Step 6C3 fixed-point Sector-SVPWM execution report

## Result and provenance

The standalone Step 6C3 build passed on Vivado 2026.1 for
`xc7a200tfbg484-2`, top `mc_sector_svpwm`, with the exact 20.000 ns `sys_clk`
constraint. The reproducible final run is `final_c20fb05`; it tested source
commit `c20fb05a9805c13d484652720052cdd193070456` and ended with
`STEP6C3_BUILD_PASS`. The tracked XPR uses external repository sources, orders
the package first, and contains the three C3 testbenches and their fixtures.

The implementation captures signed S25/F15 `v_alpha`, `v_beta` and `vdc`,
evaluates the six-sector comparison and S40 XYZ/selected numerators, then runs
two unchanged accepted `mc_udiv_u72_u41` instances in parallel. Normalized
`t1/t2` and `L/M/H` are signed S34/F32; the three unclamped outputs are signed
S26/F24. Arithmetic is explicitly widened before multiply, add/subtract,
negate and narrowing checks, with signed nearest rounding and ties away from
zero.

The routed schedule registers the combinational Sector/XYZ result at N+1,
forms `SUM`, `BASE`, denominator and divider inputs at N+2, and the two
dividers accept at N+3. Their outputs update at N+75 and are captured by the
parent at N+76. Quotient reconstruction and T rounding occur at N+77, L/M/H at
N+78, and phase mapping/narrowing at N+79. The externally measured response
remains exactly N+128 for successful and error transactions. `input_ready` is
low while busy and on the completion edge; asynchronous reset aborts the
pending request.

## Numeric and protocol verification

The final full-top XSim run checked all 790 fixture rows bit-for-bit: 22
directed plus 768 deterministic seeded rows (`0x6c32026`). It reported 791
acceptances including one reset-abort probe, 790 responses at latency 128,
101120 poisoned busy cycles, 790 blocked completion edges and 789 immediately
following-edge acceptances. Package and Sector/XYZ tests passed independently;
the latter checked 790 rows and all 16 exposed fields.

The actual 160-row Step 6A replay contained 80 rows per profile. Its normalized
absolute-error maxima were:

| Quantity | Maximum | Gate |
|---|---:|---:|
| t1 | 0.000015665495423478064619140625 | 0.00005 |
| t2 | 0.000008176039042934234619140625 | 0.00005 |
| duty_u | 0.0000042531884765625 | 0.00005 |
| duty_v | 0.000011942187652587890625 | 0.00005 |
| duty_w | 0.000011942187652587890625 | 0.00005 |

The only sector differences were the four frozen comparison-boundary rows:

| Row | Profile | Case | A raw | B raw | Source | C3 |
|---:|---|---|---:|---:|---:|---:|
| 50 | real_commissioning | edge_1_1.732 | 71475 | 123795 | 3 | 1 |
| 62 | real_commissioning | edge_1_-1.732 | 71475 | -123795 | 2 | 6 |
| 130 | MIL_PI_override | edge_1_1.732 | 142950 | 247590 | 3 | 1 |
| 142 | MIL_PI_override | edge_1_-1.732 | 142950 | -247590 | 2 | 6 |

Three focused scratch mutations were detected by exact Fatal-present and
PASS-absent gates: changing the `cmp1 >= 0` equality predicate, removing
overmodulation normalization, and swapping the sector-1 U/V mapping. The
production source was restored before each final GREEN run.

## Compact regression and implementation evidence

All five required Python checks passed: the 14-test C3 unit suite, C3 fixture
and Step 6A comparison check, accepted C2 oracle check, accepted C1 reference
check, and the Step 6A source verifier (160 rows, 2926 checks, maximum source
error `5.46e-12`). All seven required XSim regressions passed with their exact
markers and no Fatal/Error text: the three C3 testbenches, C2 divider, C2
profile-0 core, C1 current transform and Step 6B motor PWM.

Post-route packed resources were 3893 Slice LUTs, 1501 FFs, 25 DSP48E1s and
0 BRAMs. Synthesis found 0 latches and 0 black boxes. Routing completed
5700/5700 routable nets with 0 routing errors. At 20.000 ns, routed setup was
WNS `+1.935 ns`, TNS `0.000 ns`, 0/2903 failing endpoints; hold was WHS
`+0.054 ns`, THS `0.000 ns`, 0/2903 failing endpoints. Timing checks found no
unclocked internal endpoints, combinational loops or latch loops.

The first build attempt failed closed on an incorrectly quoted Windows XSim
vector argument. After that one-line script fix, all compact regressions
passed, but the initial route failed setup timing at WNS `-2.944 ns`, TNS
`-369.112 ns`, 139 failing endpoints; hold passed at WHS `+0.116 ns`. Its
worst path ran from `captured_alpha_reg[5]/C` to
`divider_a_numerator_reg[65]/CE`, through the combined Sector/XYZ and divider
preparation path. Registering Sector/XYZ in one unused internal slot produced
the passing final timing above without changing formats, rounding, accepted
divider RTL, interfaces or N+128 latency. Both failed build records remain in
the evidence tree.

## Warnings and limits

Synthesis retained six warnings: two `!==` operators synthesized as `!=`, one
accepted-divider unused high remainder bit trimmed, and three hierarchy-visible
but functionally unused `sum/base/denominator` debug registers removed. The
post-route DRC retained NSTD-1 and UCIO-1 for all 164 logical ports, CFGBVS-1,
and DSP input/output pipeline recommendations DPIP-1, DPOP-1 and DPOP-2. The
DSP recommendations are performance advice; routed timing passed with positive
setup and hold slack.

This is internal-core 50 MHz evidence. The project deliberately has only the
clock constraint, so it has no board pin, IOSTANDARD or external I/O-delay
constraints. No bitstream was generated, no physical hardware was exercised,
and no C4 or Step 6D work was performed.

Final evidence is under `docs/reports/step6c3/final_c20fb05/`, including both
synthesis and routed timing summaries, utilization/hierarchy, route status,
clock/timing checks, DRC/methodology, warnings and complete compact-regression
logs.
