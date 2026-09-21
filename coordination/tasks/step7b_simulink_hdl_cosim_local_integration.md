# Step 7B — Simulink HDL Cosimulation Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible Simulink HDL Cosimulation path around the accepted FPGA FOC/PWM chain, using `PMLSM_ThreeLoop_Simple.slx` as the integration skeleton and `CMP_active` as the long-term Simulink boundary.

**Architecture:** Keep the existing Simple-model control path driving `Inverter_DeadTime -> PMLSM_Plant_Model` during Step 7B. Add a parallel `FPGA_HDL_Cosim` branch that quantizes Simulink values, drives a new `mc_foc_cosim_top` through a Vivado HDL Cosimulation block, and observes the active compare values that really loaded at PWM ZERO. Do not close the motor loop until Step 7C.

**Tech Stack:** MATLAB/Simulink R2026b Prerelease Update 3, HDL Verifier, Fixed-Point Designer, SoC Blockset + AMD support package, AMD Vivado Simulator 2026.1/XSI, SystemVerilog, Tcl/MATLAB scripting, Git/GitHub.

**Spec:** `coordination/specs/step7b_simulink_hdl_cosim_interface_design.md`

## Global Constraints

- Work only in the user's original MAIN: `D:/Project/FPGA_XC7A200T`.
- Do not create linked worktrees, extra clones, cloud copies, or a second local implementation directory.
- Preserve tracked/untracked user files, old worktrees, `FOC_Current`, `FOC_PWM`, `FOC_Gates`, local WDB/DCP/.runs/.sim results, and hardware material.
- Never use `reset --hard`, `clean -fd`, force checkout/switch, automatic stash, or wholesale directory overwrite.
- The local `simulink模型/PMLSM_ThreeLoop_Simple.slx` is user-owned source material that is currently not on GitHub main. Inspect it first and commit the as-found file before any functional edit.
- Repository copies under `simulink模型/` are authorized for modification. External `D:/Project/PMSLM_Simulation` remains read-only.
- Step 7B does not close the motor current loop. `Control_Task_10kHz` remains the plant-driving source in the Simple model.
- Long-term plant boundary is `D_high = CMP_active / 2500`. Do not use raw C4 modulation or Step 6E six-gate deadtime to drive the average inverter.
- Simulink average-inverter deadtime remains plant-side. Do not apply RTL deadtime a second time.
- Old MIL/Simple PWM update-delay approximations are not used by the future FPGA backend because the RTL already owns shadow and ZERO loading.
- HDL clock is 50 MHz / 20 ns. Initial Simulink↔HDL communication target is 50 us with 1:1 physical time.
- R2026b + Vivado 2026.1 was proven in Step 7A through MATLAB System Object/XSI. Step 7B must prove the Simulink HDL Cosimulation block path independently.
- Do not patch MathWorks version checks or suppress Vivado version warnings.
- Do not install/uninstall software or permanently change Windows PATH. Temporary MATLAB-session tool-path changes must be restored.
- No bitstream, FPGA board operation, Vitis workspace, AXI, FIL, JMAG/Maxwell, speed-loop or position-loop integration in this step.
- Do not submit `.slxc`, `slprj`, `xsim.dir`, compiled DLLs, `.Xil`, Vivado caches, MATLAB caches, or system TEMP output to Git.
- Finish on an open implementation PR. Do not merge it or start Step 7C.

## Review Focus

1. **Local Simple model differs from the screenshot/spec.** Before mutation, Task 1 must prove the real top-level block names, solver, callbacks, references, and model load/update status; unexpected topology stops modification.
2. **A saved Simulink model only looks connected but is not performing real XSI exchange.** Task 2 must verify actual HDL outputs, including 255→0 wrap, through the HDL Cosimulation block.
3. **The sine/cosine ROM is missing from the Vivado co-sim runtime directory.** Task 4 must check final logs for no `readmemh` file-not-found and must recover the historical 1165/1335/1335 active CMP.
4. **50 us scheduler ordering captures the wrong Simulink value at carrier peak.** Task 5 must run an explicit two-vector boundary experiment and write the exact transaction mapping.
5. **Step 7B accidentally changes accepted RTL or takes control of the plant.** Tasks 3 and 6 must run original Step 6D regressions and prove `Control_Task_10kHz -> Inverter_DeadTime` remains the active plant path.

---

## File Map

### New files

```text
motor_control_ip/integration/rtl/mc_foc_cosim_top.sv
motor_control_ip/integration/tb/mc_foc_cosim_top_tb.sv
motor_control_ip/integration/tb/cosim/step7b_counter.sv

scripts/step7b_probe_environment.m
scripts/step7b_inspect_simple_model.m
scripts/step7b_generate_minimal_cosim.m
scripts/step7b_generate_foc_cosim.m
scripts/step7b_integrate_simple_cosim.m
scripts/step7b_run_cosim.m

simulink模型/PMLSM_HDL_Cosim_Minimal.slx
simulink模型/init_PMLSM_fpga_cosim_params.m

coordination/reports/step7b_codex_report.md
docs/reports/step7b/simple_baseline_inventory.txt
docs/reports/step7b/environment_probe.txt
docs/reports/step7b/minimal_cosim_result.txt
docs/reports/step7b/foc_wrapper_xsim.txt
docs/reports/step7b/foc_cosim_result.txt
docs/reports/step7b/timing_alignment.txt
docs/reports/step7b/simple_model_after.txt
docs/reports/step7b/regression_summary.txt
```

