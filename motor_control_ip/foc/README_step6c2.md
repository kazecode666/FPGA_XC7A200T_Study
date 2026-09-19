# Step 6C2 dq PI and circular limiter

This reusable transaction core implements the frozen `coordination/specs/step6c2_pi_dq_limiter.md` integer/state contract. It has no PWM, pin, ADC, encoder, host-bus or board wrapper. C1 transforms and the accepted PWM remain independent.

## Formats and transactions

Current and external voltage are signed 25-bit F15; electrical speed is signed 32-bit F16. Integrators, raw voltages and delayed anti-windup corrections are signed 40-bit F24. `PI_PROFILE=0` is `real_commissioning`; `PI_PROFILE=1` is `MIL_PI_override`. The package owns the frozen integer coefficients and ties-away-from-zero rounding.

Accept only on a rising edge with `input_valid && input_ready`. The core captures the complete transaction, uses OLD state and delayed OLD anti-windup, and atomically commits state at the response. Core completion is exactly 256 edges after acceptance for success and error. Evaluator/sqrt/divider/limiter slots are 16/40/72/160 edges. Completion cannot accept another transaction; the following rising edge is the earliest next acceptance. Holding valid while busy does not create extra samples. Functional outputs hold between responses.

Asynchronous active-low reset clears state and outputs and aborts pending work. `pi_reset` and `uq_zero_en` obey the frozen command-reset ordering. Errors retain all persistent state and report zero functional outputs; OLD/NEXT debug snapshots make this behavior inspectable. Debug is hierarchy only, with no extra production ports or KEEP attributes.

## Portable Vivado project

Open `FOC_PI/FOC_PI.xpr` with its sibling `motor_control_ip` source tree. The project references exactly the six external C2 RTL sources, package first, the six C2 testbench files and nine external text fixtures. No RTL or testbench is duplicated inside the project. The synthesis top is `mc_pi_dq_core` with `PI_PROFILE=0`; the default simulation top is `mc_pi_dq_core_tb` (profile 0). Simulation-only data files are copied into the generated XSim directory, and the serialized option `-testplusarg "VECTOR_DIR=."` resolves them there. The quotation marks are required by the Windows exported batch script.

The sole constraint is `create_clock -name sys_clk -period 20.000 [get_ports clk]`, for `xc7a200tfbg484-2`. Board pins, I/O standards, voltage-bank properties and external I/O delays are intentionally unspecified; this is internal clock timing acceptance, not board timing sign-off.

## Reproduce acceptance

From the repository root in PowerShell:

```powershell
vivado -mode batch -nojournal -log .Xil/c2_accept.log -source scripts/step6c2_pi_build.tcl -tclargs accept_01
```

Use the `vivado.bat` from your selected Vivado 2026.1 installation, either on PATH as above or by its full quoted path. The measured machine uses `E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat`; that drive layout is not required. The launcher sets `XILINX_VIVADO` to its active installation, and the build resolves `xvlog.bat`, `xelab.bat` and `xsim.bat` from that installation's `bin` directory. All three must exist and report version 2026.1 before project or simulation work begins. The resolved installation, executable directory and actual simulator version outputs are retained in run provenance and `tool_*_version.txt`. Windows installation paths containing spaces are supported.

Use a new label for every run. The script refuses existing report/scratch directories and retains all old evidence. It creates scratch work under `.Xil/c2_<label>` and evidence under `docs/reports/step6c2/<label>`. The tracked portable project is read-only to normal build invocations.

The run opens a relocated minimal XPR read-only to audit exact paths, types and compile order, reopens only the disposable copy to export scripts, verifies actual fixture staging, and executes those exported scripts for the profile-0 core. It then runs the other seven C2 configurations, the four unchanged C1 benches with explicit C1 sources/ROM, and the unchanged Step6B PWM bench: thirteen positive simulations total. Each requires exit success, its exact marker, absence of fatal/error, and applicable exact counts/profile identity. Python unit tests, C2 regeneration checks, Step6A verification, C1 checks and rejection of `-O`/`-OO` are also mandatory.

Eleven disposable negative cases must leave FAILED results: short-column, nonhex and truncated fixtures for each of round/range/sqrt, plus missing source and missing marker. Fixture failures must be explicit TB Fatal with no native simulator crash. The FXP and sqrt benches use indexed-byte tokenization because XSim 2026.1 can crash when string sscanf destinations outnumber available columns. Two independent fresh projects synthesize and route profiles 0 and 1. Gates cover primitive/hierarchy evidence, latches/black boxes, DRC, loops/no-clock/internal constraints, complete routing, setup/hold/pulse-width slack and totals/endpoints, plus raw unrounded worst setup/hold slack. Warnings are retained; there is no fixed DSP target. `build_result.txt` starts `IN_PROGRESS`; only the final all-gates path writes `PASS` and `STEP6C2_BUILD_PASS`. Caught failures write `FAILED`; native crashes cannot produce a new PASS.

No bitstream or hardware operation is performed. See `coordination/reports/step6c2_codex_report.md` for the actual tested revision, numerical comparisons, measurements, retained warnings and execution evidence.
