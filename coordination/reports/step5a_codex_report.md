# Step 5A - BX72 LED1 blink

## Audit gate (2026-09-16)

Step 4 PR #5 was verified merged at 2026-09-16T04:19:43Z. Updated local main to `90eb126`; branch `step5a-bx72-led-blink` starts there. No RTL/XDC change was made before this audit. No Computer Use or file-hash verification is used.

| Item | Audited fact | Repository evidence |
|---|---|---|
| Device/package | `XC7A200T-2FBG484I` is one supported population; matches project `xc7a200tfbg484-2` | `BX72-251215.pdf` p1 U1D/U1E/U1G lists 35T/50T/100T/200T and package compatibility; current XPR part. Documents describe board variants, not proof of the fitted chip on a particular physical board. |
| Vendor variant | Vendor XPR selects `xc7a100tfgg484-2`; do not copy its device or bitstream | `BX72_test.zip/BX72_test.xpr`, Configuration/Part. A supported variant per schematic p1; relevant pins/voltage agree, not a conflicting pin assignment. User must confirm A200T through JTAG before programming. |
| Oscillator | U4 `50M_active`, OUT pin 3 through R9 33 ohm to `FPGA_CLK` | Schematic p1 bottom center; U4 supplied from VCCIO14 via FB1. Vendor `io.xdc` line 299 creates 20 ns clock. |
| Clock pin | Y18, Bank 14, `IO_L13P_T2_MRCC_14`, LVCMOS33 | Schematic p1 U1D; spreadsheet `Sheet1!B1:C1`; vendor `io.xdc` lines 7-8. |
| LED1 pin | AA18, Bank 14, LVCMOS33 | Schematic p1 U1D; spreadsheet `Sheet1!B8:C8`; vendor `io.xdc` lines 83,160. LED0/Y19 is a different LED. |
| LED1 polarity | HIGH lights D7: LED1 -> R74 1 kohm -> D7 anode, cathode -> GND | Schematic p7 lower right. Direct mapping `led1 = pwm_core_out`; reset makes LED OFF. |
| KEY2 pin | V17, Bank 14, LVCMOS33 | Schematic p1 U1D; spreadsheet `Sheet1!B3:C3`; vendor `io.xdc` lines 80-81 (`Rst_n`). |
| KEY2 polarity | Active LOW; R71 4.7 kohm pulls up to VCCIO14; S2 closes to GND; D4 BAT54S rail clamps | Schematic p7 lower left/center. No extra FPGA pull-up required. |
| Bank voltage | VCCO14 = VCCIO14 = 3.3 V; all three signals justify LVCMOS33 | Schematic p4 U1F VCCO14 pins and FB20 connecting VCC3P3 to VCCIO14; matches vendor XDC for all three signals. |
| Configuration voltage | Bank 0 F12/T12 supplied VCC3P3; U8 CFGBVS tied to VCC3P3 | Schematic p4 U1F/U1E; justifies `CFGBVS VCCO`, `CONFIG_VOLTAGE 3.3`. |
| Physical identification | LED1 = D7, KEY2 = S2 | Assembly drawing p1/top: D7 on left edge beside upper of the two lower-left buttons; D6/LED0 immediately below. KEY2/S2 at upper left beside MIPI DSI. U4 above FPGA U1. |
| Functional notes | LED0 is DDR initialization indicator, LED1 is user LED controlled by KEY0/1 in vendor demo, KEY2 resets | `BX72用户测试说明.txt`, line 6. Describes vendor behavior only; Step 5A implements LED1 blink. |

Audit result: PASS for the three Step 5A board connections. Original PDF pages 1,4,7 and assembly top page were rendered and visually traced, alongside workbook cells and vendor source/constraints. No conflicting pin or voltage was found for these signals. Other vendor interfaces are outside this three-port experiment and are not imported.

## Execution

Branch: `step5a-bx72-led-blink`. Implementation commit and PR URL are recorded in the submission section below after publication. PR must remain open for ChatGPT review.

### Files and architecture

