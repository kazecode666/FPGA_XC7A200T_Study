# Step 7B reproduction

Use **MATLAB R2026b Prerelease Update 3** and the existing Vivado 2026.1 installation. Run from this repository; no installation or global PATH change is needed.

```matlab
cd('D:/Project/FPGA_XC7A200T');
addpath(fullfile(pwd,'scripts'));
```

The SLX files are committed. XSI DLLs and Vivado caches are intentionally local. On a fresh checkout, generate the two runtimes first:

```matlab
step7b_generate_minimal_cosim;
step7b_generate_foc_cosim;
```

The full generator sets `pi_reset` as a data input after the prerelease wizard's name-based reset inference, including the matching positional signal descriptor. It preserves the original RTL. The [MathWorks configuration API](https://www.mathworks.com/help/hdlverifier/ref/cosimulationconfiguration.html) accepts an HDL filename list; the generator supplies the current repository's explicit dependencies.

Do **not** run `step7b_integrate_simple_cosim` on the committed integrated model: it intentionally refuses an existing FPGA branch. That script records the one-time baseline-to-integrated edit. `step7b_refresh_foc_block` refreshes only the XSI mask from a regenerated local block when necessary.

Run individual checks with all models closed:

```matlab
step7b_run_cosim('minimal'); % six actual HDL exchanges, including 255 -> 0
step7b_run_cosim('foc');     % original Simple model, parallel fixed smoke
step7b_run_cosim('timing');  % three fresh runs, temporary A/B sources, never saved
step7b_run_cosim('legacy');  % original solver, FPGA run_enable = 0
step7b_acceptance;          % all ten acceptance stages in the mandated order
```

To open and press **Run** interactively:

```matlab
step7b_open_cosim('minimal');
% Close the minimal model, then:
step7b_open_cosim('foc');
```

The helper selects the local `xsim.dir` working directory, adjusts only the current MATLAB process PATH, and opens the native model. For FOC it sets a temporary 200 us stop time; do not save this override over the original stop time. `FPGA_Cosim_Input_Mode=0` is the accepted smoke mode. Mode 1 only prepares live inputs for future work and is not a validated dynamic motor loop.

Monitor columns in `fpga_monitor`: active CMP U/V/W, accepted ID, active ID, valid, needs-reset, fault, monitor duties U/V/W, then 11 input range flags. Range flags are logged per sample; all are zero in the accepted smoke and timing runs. The FPGA subsystem has **no output ports** and cannot drive the plant. The existing `Control_Task_10kHz` remains connected to `Inverter_DeadTime`.

Timing is frozen at 50 us communication, 20 ns HDL clock, 200 ns reset, zero prerun, physical 1:1 time. The 50 us B update feeds accepted ID 1; it is observed at 100 us and active ID 1 at 150 us. The first peak is slightly after 50 us because of reset; this is not a claim about exactly coincident-edge scheduler ordering. Changing reset/prerun/rates requires repeating the timing test.

Vivado 2026.1 produces a MathWorks "not fully tested" warning (local recommendation: 2025.1.1); the recorded tests establish actual operation on this machine, not general vendor certification. MATLAB is a time-limited prerelease. The wizard's preliminary interface query can warn about ROM lookup after recreating its simulation directory; final XSI runs stage the unchanged ROM in the actual runtime directory and explicitly reject missing-ROM warnings. No dynamic plant takeover, hardware validation, synthesis/route, bitstream, Vitis migration or Step 7C is included.