Generated HDL-Verifier text/config artifacts that are directly referenced by the saved HDL Cosimulation blocks may be committed under:

```text
simulink模型/hdl_cosim/minimal/
simulink模型/hdl_cosim/foc/
```

but only if they are required to reopen/regenerate the blocks and contain no compiled binary/cache output.

### Existing files allowed to change

```text
simulink模型/PMLSM_ThreeLoop_Simple.slx   # local as-found baseline first, then FPGA branch
motor_control_ip/integration/rtl/mc_foc_pwm_top.sv
motor_control_ip/integration/tb/mc_foc_pwm_top_tb.sv
coordination/HANDOFF.md                    # implementation PR may update after successful 7B
```

Other accepted C1–C4/PWM/gate RTL stays read-only.

---

## Task 1: Import and freeze the user's as-found Simple-model baseline

**Files:**
- Add as baseline: `simulink模型/PMLSM_ThreeLoop_Simple.slx`
- Create: `docs/reports/step7b/simple_baseline_inventory.txt`
- Create later in this task: `scripts/step7b_inspect_simple_model.m`

**Interfaces:**
- Consumes: local user file `D:/Project/FPGA_XC7A200T/simulink模型/PMLSM_ThreeLoop_Simple.slx`
- Produces: a Git-tracked immutable baseline commit plus a text inventory that later tasks use to assert real block paths.

- [ ] **Step 1: Verify MAIN and preserve user state**

Run from PowerShell/CMD in the original project:

```bat
cd /d D:\Project\FPGA_XC7A200T
git rev-parse --show-toplevel
git worktree list --porcelain
git remote -v
git branch --show-current
git status --short
git fetch origin
git rev-parse origin/main
```

Expected:
- top-level is exactly `D:/Project/FPGA_XC7A200T`;
- origin points to `kazecode666/FPGA_XC7A200T_Study`;
- merged Step 7B spec exists on main;
- `simulink模型/PMLSM_ThreeLoop_Simple.slx` exists locally;
- any unrelated tracked/untracked user changes are recorded and preserved.

If changing to the Step 7B implementation branch would overwrite a local user file, stop and report instead of stashing or forcing.

- [ ] **Step 2: Safely synchronize accepted main and create the local implementation branch**

Use a normal fast-forward only when Git reports it is safe:

```bat
git switch main
git pull --ff-only origin main
git switch -c step7b-simulink-hdl-cosim
```

If the branch already exists from an earlier interrupted attempt, inspect it first; do not force-reset it.

- [ ] **Step 3: Read the Simple model without modifying it**

Create a temporary MATLAB command or script that loads the local model and writes only observations. The committed inspection script created after the baseline commit must use this structure:

```matlab
root = 'D:/Project/FPGA_XC7A200T';
modelFile = fullfile(root,'simulink模型','PMLSM_ThreeLoop_Simple.slx');
assert(isfile(modelFile),'PMLSM_ThreeLoop_Simple.slx is missing');

[~,mdl] = fileparts(modelFile);
load_system(modelFile);

rootBlocks = find_system(mdl,'SearchDepth',1,'Type','Block');
expected = { ...
    [mdl '/Simple_Host'], ...
    [mdl '/Control_Task_10kHz'], ...
    [mdl '/Inverter_DeadTime'], ...
    [mdl '/PMLSM_Plant_Model']};

for k = 1:numel(expected)
    assert(getSimulinkBlockHandle(expected{k}) ~= -1, ...
        'Required Simple-model block missing: %s', expected{k});
end

fprintf('MODEL=%s\n',modelFile);
fprintf('SolverType=%s\n',get_param(mdl,'SolverType'));
fprintf('Solver=%s\n',get_param(mdl,'Solver'));
fprintf('FixedStep=%s\n',get_param(mdl,'FixedStep'));
fprintf('InitFcn=%s\n',get_param(mdl,'InitFcn'));
for k = 1:numel(rootBlocks)
    fprintf('ROOT_BLOCK=%s | BlockType=%s | ReferenceBlock=%s\n', ...
        rootBlocks{k}, ...
        get_param(rootBlocks{k},'BlockType'), ...
        get_param(rootBlocks{k},'ReferenceBlock'));
end

set_param(mdl,'SimulationCommand','update');
fprintf('MODEL_UPDATE=PASS\n');
close_system(mdl,0);
```

Do not save the model during this inspection.

- [ ] **Step 4: Save the inventory text**

Write the output to:

```text
docs/reports/step7b/simple_baseline_inventory.txt
```

The file must include the actual top-level block paths, model version, solver, fixed step, InitFcn, referenced models/libraries found by `find_mdlrefs`, and `MODEL_UPDATE=PASS`.

If the four expected root blocks are absent, stop before modifying the model and report the actual topology to the user.

- [ ] **Step 5: Commit only the as-found baseline model and inventory**

Check what is staged:

```bat
git add -- "simulink模型/PMLSM_ThreeLoop_Simple.slx" "docs/reports/step7b/simple_baseline_inventory.txt"
git diff --cached --name-status
git diff --cached --check
```

Expected staged paths: exactly those two paths.

Commit:

```bat
git commit -m "simulink: import ThreeLoop Simple baseline"
```

This commit must precede all FPGA co-sim model edits.

- [ ] **Step 6: Add the reusable inspection script after the baseline commit**

Create `scripts/step7b_inspect_simple_model.m` from the Step 3 logic, extended to save its own output to the requested report path. Commit it separately:

```bat
git add scripts/step7b_inspect_simple_model.m
git commit -m "test: add Simple model structure probe"
```