- Added `PWM_Controller/PWM_Controller.srcs/sources_1/new/pwm_demo_top.sv`: only `clk`, `key2_n`, `led1` are board-facing; the 64 configuration bits are internal constants.
- Added `PWM_Controller/PWM_Controller.srcs/sim_1/new/pwm_demo_top_tb.sv` with reduced parameters 8/4.
- Added `PWM_Controller/PWM_Controller.srcs/constrs_1/new/bx72_step5a.xdc`, in separate fileset `constrs_step5a`. Step 4 `pwm_timing.xdc` is untouched and not used by Step 5A runs.
- Updated `PWM_Controller/PWM_Controller.xpr`: design top `pwm_demo_top`, default simulation top `pwm_demo_top_tb`, current runs `step5a_synth` / `step5a_impl`. The original core TB remains in `sim_1` and the script explicitly selects/runs it first; Vivado's AutoDisabled flag for the non-selected TB is normal compile-order metadata.
- Added `scripts/step5a_bx72_build.tcl`, this report, and actual tool reports in `docs/reports/step5a/`; updated README's previously obsolete project status.
- Original `pwm_control.sv` and `pwm_controller_tb.sv` are unchanged. Old `synth_1` / `impl_1` results were not reset; use the new Step 5A runs, not those historical results.

The hierarchy is `KEY2 -> reset_release[1:0] -> internal reset_n -> one-shot configuration + u_pwm -> LED1`. Both release flops asynchronously clear on KEY2 LOW. Release shifts HIGH through two clock edges. `ASYNC_REG=TRUE` and `SHREG_EXTRACT=NO` identify the synchronizer, and both flops have FPGA INIT=0 so startup also works without a button press. The core's reset logic is unchanged.

`configured` clears with internal reset. `config_en = reset_n && !configured` is HIGH for exactly one full clock interval after the second release edge. On the third edge, the core latches `50_000_000 / 25_000_000` while `configured` sets, ending the pulse. The core starts at counter zero, LED OFF; then it runs freely with 0.5 s OFF / 0.5 s ON, 1 s total period. Pressing KEY2 turns it OFF asynchronously; release restarts that sequence. Mechanical bounce can extend/repeat reset until the button settles; there is no button debouncer or breathing-LED logic.

The only false path is external asynchronous KEY2 to the two synchronizer CLR pins. It does not mask internal reset recovery/removal paths or the two-stage data path. `board_properties.txt` checks actual mapped flops and exception endpoints; `cdc.rpt` reports one safe asynchronous reset crossing, zero unsafe/unknown/no-ASYNC_REG endpoints.

### Actual verification (Vivado 2026.1, 2026-09-16)

| Check | Result / evidence in `docs/reports/step5a/` |
|---|---|
| Core regression | PASS: all 8 functional cases and 4 counter/output-alignment cases; finished at 5460 ns (`pwm_controller_tb.txt`) |
| Board TB | PASS: power-on with KEY2 initially released, exactly two-edge synchronized release, one sampled config pulse, 4 complete 8-cycle periods per startup/restart, direct active-high LED mapping, asynchronous reset while LED ON, held reset and deterministic restart; finished at 1531 ns (`pwm_demo_top_tb.txt`) |
| Synthesis | `synth_design Complete!`; 67 LUTs, 37 FFs, 16 CARRY4, 1 BUFG, 2 IBUF, 1 OBUF; no latches/BRAM/DSP (`synthesis_utilization.rpt`) |
| Implementation | `route_design Complete!`; 90/90 routable nets fully routed, 0 routing errors; same LUT/FF totals (`route_status.rpt`, `implementation_utilization.rpt`) |
| Clock | Single `sys_clk`, 20.000 ns / 50.000 MHz (`timing_summary.rpt`) |
| Timing | WNS **14.682 ns**, TNS **0.000 ns**, WHS **0.130 ns**, THS **0.000 ns**; 0 failing setup/hold endpoints of 70 checked each, including reset checks. WPWS 9.500 ns, TPWS 0.000 ns |
| Internal constraint coverage | `no_clock=0`, `unconstrained_internal_endpoints=0`; no combinational/latch loops |
| Board ports | clk=Y18, key2_n=V17, led1=AA18; all fixed, Bank 14 / LVCMOS33 (`io.rpt`, `board_properties.txt`) |
| DRC | **0 checks/violations** in routed default DRC. NSTD-1/UCIO-1/CFGBVS-1 absent through real constraints; no severity override. Bitgen's own DRC also reports 0 errors |
| Bitstream | **Yes**; `write_bitstream Complete!`, `STEP5A_BUILD_PASS`, exit code 0 (`build_result.txt`) |
| Physical hardware | **NOT TESTED; physical PASS still awaits the user's observation** |

