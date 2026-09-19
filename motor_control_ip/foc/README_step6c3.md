# Step 6C3 fixed-point Sector-SVPWM

`mc_sector_svpwm` is the learning-stage, fixed-point Sector-SVPWM core for the
accepted Step 6A algorithm. It accepts signed S25/F15 `v_alpha`, `v_beta` and
`vdc`; it returns signed S26/F24 `duty_u`, `duty_v` and `duty_w`. Internal
normalized dwell values `t1` and `t2` use S34/F32. The implementation preserves
the audited six-sector XYZ decision and intentionally does not clamp duty.

One request may be in flight. A request accepted on edge N completes on edge
N+128, including invalid-VDC and internal error responses. `input_ready` is low
while busy and on the completion edge, so the earliest next request is the
following edge. Asynchronous active-low reset aborts an in-flight request.

The standalone `FOC_SVPWM/FOC_SVPWM.xpr` targets `xc7a200tfbg484-2`, keeps the
RTL and fixtures as external repository sources, places `mc_svpwm_pkg.sv` first,
and applies exactly one 20.000 ns `sys_clk` constraint. The project includes the
three C3 testbenches; its synthesis top is `mc_sector_svpwm` and its simulation
top is `mc_sector_svpwm_tb`.

Run the complete compact acceptance from the repository root with the selected
Vivado 2026.1 launcher and a fresh label:

```powershell
& "E:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" -mode batch -nojournal -nolog `
  -source scripts\step6c3_svpwm_build.tcl -tclargs final_LABEL
```

The launcher identifies its own installation and the Tcl script resolves the
sibling `xvlog`, `xelab` and `xsim` executables from it. A passing run writes a
new `docs/reports/step6c3/<label>/` evidence directory and ends with
`STEP6C3_BUILD_PASS`. The script gates five Python checks, all three C3
testbenches, the accepted C2 divider and profile-0 core regressions, the C1
current-transform regression and the Step 6B motor-PWM regression. Every XSim
run requires its exact PASS marker and rejects Fatal/Error text because XSim can
exit zero after an HDL `$fatal`.

The build then synthesizes and routes a fresh project with default Vivado
strategies. It retains synthesis and routed timing summaries, packed resource
reports, primitive and hierarchy evidence, route completeness, timing checks,
DRC/methodology findings and warning categories. Acceptance requires complete
routing, nonnegative setup and hold slack/totals, no latch, black box,
unresolved module or internal combinational loop, and no non-board blocking
DRC. UCIO/NSTD/CFGBVS findings are retained because this portable core project
contains only a clock constraint and no board pin, IOSTANDARD or external I/O
delay constraints.

The result is internal core timing evidence at 50 MHz. The flow does not create
a bitstream and does not validate board I/O timing, physical hardware, C4 or
Step 6D.