**Task 1 deliverable:** the user's original Simple model is now versioned on the implementation branch before any co-sim modification, and its real topology is known.

---

## Task 2: Prove the Simulink HDL Cosimulation block path with a tiny HDL DUT

**Files:**
- Create: `motor_control_ip/integration/tb/cosim/step7b_counter.sv`
- Create: `scripts/step7b_probe_environment.m`
- Create: `scripts/step7b_generate_minimal_cosim.m`
- Create: `simulink模型/PMLSM_HDL_Cosim_Minimal.slx`
- Create: `docs/reports/step7b/environment_probe.txt`
- Create: `docs/reports/step7b/minimal_cosim_result.txt`
- Optional generated text/config: `simulink模型/hdl_cosim/minimal/`

**Interfaces:**
- Consumes: R2026b + HDL Verifier + Vivado 2026.1 proven in Step 7A.
- Produces: a saved Simulink model containing one real Vivado HDL Cosimulation block and an executable regression that proves XSI data exchange.

- [ ] **Step 1: Write the tiny HDL counter**

Create:

```systemverilog
`timescale 1ns/1ps
module step7b_counter (
    input  logic       clk,
    input  logic       reset_n,
    input  logic [7:0] in_data,
    output logic [7:0] out_data
);
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      out_data <= 8'd0;
    else
      out_data <= in_data + 8'd1;
  end
endmodule
```

File:
```text
motor_control_ip/integration/tb/cosim/step7b_counter.sv
```

- [ ] **Step 2: Probe the newly installed AMD support package without redoing Step 7A**

Create `scripts/step7b_probe_environment.m`. It must explicitly invoke the current R2026b and print:

```matlab
fprintf('MATLAB=%s\n',version);
fprintf('RELEASE=%s\n',version('-release'));

a = matlab.addons.installedAddons;
disp(a);

try
    s = matlabshared.supportpkg.getInstalled;
    disp(s);
catch ME
    fprintf('SUPPORTPKG_GETINSTALLED_ERROR=%s\n',ME.message);
end

assert(license('test','EDA_Simulator_Link') == 1, ...
    'HDL Verifier license unavailable');

fprintf('HDL_VERIFIER_LICENSE=PASS\n');
```

The script must search the returned names for:

```text
SoC Blockset Support Package for AMD FPGA and SoC Devices
```

and report either:

```text
AMD_SUPPORT_PACKAGE=PASS version=<actual>
```

or:

```text
AMD_SUPPORT_PACKAGE=NOT_RECOGNIZED
```

A missing support package is reportable but does not by itself block the pure simulator test if HDL Verifier remains usable.

Save the batch output to `docs/reports/step7b/environment_probe.txt`.

- [ ] **Step 3: Generate the Simulink HDL Cosimulation block with the R2026b command-line workflow**

Create `scripts/step7b_generate_minimal_cosim.m`. Start from the Step 7A-proven API:

```matlab
root = 'D:/Project/FPGA_XC7A200T';
src  = fullfile(root,'motor_control_ip','integration','tb','cosim','step7b_counter.sv');

oldpwd = pwd;
oldpath = getenv('PATH');
oldvivado = getenv('XILINX_VIVADO');

cleanup = onCleanup(@() localRestore(oldpwd,oldpath,oldvivado));

hdlsetuptoolpath( ...
    'ToolName','Xilinx Vivado', ...
    'ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');

work = fullfile(root,'.Xil','step7b_minimal_cosim');
if ~isfolder(work), mkdir(work); end
cd(work);

c = cosimulationConfiguration( ...
    'Vivado Simulator','Simulink','step7b_counter');
c.HDLFiles = {src,'Verilog'};
c.HDLSimulatorPath = 'E:/AMDDesignTools/2026.1/Vivado/bin';
c.HDLTimeUnit = 'ns';
c.AutoTimeScale = false;
c.TimeScale = {1,'s'};
runWorkflow(c);
```

Define `localRestore` in the same file:

```matlab
function localRestore(oldpwd,oldpath,oldvivado)
    cd(oldpwd);
    setenv('PATH',oldpath);
    setenv('XILINX_VIVADO',oldvivado);
end
```

If R2026b rejects any property name above, use `properties(c)` and local `help cosimulationConfiguration` to make the smallest R2026b-compatible correction; record the exact difference in the Step 7B report rather than patching MathWorks code.

- [ ] **Step 4: Curate the generated Simulink block into a reproducible minimal model**

The generation script must:
1. identify exactly one generated HDL Cosimulation block;
2. create/open `PMLSM_HDL_Cosim_Minimal`;
3. copy that block into the model;
4. add a uint8 source, output logger, and assertions;
5. configure a 20 ns HDL clock and active-low reset in the generated block;
6. save the model to `simulink模型/PMLSM_HDL_Cosim_Minimal.slx`.

The script must fail if it finds zero or multiple generated Vivado HDL Cosimulation blocks.

Do not hand-edit a binary SLX in a ZIP editor.

- [ ] **Step 5: Make the minimal test exercise six values through Simulink**

Use the generated block in six short simulations or one deterministic vector run:

```text
0   -> 1
1   -> 2
42  -> 43
127 -> 128
254 -> 255
255 -> 0
```

The runner must assert output values obtained from the HDL Cosimulation block. It must not calculate a MATLAB-only reference and call that “co-sim” without reading the block output.

Save an output transcript ending with:

```text
STEP7B_SIMULINK_MINIMAL_COSIM_PASS
```

to `docs/reports/step7b/minimal_cosim_result.txt`.

- [ ] **Step 6: Verify the saved model is reusable**

Close all models and MATLAB-generated HDL simulation state, start a fresh R2026b batch process, reopen `PMLSM_HDL_Cosim_Minimal.slx`, and rerun the six-value check.

If the block contains an absolute system-TEMP dependency, regenerate it into a repo-relative `simulink模型/hdl_cosim/minimal/` configuration location and repeat until the saved model can be reopened from the project root.

Commit only the SLX, source HDL, generation/probe scripts, report text, and any small generated text/MAT configuration directly required by the saved block. Do not commit compiled XSI DLLs or `xsim.dir`.

- [ ] **Step 7: Commit Task 2**

```bat
git add motor_control_ip/integration/tb/cosim/step7b_counter.sv ^
        scripts/step7b_probe_environment.m ^
        scripts/step7b_generate_minimal_cosim.m ^
        "simulink模型/PMLSM_HDL_Cosim_Minimal.slx" ^
        docs/reports/step7b/environment_probe.txt ^
        docs/reports/step7b/minimal_cosim_result.txt