The smaller resource count than Step 4 is expected: the board wrapper supplies fixed values so synthesis optimizes constant configuration logic. This is not a change in the frozen PWM core semantics.

Exact local bitstream path:

`D:/Project/FPGA_XC7A200T/PWM_Controller/PWM_Controller.runs/step5a_impl/pwm_demo_top.bit`

File exists, 9,730,856 bytes, written 2026-09-16 12:31:03 local time. The generated runs/bitstream are ignored and not committed; reproduce them with the build script. No file hashes were calculated.

### Remaining warnings and limits

1. `TIMING-18` (one methodology warning): LED1 has no output delay. An LED has no external sampling clock. KEY2 is an asynchronous human input; its input delay is intentionally absent and its reset entry path is excepted narrowly. These are control GPIO, not a synchronous external data bus. No arbitrary `set_input_delay` / `set_output_delay` is added. Internal synchronous and synchronized-reset timing passes; this is not external-bus timing sign-off.
2. `XDCB-5` (one methodology warning): the small hierarchical query selecting the two reset CLR pins is flagged as runtime-inefficient. It matches exactly two intended pins and has no functional or timing-coverage error; it is not suppressed. See `exceptions.rpt` and `board_properties.txt`.
3. Outer batch has one `Project 1-5713` empty BoardPart warning. This is a part-based project with explicit audited pin constraints, not a Vivado board-preset project. Device remains `xc7a200tfbg484-2`.
4. Final synthesis and implementation/bitgen run logs each contain 0 ERROR, 0 CRITICAL WARNING, 0 WARNING lines. These log counts are distinct from the two methodology report findings above (`messages.txt`).
5. Initial setup encountered a transient XPR write error before simulation, and then an invalid `Default` strategy name. After correcting the strategy to `Vivado Implementation Defaults`, the full run completed successfully; no bitstream was produced by either failed attempt. These are retained in the execution narrative, not presented as final successful-run errors.

There is no unresolved build blocker. Documented board variants do not establish the fitted device on the user's physical board: confirm `xc7a200t` in Hardware Manager before programming. No JTAG programming was performed.

### Reproduce

From the repository root in PowerShell:

```powershell
& 'E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat' -mode batch -nojournal -log step5a_build.log -source scripts/step5a_bx72_build.tcl
```

The script selects each TB, requires its PASS marker, runs Step 5A synthesis and implementation, verifies actual pins/clock, checks internal max/min timing and blocking DRCs, then generates bitstream. It does not program the board. Local pre-existing XPR run-directory/job-count metadata was backed up and preserved separately from the committed source configuration; the pre-existing Excel owner-lock file was not touched or staged.

### Manual hardware verification (no oscilloscope required)

1. With BX72 powered off, keep external motor/power-stage/ADC/adapter boards disconnected for this experiment. Use the BX72's intended supply and connector, checking the actual board's supply markings. Power only BX72.
2. Connect the board's JTAG interface to the computer.
3. Open `PWM_Controller/PWM_Controller.xpr`. Confirm Design Top `pwm_demo_top` and active implementation `step5a_impl`; open Hardware Manager -> Open Target -> Auto Connect.
4. Confirm the detected device is `xc7a200t`. If the physical part differs, stop and report it; do not use the vendor A100T bitstream. Select Program Device and use the exact `pwm_demo_top.bit` path above. No flash programming is required.
5. Locate **LED1 = D7**, not DDR indicator LED0/D6. With the assembly p1 orientation (P1 at top, P2 at bottom), D7 is on the left edge near the upper of the two lower-left buttons, with D6 directly below. **KEY2 = S2** is at the upper left beside MIPI DSI.
6. Observe LED1: approximately 0.5 s OFF, 0.5 s ON, repeating once per second. Record success/failure; do not infer it solely from successful programming.
7. Hold KEY2: LED1 must stay OFF. Release it: after synchronization/configuration, expect 0.5 s OFF then 0.5 s ON repeatedly; allow mechanical contacts to settle.
8. Report detected FPGA, programming result, LED1 behavior, and KEY2 restart behavior back to ChatGPT. **Physical hardware PASS remains pending this observation.**

## Submission

Implementation commit: pending publication.

PR URL: pending publication.

Stop at the open Step 5A PR for review. **Step 5B has not been implemented or started.**