git diff --cached --check
git commit -m "test: prove Simulink Vivado HDL cosimulation"
```

Include only required generated configuration files if the saved block depends on them.

**Task 2 deliverable:** Simulink itself, not only a MATLAB System Object, has performed real HDL-Verifier/Vivado data exchange.

---

## Task 3: Export active CMP cleanly and build the co-sim RTL wrapper

**Files:**
- Modify: `motor_control_ip/integration/rtl/mc_foc_pwm_top.sv`
- Modify: `motor_control_ip/integration/tb/mc_foc_pwm_top_tb.sv`
- Create: `motor_control_ip/integration/rtl/mc_foc_cosim_top.sv`
- Create: `motor_control_ip/integration/tb/mc_foc_cosim_top_tb.sv`
- Create: `docs/reports/step7b/foc_wrapper_xsim.txt`

**Interfaces:**
- Consumes: accepted `mc_foc_pwm_top` and Step 6D timing contract.
- Produces: stable co-sim ports `cmp_*_active`, `accepted_sample_id`, `active_command_id`, `active_valid`, `needs_reset`, `fault_code`.

- [ ] **Step 1: Write the failing wrapper TB first**

Create `mc_foc_cosim_top_tb.sv` with:
- 50 MHz clock;
- reset asserted for at least five rising edges;
- `run_enable=1` after reset;
- fixed historical d_current input.

Use exact fixed-point constants:

```systemverilog
ia      =  24'sd32768;   // +1.0 A S24/F15
ib      = -24'sd16384;   // -0.5 A
ic      = -24'sd16384;
theta_e =  16'h0000;
we      =  32'sd0;
id_ref  =  25'sd0;
iq_ref  =  25'sd0;
vdc     =  25'sd1572864; // 48.0 V S25/F15
pi_reset   = 1'b0;
uq_zero_en = 1'b0;
```

The initial test must wait for `active_command_id==1` and then assert:

```systemverilog
assert (accepted_sample_id >= 1)
  else $fatal(1,"STEP7B_WRAPPER_FAIL no accepted sample");

assert (active_valid)
  else $fatal(1,"STEP7B_WRAPPER_FAIL active_valid");

assert (cmp_u_active == 12'd1165 &&
        cmp_v_active == 12'd1335 &&
        cmp_w_active == 12'd1335)
  else $fatal(1,"STEP7B_WRAPPER_FAIL first active CMP");

assert (!needs_reset && fault_code == 3'd0)
  else $fatal(1,"STEP7B_WRAPPER_FAIL fault");
```

Then drop `run_enable` and assert `active_valid==0` after the sampling edge.

Before implementation, compile should fail because `mc_foc_cosim_top` does not exist.

- [ ] **Step 2: Add only the authorized active-CMP monitor ports to the old 6D top**

Add to `mc_foc_pwm_top`:

```systemverilog
output logic [11:0] cmp_u_active_mon,
output logic [11:0] cmp_v_active_mon,
output logic [11:0] cmp_w_active_mon
```

and only these assignments:

```systemverilog
assign cmp_u_active_mon = cmp_u_active;
assign cmp_v_active_mon = cmp_v_active;
assign cmp_w_active_mon = cmp_w_active;
```

Do not change the existing carrier, FOC, adapter, shadow, deadline, or fault logic.

- [ ] **Step 3: Keep the old wildcard TB compiling**

Because `mc_foc_pwm_top_tb` instantiates the DUT with `.*`, add:

```systemverilog
logic [11:0] cmp_u_active_mon;
logic [11:0] cmp_v_active_mon;
logic [11:0] cmp_w_active_mon;
```

Do not alter its existing assertions or PASS conditions.

- [ ] **Step 4: Implement `mc_foc_cosim_top` minimally**

Use this interface and behavior:

```systemverilog
module mc_foc_cosim_top #(parameter int PI_PROFILE=0) (
  input  logic clk,
  input  logic reset_n,
  input  logic run_enable,
  input  logic signed [23:0] ia, ib, ic,
  input  logic [15:0] theta_e,
  input  logic signed [31:0] we,
  input  logic signed [24:0] id_ref, iq_ref, vdc,
  input  logic pi_reset,
  input  logic uq_zero_en,

  output logic [11:0] cmp_u_active,
  output logic [11:0] cmp_v_active,
  output logic [11:0] cmp_w_active,
  output logic [31:0] accepted_sample_id,
  output logic [31:0] active_command_id,
  output logic active_valid,
  output logic needs_reset,
  output logic [2:0] fault_code
);
```

Internals:

```systemverilog
logic sample_request_i, sample_ready_i;
logic pwm_command_loaded_i;
logic pwm_u_i, pwm_v_i, pwm_w_i;
logic active_seen;

wire sample_valid_i = sample_request_i;
wire sample_accept_i = sample_request_i && sample_ready_i;

assign active_valid = active_seen && run_enable && !needs_reset;
```

Instantiate `mc_foc_pwm_top` with `sample_valid(sample_valid_i)`, route its monitor outputs to `cmp_*_active`, and do not expose raw C4 duty as the plant boundary.

Counter/state behavior:

```systemverilog
always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    accepted_sample_id <= 32'd0;
    active_command_id  <= 32'd0;
    active_seen        <= 1'b0;
  end else begin
    if (sample_accept_i)
      accepted_sample_id <= accepted_sample_id + 1'b1;

    if (pwm_command_loaded_i) begin
      active_command_id <= active_command_id + 1'b1;
      active_seen       <= 1'b1;
    end

    if (!run_enable || needs_reset)
      active_seen <= 1'b0;
  end
end
```

Do not create a second PWM or FOC state machine.

- [ ] **Step 5: Run the wrapper TB in XSim**

Use Vivado 2026.1 `xvlog/xelab/xsim` with the same source ordering used by Step 6D, including the sine ROM copied to the simulation run directory.

The log must end with a marker such as:

```text
STEP7B_FOC_WRAPPER_PASS first_cmp=1165,1335,1335
```

Save the actual compile/elaboration/simulation transcript to `docs/reports/step7b/foc_wrapper_xsim.txt`.

- [ ] **Step 6: Run original Step 6D regressions**

Run the original `mc_foc_pwm_top_tb` in:
- `PI_PROFILE=0, DEMO=0`;
- `PI_PROFILE=1, DEMO=0`.

Require the existing markers:

```text
ALL STEP 6D FOC PWM TESTS PASSED profile=0 ...
ALL STEP 6D FOC PWM TESTS PASSED profile=1 ...
```

No test weakening is allowed to accommodate the new outputs.

- [ ] **Step 7: Commit Task 3**

```bat
git add motor_control_ip/integration/rtl/mc_foc_pwm_top.sv ^
        motor_control_ip/integration/tb/mc_foc_pwm_top_tb.sv ^
        motor_control_ip/integration/rtl/mc_foc_cosim_top.sv ^
        motor_control_ip/integration/tb/mc_foc_cosim_top_tb.sv ^
        docs/reports/step7b/foc_wrapper_xsim.txt
git diff --cached --check
git commit -m "feat: add FOC cosimulation wrapper"
```

**Task 3 deliverable:** a small, testable RTL wrapper exposes the actual applied compare values without changing accepted motor-control math or PWM timing.

---

## Task 4: Generate the full FOC HDL Cosimulation block and add a non-driving FPGA branch to the Simple model

**Files:**
- Create: `scripts/step7b_generate_foc_cosim.m`
- Create: `scripts/step7b_integrate_simple_cosim.m`
- Create: `simulink模型/init_PMLSM_fpga_cosim_params.m`
- Modify: `simulink模型/PMLSM_ThreeLoop_Simple.slx`
- Optional generated text/config: `simulink模型/hdl_cosim/foc/`
- Create: `docs/reports/step7b/simple_model_after.txt`
- Create: `docs/reports/step7b/foc_cosim_result.txt`

**Interfaces:**
- Consumes: `mc_foc_cosim_top` and the imported Simple-model baseline.
- Produces: `PMLSM_ThreeLoop_Simple/FPGA_HDL_Cosim` as a parallel smoke/monitor branch; the plant remains driven by legacy `Control_Task_10kHz`.

- [ ] **Step 1: Create the co-sim parameter script**

Create `simulink模型/init_PMLSM_fpga_cosim_params.m` with only Step 7B co-sim configuration:

```matlab
FPGA_Cosim_Enable = 1;
FPGA_Cosim_Input_Mode = 0; % 0=fixed smoke, 1=Simple live signals for Step 7C

FPGA_CLK_Hz = 50e6;
FPGA_CLK_Period_s = 20e-9;
FPGA_PWM_Hz = 10e3;
FPGA_TBPRD = 2500;
FPGA_Cosim_Ts_s = 50e-6;

FPGA_Current_FWL = 24;
FPGA_Current_FL  = 15;
FPGA_Theta_WL    = 16;
FPGA_We_WL       = 32;
FPGA_We_FL       = 16;
FPGA_RefVdc_WL   = 25;
FPGA_RefVdc_FL   = 15;

FPGA_Smoke_ia_A = 1.0;
FPGA_Smoke_ib_A = -0.5;
FPGA_Smoke_ic_A = -0.5;
FPGA_Smoke_theta_rad = 0.0;
FPGA_Smoke_we_radps = 0.0;
FPGA_Smoke_id_ref_A = 0.0;
FPGA_Smoke_iq_ref_A = 0.0;
FPGA_Smoke_vdc_V = 48.0;

FPGA_Smoke_CMP_Expected = uint16([1165 1335 1335]);
```

Do not alter the plant motor parameters.

- [ ] **Step 2: Generate the FOC Simulink HDL Cosimulation block**

Create `scripts/step7b_generate_foc_cosim.m` using:

```matlab
c = cosimulationConfiguration( ...
    'Vivado Simulator','Simulink','mc_foc_cosim_top');
```

Set:
- explicit HDL source list for C1–C4, adapter, `motor_pwm_core`, `mc_foc_pwm_top`, `mc_foc_cosim_top`;
- Vivado 2026.1 path;
- HDL time unit;
- 1:1 physical timescale;
- 50 MHz clock and active-low reset in the generated block;
- output sample time compatible with `FPGA_Cosim_Ts_s=50e-6`.

The source list must use the actual package/module dependencies from the current repository rather than copying an old worktree.

- [ ] **Step 3: Stage the sine ROM for Vivado/XSim**

Before the final FOC smoke run, ensure the runtime that evaluates:

```systemverilog
$readmemh("sin_qw_4096x18.mem", sin_qw_rom);
```

can open:

```text
motor_control_ip/foc/rom/sin_qw_4096x18.mem
```

Use the smallest generated-workflow mechanism supported by R2026b/Vivado:
- add/copy the MEM file into the final XSim runtime directory before simulation, or
- add it as a Vivado simulation data source if the generated flow exposes that hook.

Do not change ROM contents or accepted trig RTL.

The final FOC co-sim evidence log must contain no `readmemh` file-not-found message.

- [ ] **Step 4: Programmatically add `FPGA_HDL_Cosim` to the Simple model**

Create `scripts/step7b_integrate_simple_cosim.m`.

The script must assert the current model still contains:

```text
PMLSM_ThreeLoop_Simple/Simple_Host
PMLSM_ThreeLoop_Simple/Control_Task_10kHz
PMLSM_ThreeLoop_Simple/Inverter_DeadTime
PMLSM_ThreeLoop_Simple/PMLSM_Plant_Model
```

before it changes anything.

If `FPGA_HDL_Cosim` already exists, fail instead of duplicating it.

Create:

```text
PMLSM_ThreeLoop_Simple/FPGA_HDL_Cosim
  ├─ FPGA_Input_Adapter
  ├─ HDL_Cosimulation
  ├─ FPGA_Output_Adapter
  └─ FPGA_Cosim_Monitor
```

Use MATLAB/Simulink APIs (`add_block`, `add_line`, `set_param`). Do not use global automatic layout.

- [ ] **Step 5: Build the two input sources**

Inside `FPGA_Input_Adapter`:

**Mode 0 — Step 7B fixed smoke.** Use the exact smoke constants from `init_PMLSM_fpga_cosim_params.m`.

**Mode 1 — reserved live path for Step 7C.** Use the Simple model's existing Goto/From signals where present:
- `ia`, `ib`, `ic`;
- `theta`;
- `we`;
- `vdc`;
- `id_cmd`;
- `iq_cmd`;
- `PWM_EN` / equivalent enable;
- `PI_Reset` / equivalent reset.

The implementation script must validate each actual Goto tag with `find_system`. If a tag name differs in the real Simple model, record the actual name in `simple_model_after.txt` and connect to that real signal; do not invent a new semantic signal.

Mode 1 is not allowed to drive the plant in 7B.

- [ ] **Step 6: Quantize inputs explicitly**

Use Data Type Conversion blocks with:
- `RndMeth='Nearest'`;
- `SaturateOnIntegerOverflow='on'`.

Required output types:

```text
ia/ib/ic      fixdt(1,24,15)
theta_e       fixdt(0,16,0)
we            fixdt(1,32,16)
id_ref/iq_ref fixdt(1,25,15)
vdc           fixdt(1,25,15)
```

For live theta, use an explicit MATLAB Function or equivalent subsystem that implements:

```matlab
function y = theta_to_u16(theta)
t = mod(theta,2*pi);
n = floor(t * 65536/(2*pi) + 0.5);
if n >= 65536
    n = 0;
end
y = uint16(n);
end
```

The smoke case theta=0 must map exactly to `uint16(0)`.

- [ ] **Step 7: Add the generated HDL Cosimulation block and output adapter**

Copy exactly one generated Vivado HDL Cosimulation block into:

```text
PMLSM_ThreeLoop_Simple/FPGA_HDL_Cosim/HDL_Cosimulation
```

Expose/log:

```text
cmp_u_active
cmp_v_active
cmp_w_active
accepted_sample_id
active_command_id
active_valid
needs_reset
fault_code
```

Compute monitor-only duties:

```text
duty_u = double(cmp_u_active) / 2500
duty_v = double(cmp_v_active) / 2500
duty_w = double(cmp_w_active) / 2500
```

Do not connect these duties to `Inverter_DeadTime` in Step 7B.

- [ ] **Step 8: Prove the legacy plant path was not replaced**

Before saving, programmatically inspect line connectivity around:
- `Control_Task_10kHz` compare outputs;
- `Inverter_DeadTime` compare inputs.

Save actual source/destination block paths in `docs/reports/step7b/simple_model_after.txt` and include:

```text
FPGA_BRANCH_DRIVES_PLANT=0
LEGACY_CONTROL_DRIVES_INVERTER=1
```

- [ ] **Step 9: Run the fixed FOC smoke through Simulink + Vivado**

Use a 50 us simulation communication step for this smoke, preferably through `Simulink.SimulationInput` overrides so the saved Simple-model legacy solver configuration is not silently rewritten.

Keep the fixed smoke values stable until the first active command loads.

Require:

```text
accepted_sample_id >= 1
active_command_id  >= 1
first active CMP   = 1165,1335,1335
active_valid       = 1
needs_reset        = 0
fault_code         = 0
```

Save evidence ending with:

```text
STEP7B_FOC_COSIM_SMOKE_PASS
```

to `docs/reports/step7b/foc_cosim_result.txt`.

- [ ] **Step 10: Update and short-run the Simple model with the FPGA branch disabled/non-driving**

Run:
1. `SimulationCommand='update'`;
2. a short legacy-path simulation using the model's original saved solver/fixed step;
3. a structure check proving `FPGA_HDL_Cosim` exists but does not drive `Inverter_DeadTime`.

Do not claim numeric equivalence if the original model did not have a frozen numeric baseline; the acceptance here is no structural takeover and no model-update/runtime error.

- [ ] **Step 11: Commit Task 4**

Stage only the authorized model/script/RTL-generated text assets and reports, then:

```bat
git diff --cached --name-status
git diff --cached --check
git commit -m "feat: add FPGA HDL cosim branch to Simple model"
```

**Task 4 deliverable:** the user's Simple model contains a runnable, parallel FOC/PWM HDL branch while the legacy controller still drives the plant.

---

## Task 5: Freeze the 50 us Simulink↔HDL scheduler contract

**Files:**
- Create/modify: `scripts/step7b_run_cosim.m`
- Create: `docs/reports/step7b/timing_alignment.txt`
- Modify only if needed for test stimulus: `simulink模型/PMLSM_ThreeLoop_Simple.slx`

**Interfaces:**
- Consumes: working FOC co-sim branch from Task 4.
- Produces: one unambiguous rule mapping a Simulink 50 us input update to the HDL accepted transaction and active-command ID.

- [ ] **Step 1: Select two distinct existing Step 6D vectors**

Parse:

```text
motor_control_ip/integration/tb/vectors/step6d_pwm_vectors.txt
```

Select two profile-0 normal rows whose expected `cmp_u/v/w` fields differ.

The test script must print:
- row indices;
- physical/fixed input values used;
- expected CMP tuples from the vector file.

Do not invent new golden arithmetic.

- [ ] **Step 2: Build a 50 us boundary stimulus**

For the smoke-source path:
- drive vector A from simulation start up to the first 50 us boundary;
- update to vector B exactly on the next 50 us Simulink sample hit;
- keep B stable thereafter.

Reset/run sequencing must make the first accepted FOC transaction deterministic.

- [ ] **Step 3: Run and identify which vector the first accepted transaction used**

Observe:
- `accepted_sample_id`;
- `active_command_id`;
- first and second active CMP tuples.

Compare the observed tuples against the expected vector-A and vector-B CMP fields.

The log must explicitly state one rule, for example:

```text
At a Simulink data update coincident with the 50 us HDL carrier-peak time,
the HDL transaction N captures the NEW Simulink value.
```

or:

```text
... captures the PREVIOUS Simulink value; the new value is first used by transaction N+1.
```

Use the observed result, not an assumed scheduler order.

- [ ] **Step 4: Remove any race if the behavior is nondeterministic**

Repeat the same run at least three times from a fresh simulation state.

If the result is not stable:
- adjust the supported HDL-Verifier cosimulation start/clock offset so the Simulink data update does not coincide ambiguously with the active HDL clock edge;
- rerun until all three repetitions show the same mapping.

Do not solve the race by reducing the HDL clock, changing PWM timing, or inserting an unreviewed full control-period delay.

- [ ] **Step 5: Write the frozen timing contract**

Save `docs/reports/step7b/timing_alignment.txt` with:
- Simulink communication step = 50 us;
- HDL clock = 20 ns;
- reset release relation;
- carrier peak relation;
- vector A/B test;
- three-run result;
- exact accepted-sample mapping;
- exact active-command mapping.

End with:

```text
STEP7B_TIMING_ALIGNMENT_PASS
```

- [ ] **Step 6: Commit Task 5**

```bat
git add scripts/step7b_run_cosim.m docs/reports/step7b/timing_alignment.txt
git diff --cached --check
git commit -m "test: freeze Simulink HDL timing alignment"
```

**Task 5 deliverable:** Step 7C can connect the motor plant without guessing whether a value updated at 50 us is sampled immediately or one transaction later.

---

## Task 6: Final regression, report, GitHub synchronization, and implementation PR

**Files:**
- Create: `coordination/reports/step7b_codex_report.md`
- Create/update: `docs/reports/step7b/regression_summary.txt`
- Update: `coordination/HANDOFF.md` only after all 7B acceptance checks have passed.

**Interfaces:**
- Consumes: all Task 1–5 deliverables.
- Produces: reproducible Step 7B implementation PR, local runnable models, and explicit handoff to Step 7C.

- [ ] **Step 1: Run the complete Step 7B acceptance sequence fresh**

After the last RTL/SLX/script change, run in this order:

```text
1. environment/support-package probe
2. Simple-model structure/update probe
3. minimal Simulink HDL co-sim six-value test
4. standalone mc_foc_cosim_top XSim TB
5. original Step 6D profile0 DEMO=0
6. original Step 6D profile1 DEMO=0
7. Step 6E default/profile0 regression or accepted default demo test
8. Simple-model FOC co-sim smoke
9. 50 us timing alignment test, three fresh runs
10. Simple-model legacy path short run with FPGA branch non-driving
```

Do not reuse a PASS marker generated before the final code/model change.

- [ ] **Step 2: Check Step 6E compatibility**

Because `mc_foc_pwm_top` gained output ports, compile/run a Step 6E default regression to prove named instantiations still work.

The gate-output math does not need another route in Step 7B unless the RTL change unexpectedly alters synthesis structure beyond passive output taps.

- [ ] **Step 3: Inspect the branch for accidental generated/cache files**

Run:

```bat
git status --short
git diff --check
git ls-files "simulink模型/*.slxc" "simulink模型/slprj/*" ".Xil/*" "*xsim.dir*"
```

The tracked result for cache patterns must be empty unless a pre-existing accepted file is already tracked; if so, report it rather than adding new cache content.

- [ ] **Step 4: Write `regression_summary.txt`**

It must contain exact PASS markers and actual counts/rows for:
- minimal Simulink co-sim;
- wrapper TB;
- Step 6D profile0/profile1;
- Step 6E compatibility;
- FOC Simulink smoke;
- timing alignment;
- legacy plant path non-driving status.

Do not summarize a test that was not rerun after the final change.

- [ ] **Step 5: Write the Codex execution report**

Create `coordination/reports/step7b_codex_report.md` with:

```text
A. MAIN / branch / Git state and preserved user files
B. imported PMLSM_ThreeLoop_Simple baseline commit
C. R2026b / HDL Verifier / AMD support package / Vivado versions
D. minimal Simulink HDL Cosimulation block result
E. mc_foc_cosim_top interface and standalone XSim result
F. active CMP first-command result 1165/1335/1335
G. ROM staging method and proof of successful readmemh
H. Simple-model FPGA_HDL_Cosim structure and fixed-point formats
I. proof that legacy Control_Task_10kHz still drives Inverter_DeadTime
J. exact 50 us scheduler/transaction contract
K. Step 6D/6E regression results
L. files intentionally not committed
M. remaining Step 7C work and known limitations
```

Explicitly state that no dynamic motor current loop was closed in Step 7B.

- [ ] **Step 6: Update HANDOFF only after acceptance**

Mark:
- Step 7A accepted;
- Step 7B implementation complete and awaiting/after Review as appropriate;
- Simple model is now the main integration skeleton;
- the frozen active-CMP boundary;
- timing-alignment result;
- Step 7C will be the first actual plant current-loop closure.

Do not mark Step 7C as started.

- [ ] **Step 7: Push the implementation branch and open the PR**

First verify all authorized commits are present and user unrelated files are not staged:

```bat
git status --short
git log --oneline --decorate -8
git diff origin/main...HEAD --stat
git diff --check
```

Push:

```bat
git push -u origin step7b-simulink-hdl-cosim
```

Open:

```text
PR title:
Step 7B: Add Simulink HDL co-simulation interface
```

PR body must mention:
- the original Simple baseline was committed before modification;
- minimal Simulink block path passed;
- full FOC/PWM Simulink smoke passed;
- exact 50 us scheduler rule;
- active CMP 1165/1335/1335;
- legacy plant path remains driven by `Control_Task_10kHz`;
- no motor loop closure;
- no bitstream/hardware/Step 7C.

- [ ] **Step 8: Stop for ChatGPT Review**

Return to the user:
- implementation PR URL;
- local Simple model absolute path;
- how to open/run the minimal model;
- how to open/run the Simple-model FPGA smoke;
- exact report path.

Do not merge the PR and do not start Step 7C.

---

## Codex Start Prompt

After this task-document PR is merged, the user can send the following directly to local Codex:

```text
开始 Step 7B，严格按 executing-plans 顺序执行。

先读取：
coordination/HANDOFF.md
coordination/specs/step7b_simulink_hdl_cosim_interface_design.md
coordination/tasks/step7b_simulink_hdl_cosim_local_integration.md

只在我的原始主项目：
D:/Project/FPGA_XC7A200T
中工作。

先核对 Git 主工作树、远端、当前修改和已合并 main。
不要创建 worktree/额外 clone，不 stash，不 reset/clean，不覆盖我的文件。

非常重要：
simulink模型/PMLSM_ThreeLoop_Simple.slx 是我本地已有但之前未同步 GitHub 的模型。
先用 MATLAB/Simulink API 只读检查真实结构，在任何功能修改前，
把 as-found 的 Simple 模型和 baseline inventory 作为第一笔实现 commit 纳入分支。
之后再开始修改，并把所有授权的 SLX/RTL/scripts/reports 继续同步到 GitHub。
不要只改本地模型。

按任务书先做最小 Simulink HDL Cosimulation Block + Vivado 2026.1 联通；
再做 mc_foc_cosim_top 和 active CMP 只读端口；
然后在 PMLSM_ThreeLoop_Simple.slx 中新增并联 FPGA_HDL_Cosim branch。

Step 7B 中 FPGA branch 只能 smoke/monitor，
不得接管 Control_Task_10kHz -> Inverter_DeadTime -> PMLSM_Plant_Model 主链。
第一笔 d_current 的真实 active CMP 必须检查为 1165/1335/1335。

把 50 us Simulink 数据更新与 HDL carrier peak 的 scheduler 顺序实际测出来，
连续三次新鲜仿真一致后冻结 timing contract，不凭假设。

确认新安装的 SoC Blockset Support Package for AMD 是否被 R2026b 识别；
这不是重新做 Step 7A，也不要因为 support package 问题去 patch MATLAB。
HDL simulator 仍使用现有 Vivado 2026.1。

完整重跑任务书列出的 Step 7B 验收和原 6D/6E必要回归。
不跑 bitstream、不操作硬件、不开始电机闭环、不进入 Step 7C。

最后写：
coordination/reports/step7b_codex_report.md
docs/reports/step7b/

推送实现分支并创建 PR：
Step 7B: Add Simulink HDL co-simulation interface

返回 PR、本地模型路径和复现步骤，停在开放 PR 等待 ChatGPT Review。
```
