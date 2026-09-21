# Step 7C — Dynamic FPGA Current Loop with Free-Moving PMLSM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing Vivado/XSI FPGA FOC/PWM controller actually drive the shared Simulink average inverter and free-moving PMLSM plant, using dynamic plant current/angle/speed feedback and the real active-CMP boundary.

**Architecture:** Preserve one Simple model, one average inverter/deadtime implementation, and one motor plant. Keep the legacy command path intact, add a static backend selection, refactor only the inverter command front-end so both legacy counts and FPGA active duties meet at one normalized `D_high` boundary, and run the existing HDL Cosimulation block at a 1 us reference exchange/plant step while the RTL control period remains 100 us.

**Tech Stack:** MATLAB/Simulink R2026b Prerelease Update 3, HDL Verifier, Fixed-Point Designer, SoC Blockset AMD support package, Vivado Simulator 2026.1/XSI, SystemVerilog, MATLAB API model editing, Git/GitHub.

**Spec:** `coordination/specs/step7c_dynamic_motor_current_loop_cosim_design.md`

## Global Constraints

- Work only in `D:/Project/FPGA_XC7A200T`.
- Do not create a linked worktree, extra clone, cloud implementation copy, or second local project.
- Preserve unrelated tracked/untracked user files, local Vivado results, hardware documents, and old caches.
- Never use `reset --hard`, `clean -fd`, force checkout/switch, automatic stash, bulk overwrite, or automatic cleanup.
- Start from the merged Step 7C design on `origin/main`. Use a normal feature branch in the original working directory only when Git reports it is safe.
- Main integration model is `simulink模型/PMLSM_ThreeLoop_Simple.slx`.
- No position or speed lock. No soft/hard travel limit. The mechanical plant must move naturally.
- Step 7C controls only the inner current loop. Do not enable the legacy speed/position loops as the FPGA reference source.
- `PI_PROFILE=0` stays frozen. Do not retune C1–C4 or PI to make the waveforms look better.
- FPGA plant boundary remains `D_high = CMP_active / 2500`.
- FPGA backend must bypass legacy `PWM_Update_HalfTs` and legacy count/polarity conversion.
- Legacy backend must retain the old count/update path and remain a useful reference.
- Use one shared deadtime/average-inverter core and one shared plant. Do not duplicate the inverter or motor model.
- Plant-side deadtime is modeled only by Simulink. Do not feed Step 6E six-gate/deadtime waveforms into the average plant.
- Reference dynamic timing is: 20 ns HDL clock, 100 us PWM/current transaction, 1 us Simulink↔HDL communication, 1 us plant step, 200 ns XSI reset, zero prerun, physical time 1:1.
- `Ts_ACR` remains 100 us. A 1 us plant/communication step must not change controller sampling to 1 us.
- Legacy backend must run from the project root without calling `hdlsetuptoolpath` or changing into an XSI runtime directory.
- No bitstream, FPGA board, FIL, Vitis, PS/AXI, JMAG/Maxwell, real ADC/encoder, or Step 7D.
- Do not commit `.slxc`, `slprj`, `.Xil`, `xsim.dir`, DLLs, WDB, generated Vivado caches, system TEMP contents, or MATLAB cache files.
- Finish with an open implementation PR; do not merge and do not begin Step 7D.

## Review Focus

1. **Legacy behavior changes while extracting the normalized-duty boundary.** Task 1 captures a pre-edit numeric baseline; Task 2 must reproduce it with backend 0 before any FPGA plant takeover is accepted.
2. **The FPGA backend accidentally passes through the old half-period delay or count inversion.** Task 2 structurally proves the FPGA path reaches normalized `D_high` directly; Task 4 checks actuation timing and polarity dynamically.
3. **The 1 us setting changes only Simulink FixedStep but leaves HDL block PortTimes or plant integrators at 50 us.** Task 3 reads back every effective timing field and asserts `Ts_ACR=100 us` separately.
4. **Legacy mode still initializes XSI even when FPGA is not selected.** Task 2 must compile and short-run backend 0 from the project root without HDL setup/runtime-directory preparation.
5. **A moving motor appears stable only because the HDL still sees smoke inputs or fixed theta/we.** Task 4 logs plant feedback at the FPGA adapter and proves ia/ib/ic/theta/we change and are used while accepted/active command IDs advance.

---

## File Map

### Expected new files

```text
scripts/step7c_capture_legacy_baseline.m
scripts/step7c_refactor_backend.m
scripts/step7c_generate_foc_cosim.m
scripts/step7c_refresh_foc_block.m
scripts/step7c_run_dynamic.m
scripts/step7c_run_scenario.m
scripts/step7c_compare_convergence.m
scripts/step7c_acceptance.m
scripts/step7c_check_structure.m

simulink模型/init_PMLSM_step7c_params.m

coordination/reports/step7c_codex_report.md

docs/reports/step7c/README.md
docs/reports/step7c/legacy_before.txt
docs/reports/step7c/legacy_after.txt
docs/reports/step7c/legacy_compare.txt
docs/reports/step7c/structure_after.txt
docs/reports/step7c/timing_1us.txt
docs/reports/step7c/dynamic_ideal.txt
docs/reports/step7c/dynamic_deadtime.txt
docs/reports/step7c/dynamic_stop.txt
docs/reports/step7c/convergence_1us_vs_0p5us.txt
docs/reports/step7c/regression_summary.txt
docs/reports/step7c/acceptance_console.txt
```

Optional review artifacts may include small CSV/PNG exports under `docs/reports/step7c/` if generated directly from the accepted runs.

### Expected modified files

```text
simulink模型/PMLSM_ThreeLoop_Simple.slx
simulink模型/init_PMLSM_fpga_cosim_params.m
coordination/HANDOFF.md
```

### Files expected to remain unchanged

```text
motor_control_ip/foc/rtl/*
motor_control_ip/pwm/rtl/*
motor_control_ip/integration/rtl/mc_foc_pwm_top.sv
motor_control_ip/integration/rtl/mc_foc_cosim_top.sv
motor_control_ip/integration/rtl/mc_foc_gate_top.sv
```

If a new RTL monitor output appears necessary, stop and report the exact missing observation before changing RTL; do not silently expand Step 7C scope.

---

## Task 1: Freeze the current legacy Simple-model behavior before structural edits

**Files:**
- Create: `scripts/step7c_capture_legacy_baseline.m`
- Create: `docs/reports/step7c/legacy_before.txt`

**Interfaces:**
- Consumes: merged Step 7B model on main.
- Produces: deterministic pre-change legacy traces/metrics against which the post-refactor backend-0 model is compared.

- [ ] **Step 1: Verify repository state and create the implementation branch safely**

Run:

```bat
cd /d D:\Project\FPGA_XC7A200T
git rev-parse --show-toplevel
git remote -v
git branch --show-current
git status --short
git fetch origin
git rev-parse origin/main
git log -1 --oneline origin/main
```

Expected `origin/main` contains the merged Step 7C design and `PMLSM_ThreeLoop_Simple.slx` from Step 7B.

Preserve every unrelated local change. If a normal switch would overwrite user files, stop and report.

When safe:

```bat
git switch main
git pull --ff-only origin main
git switch -c step7c-dynamic-current-loop-cosim
```

Do not reset an existing branch with the same name; inspect it first.

- [ ] **Step 2: Create a reusable in-memory legacy logger**

Create `scripts/step7c_capture_legacy_baseline.m`.

The script must:
1. load `PMLSM_ThreeLoop_Simple` with all models closed;
2. refuse to save the model;
3. add temporary `To Workspace` sinks **in memory only** for:
   - `Control_Task_10kHz` outputs 1–3: legacy CMP counts;
   - `Inverter_DeadTime` outputs 1–2: vd/vq;
   - `PMLSM_Plant_Model` outputs 1–9: id, iq, ia, ib, ic, x_mm, v_mmps, theta_e, omega_e;
   - `Inverter_DeadTime/PWM_Update_HalfTs` outputs 1–3: delayed legacy command counts;
4. close the model with `close_system(mdl,0)` after simulation.

Use a helper with this pattern:

```matlab
function addTap(parent,srcPortHandle,name,varName,pos)
    add_block('simulink/Sinks/To Workspace',[parent '/' name], ...
        'VariableName',varName,'SaveFormat','Timeseries','Position',pos);
    dst=get_param([parent '/' name],'PortHandles');
    add_line(parent,srcPortHandle,dst.Inport,'autorouting','on');
end
```

Do not save the temporary sinks into the SLX.

- [ ] **Step 3: Define one deterministic legacy test scenario**

Use `Simulink.SimulationInput` with the model's current saved solver and original plant step.

Set the current-test scenario in model workspace/base parameters without editing the SLX:

```matlab
Host_Enable_Schedule = [0 1 0 1]; % close loop on, position loop off, PWM on
Host_Iq_Test_Mode = 1;
Host_Id_A = 0;
Host_Iq_A = 0.2;
Host_Load_N = 0;
StopTime = 5e-3;
```

Keep the current legacy controller and existing deadtime/update path exactly as main provides them.

If R2026b requires model-workspace targeting, use:

```matlab
si = si.setVariable('Host_Iq_Test_Mode',1,'Workspace',mdl);
```

and the same form for the other model-workspace variables.

- [ ] **Step 4: Write the pre-change baseline**

Write `docs/reports/step7c/legacy_before.txt` with:
- actual model solver and effective fixed step;
- the exact overrides above;
- sampled traces at a deterministic grid, preferably every 50 us;
- maximum/minimum/final values for CMP A/B/C, vd/vq, id/iq, ia/ib/ic, x, v, theta, omega;
- a final marker:

```text
STEP7C_LEGACY_BASELINE_CAPTURE_PASS
```

Also record:

```text
MODEL_SAVED=0
XSI_SETUP_CALLED=0
```

- [ ] **Step 5: Commit the baseline evidence before modifying the model**

```bat
git add scripts/step7c_capture_legacy_baseline.m docs/reports/step7c/legacy_before.txt
git diff --cached --check
git commit -m "test: capture Step 7C legacy baseline"
```

**Task 1 deliverable:** the old Simple controller/inverter/plant behavior has a numeric comparison point before command-path refactoring.

---

## Task 2: Refactor the inverter command boundary and add static backend selection without changing legacy behavior

**Files:**
- Create: `scripts/step7c_refactor_backend.m`
- Create: `scripts/step7c_check_structure.m`
- Create: `simulink模型/init_PMLSM_step7c_params.m`
- Modify: `simulink模型/PMLSM_ThreeLoop_Simple.slx`
- Modify: `simulink模型/init_PMLSM_fpga_cosim_params.m`
- Create: `docs/reports/step7c/structure_after.txt`
- Create: `docs/reports/step7c/legacy_after.txt`
- Create: `docs/reports/step7c/legacy_compare.txt`

**Interfaces:**
- Consumes: Step 7B `FPGA_HDL_Cosim` and existing `Inverter_DeadTime`.
- Produces: one common normalized-duty/deadtime/average-voltage path selected statically by `CONTROL_BACKEND`.

- [ ] **Step 1: Add Step 7C control parameters**

Create `simulink模型/init_PMLSM_step7c_params.m`:

```matlab
% Step 7C backend and dynamic-current-loop defaults.
CONTROL_BACKEND = 0;      % 0=legacy Simulink, 1=FPGA HDL
FPGA_Reference_Mode = 0;  % 0=scripted current profile, 1=future outer-loop/host

STEP7C_Comm_Ts_s = 1e-6;
STEP7C_Convergence_Ts_s = 0.5e-6;
STEP7C_StopTime_s = 31e-3;

STEP7C_Id_Ref_A = 0;
STEP7C_Iq_Profile_Time_s = [0 1e-3 11e-3 16e-3 26e-3 31e-3]';
STEP7C_Iq_Profile_A      = [0 0.5    0      -0.5   0      0]';

STEP7C_Vdc_V = 48;
STEP7C_Load_N = 0;
STEP7C_PI_PROFILE = 0;
```

Modify `init_PMLSM_fpga_cosim_params.m` only to call the Step 7C defaults after its existing Step 7B constants:

```matlab
init_PMLSM_step7c_params;
```

Keep all existing fixed-point widths and Step 7B smoke constants.

- [ ] **Step 2: Create explicit static variant controls**

In `init_PMLSM_step7c_params.m` also define:

```matlab
V_Backend_Legacy = Simulink.Variant('CONTROL_BACKEND == 0');
V_Backend_FPGA   = Simulink.Variant('CONTROL_BACKEND == 1');
```

Use these or equivalent R2026b-supported expressions in the model. Do not implement backend selection with a tunable runtime Switch.

- [ ] **Step 3: Inspect the existing inverter internals before mutation**

`step7c_refactor_backend.m` must assert these current Step 7B paths exist:

```text
PMLSM_ThreeLoop_Simple/Inverter_DeadTime
PMLSM_ThreeLoop_Simple/Inverter_DeadTime/PWM_Update_HalfTs
PMLSM_ThreeLoop_Simple/Inverter_DeadTime/DeadTime_Voltage_Model
PMLSM_ThreeLoop_Simple/FPGA_HDL_Cosim
```

Inside `DeadTime_Voltage_Model` identify its three phase duty/count front ends by actual block path and confirm each currently performs the equivalent of:

```text
D_high = saturate(1 - count / PMLSM_pwm_period_counts, 0, 1)
```

If the actual current model does not have this structure, stop and report the observed block paths instead of editing a guessed topology.

- [ ] **Step 4: Extract the legacy count-to-duty conversion ahead of the shared deadtime core**

Programmatically add:

```text
PMLSM_ThreeLoop_Simple/Inverter_DeadTime/Legacy_Counts_To_Duty
```

Inputs: delayed count A/B/C.  
Outputs: legacy `D_high_A/B/C`.

For each phase implement exactly:

```text
d = 1 - count / PMLSM_pwm_period_counts
D_high = saturate(d,0,1)
```

Reuse the original blocks/equation semantics where possible; do not change rounding or endpoint saturation.

Remove only the now-duplicated count→duty conversion from the three deadtime phase paths and make `DeadTime_Voltage_Model` accept normalized duties on inputs 1–3.

Do **not** change:
- deadtime current sign logic;
- vdc use;
- abc/dq voltage reconstruction;
- PWM enable multiplication;
- plant connections.

- [ ] **Step 5: Add FPGA duty/enable ports to the inverter front end**

Add four new `Inverter_DeadTime` inports after the existing nine:

```text
10 fpga_duty_u
11 fpga_duty_v
12 fpga_duty_w
13 fpga_bridge_enable
```

Inside, add static Variant Source/Variant selection so:

```text
CONTROL_BACKEND==0:
    selected duty = Legacy_Counts_To_Duty output
    selected enable = existing PWM_EN

CONTROL_BACKEND==1:
    selected duty = fpga_duty_u/v/w
    selected enable = fpga_bridge_enable
```

Selected duty goes directly into the common deadtime/voltage core.

No FPGA signal may pass through `PWM_Update_HalfTs`.

- [ ] **Step 6: Make the HDL block statically inactive in legacy mode**

Keep the root path `PMLSM_ThreeLoop_Simple/FPGA_HDL_Cosim` recognizable, but put its actual `HDL_Cosimulation` execution path behind a static variant controlled by `CONTROL_BACKEND==1`.

One accepted structure is:

```text
FPGA_HDL_Cosim
  ├─ FPGA_Input_Adapter
  ├─ HDL_Backend_Variant
  │   ├─ FPGA_Enabled    [CONTROL_BACKEND==1]
  │   │    └─ HDL_Cosimulation
  │   └─ FPGA_Disabled   [CONTROL_BACKEND==0]
  │        └─ zero/status constants
  ├─ FPGA_Output_Adapter
  └─ FPGA_Cosim_Monitor
```

The disabled choice must expose the same eight HDL result ports with zeros/false.

This keeps legacy compile/run from requiring the XSI block.

- [ ] **Step 7: Expose the four FPGA actuation outputs from `FPGA_HDL_Cosim`**

Add subsystem outputs:

```text
1  fpga_duty_u
2  fpga_duty_v
3  fpga_duty_w
4  fpga_bridge_enable
5  cmp_u_active
6  cmp_v_active
7  cmp_w_active
8  accepted_sample_id
9  active_command_id
10 active_valid
11 fault_code
12 needs_reset
```

Only outputs 1–4 may connect to the shared inverter. Outputs 5–12 are monitor/status only.

Use existing output-adapter duties:

```text
duty = double(CMP_active) / FPGA_TBPRD
```

with an interface guard Saturation block [0,1].

Define:

```text
fpga_bridge_enable =
    PWM_EN
    && active_valid
    && !needs_reset
    && (fault_code == 0)
```

At root, connect these four signals only to new `Inverter_DeadTime` ports 10–13.

- [ ] **Step 8: Prove the FPGA path bypasses both legacy layers structurally**

Create `scripts/step7c_check_structure.m` that writes `structure_after.txt` and asserts:

```text
FPGA_DUTY_SOURCE = FPGA_HDL_Cosim outputs
FPGA_TO_PWM_UPDATE_HALFTS_PATH = 0
FPGA_TO_LEGACY_COUNT_MAPPING_PATH = 0
ONE_DEADTIME_VOLTAGE_MODEL = 1
ONE_PMLSM_PLANT_MODEL = 1
```

Also print actual source/destination block paths for the selected-duty and selected-enable inputs.

- [ ] **Step 9: Re-run the Task 1 legacy scenario with backend 0**

Run from project root, without:
- `hdlsetuptoolpath`;
- `cd .Xil/...`;
- XSI generation.

Set:

```text
CONTROL_BACKEND=0
```

Write `legacy_after.txt` in the same grid/format as `legacy_before.txt`.

- [ ] **Step 10: Compare legacy before/after numerically**

Create comparison logic in the capture script or a helper.

For all common time samples compare:
- delayed counts A/B/C;
- vd/vq;
- id/iq;
- ia/ib/ic;
- x/v;
- theta/we.

Target:

```text
max_abs_difference <= 1e-10
```

If any field exceeds the target, report the exact signal and max difference before proceeding to FPGA takeover. Do not loosen the threshold silently.

Write:

```text
docs/reports/step7c/legacy_compare.txt
```

ending with:

```text
STEP7C_LEGACY_EQUIVALENCE_PASS
LEGACY_REQUIRES_XSI=0
```

- [ ] **Step 11: Commit Task 2**

```bat
git add scripts/step7c_refactor_backend.m ^
        scripts/step7c_check_structure.m ^
        "simulink模型/PMLSM_ThreeLoop_Simple.slx" ^
        "simulink模型/init_PMLSM_step7c_params.m" ^
        "simulink模型/init_PMLSM_fpga_cosim_params.m" ^
        docs/reports/step7c/structure_after.txt ^
        docs/reports/step7c/legacy_after.txt ^
        docs/reports/step7c/legacy_compare.txt
git diff --cached --check
git commit -m "simulink: add static controller backend boundary"
```

**Task 2 deliverable:** backend 0 is numerically unchanged and independent of XSI; backend 1 has a direct normalized-duty route to the single shared deadtime/inverter core.

---

## Task 3: Parameterize the HDL Cosimulation block for 1 us dynamic exchange and direct current-test references

**Files:**
- Create: `scripts/step7c_generate_foc_cosim.m`
- Create: `scripts/step7c_refresh_foc_block.m`
- Modify: `simulink模型/PMLSM_ThreeLoop_Simple.slx`
- Create/update: `simulink模型/init_PMLSM_step7c_params.m`
- Create: `docs/reports/step7c/timing_1us.txt`

**Interfaces:**
- Consumes: existing `mc_foc_cosim_top` unchanged.
- Produces: FPGA backend that consumes live plant feedback at 1 us communication and scripted id/iq references while RTL still accepts one transaction per 100 us carrier period.

- [ ] **Step 1: Create a Step 7C generator without destroying the Step 7B script**

Copy the proven source-list/R2026b `pi_reset` metadata workaround from `step7b_generate_foc_cosim.m` into `scripts/step7c_generate_foc_cosim.m`.

Use:

```matlab
function step7c_generate_foc_cosim(commTs,rebuild)
if nargin < 1, commTs = 1e-6; end
if nargin < 2, rebuild = true; end
assert(any(abs(commTs-[1e-6 0.5e-6]) < eps), ...
    'Step 7C generator accepts only 1 us or 0.5 us reference/probe rates');
```

Use work directory:

```text
.Xil/step7c_foc_cosim
```

Keep:
- clock 20 ns;
- reset 200 ns;
- physical timescale 1 s:1 s;
- prerun 0;
- unchanged RTL source list and ROM.

Set all eight HDL output sample times and final block `PortTimes` to `commTs` instead of a literal 50 us.

- [ ] **Step 2: Keep the ROM staging behavior**

Before generation/runtime, copy:

```text
motor_control_ip/foc/rom/sin_qw_4096x18.mem
```

to the actual Step 7C XSI work/runtime locations using the same non-Git mechanism proven in Step 7B.

Do not change ROM contents.

- [ ] **Step 3: Add direct Step 7C current references to the FPGA input adapter**

Inside `FPGA_Input_Adapter` retain:

```text
FPGA_Cosim_Input_Mode=0 → Step 7B fixed smoke inputs
FPGA_Cosim_Input_Mode=1 → live plant feedback
```

For `FPGA_Cosim_Input_Mode=1`:

- ia/ib/ic/theta/we/vdc come from existing live plant/model tags;
- `run_enable` comes from live PWM enable AND the Step 7C scripted run gate;
- `pi_reset` remains explicit;
- `uq_zero_en=0` for accepted dynamic runs.

For id/iq references insert a separate selector:

```text
FPGA_Reference_Mode=0:
    id_ref = STEP7C scripted reference
    iq_ref = STEP7C scripted reference

FPGA_Reference_Mode=1:
    id_ref = live id_cmd
    iq_ref = live iq_cmd
```

Step 7C uses mode 0 only.

- [ ] **Step 4: Generate reference timeseries in a runner, not by GUI editing**

`step7c_run_scenario.m` (Task 4) will create:

```matlab
t = [0 1e-3 11e-3 16e-3 26e-3 31e-3]';
iq = [0 0.5 0 -0.5 0 0]';
STEP7C_iq_ref_ts = timeseries(iq,t);
STEP7C_id_ref_ts = timeseries(zeros(size(t)),t);
```

Configure the From Workspace source to use zero-order hold/interpolation disabled as appropriate for piecewise-constant current reference.

The model must not require manual Scope edits.

- [ ] **Step 5: Refresh the saved model with the 1 us HDL block**

Create `scripts/step7c_refresh_foc_block.m` based on the Step 7B refresh helper.

It must:
- load the newly generated Step 7C block;
- replace only UserData/mask/interface metadata in the **active FPGA variant choice**;
- preserve all Step 7C model wiring/layout;
- assert eight outputs, eleven data inputs, clock 20 ns, reset 200 ns;
- read back output `PortTimes=1e-6` before saving.

- [ ] **Step 6: Make plant step an explicit simulation override, not a controller-period rewrite**

For FPGA dynamic runs use targeted model-workspace overrides:

```matlab
si = si.setVariable('PMLSM_Ts_s',commTs,'Workspace',mdl);
si = si.setModelParameter('FixedStep',sprintf('%.17g',commTs));
```

and likewise target plant/deadtime variables to the model workspace when they are defined there.

Do not set:

```text
Ts
Ts_ACR
Ts_ASR
Ts_POS
```

to 1 us.

Every run must assert after model initialization:

```text
Ts_ACR == 100e-6
FPGA_CLK_Period_s == 20e-9
PMLSM_Ts_s == commTs
FixedStep == commTs
HDL output PortTimes == commTs
```

- [ ] **Step 7: Run a 1 us timing-only dynamic setup before closing the plant loop**

Use live feedback/input mode but hold iq/id refs at zero and run for about 0.5 ms.

Record:
- communication timestamps;
- accepted ID transitions;
- active ID transitions;
- first visible nonzero/valid command time;
- expected carrier relation.

Require:
- accepted IDs advance every 100 us after startup;
- active IDs advance once per accepted sample;
- observed active duty becomes available no more than 1 us after the corresponding internal load window inferred from the accepted timing;
- fault=0;
- needs_reset=0.

Write `docs/reports/step7c/timing_1us.txt` ending:

```text
STEP7C_1US_TIMING_PASS
```

Do not hard-code 100.20/101.00 us as exact pass times; log the actual result.

- [ ] **Step 8: Commit Task 3**

```bat
git add scripts/step7c_generate_foc_cosim.m ^
        scripts/step7c_refresh_foc_block.m ^
        "simulink模型/PMLSM_ThreeLoop_Simple.slx" ^
        "simulink模型/init_PMLSM_step7c_params.m" ^
        docs/reports/step7c/timing_1us.txt
git diff --cached --check
git commit -m "simulink: configure 1us FPGA cosim timing"
```

**Task 3 deliverable:** the FPGA branch is statically selectable, uses 1 us exchange/plant timing, and still preserves a 100 us HDL current transaction period.

---

## Task 4: Close the first free-moving FPGA current loop with the ideal average inverter

**Files:**
- Create: `scripts/step7c_run_scenario.m`
- Create: `scripts/step7c_run_dynamic.m`
- Modify: `simulink模型/PMLSM_ThreeLoop_Simple.slx`
- Create: `docs/reports/step7c/dynamic_ideal.txt`

**Interfaces:**
- Consumes: backend 1, live plant feedback, direct Step 7C current references, normalized FPGA duty.
- Produces: first true FPGA↔motor dynamic current-loop evidence.

- [ ] **Step 1: Add a permanent non-driving Step 7C monitor**

Programmatically add one monitor subsystem at root:

```text
PMLSM_ThreeLoop_Simple/Step7C_Monitor
```

It must have **no outputs to the control/plant path**.

Log at minimum:

```text
1  id_ref
2  iq_ref
3  id_plant
4  iq_plant
5  ia
6  ib
7  ic
8  x_mm
9  v_mmps
10 theta_e
11 omega_e
12 cmp_u_active
13 cmp_v_active
14 cmp_w_active
15 duty_u
16 duty_v
17 duty_w
18 accepted_sample_id
19 active_command_id
20 active_valid
21 fpga_bridge_enable
22 fault_code
23 needs_reset
24 inverter_vd
25 inverter_vq
```

Source FPGA status/CMP values from `FPGA_HDL_Cosim` monitor outputs 5–12 added in Task 2; source only duty/bridge outputs 1–4 into the inverter. Use a Mux of double-converted values and one `To Workspace` named:

```text
step7c_monitor
```

Keep the existing Step 7B `fpga_monitor` for fixed-point range flags.

- [ ] **Step 2: Implement a single scenario runner**

Create:

```matlab
function result = step7c_run_scenario(name,commTs)
```

Supported names:

```text
legacy
ideal
deadtime
stop
convergence
```

For `legacy`, set `CONTROL_BACKEND=0`, do not call `hdlsetuptoolpath`, do not change into `.Xil`, and run the same short deterministic legacy scenario used by Task 1. This provides the final reproduction entry point for the XSI-independent backend.

For `ideal` set:

```text
CONTROL_BACKEND=1
FPGA_Cosim_Enable=1
FPGA_Cosim_Input_Mode=1
FPGA_Reference_Mode=0
PI_PROFILE=0
PMLSM_deadtime_s=0
PMLSM_deadtime_ratio=0
PMLSM_Ts_s=commTs
FixedStep=commTs
StopTime=31e-3
vdc=48 V
load=0 N
```

Create the id/iq profile exactly from the spec.

- [ ] **Step 3: Assert the FPGA branch really uses moving-plant inputs**

During the ideal run, assert using logged signals:

```matlab
assert(max(abs(theta_e-theta_e(1))) > 1e-4, 'theta did not move');
assert(max(abs(omega_e)) > 1e-3, 'omega_e stayed fixed');
assert(max(abs(ia-ia(1))) > 1e-3, 'phase current stayed fixed');
```

Also assert:
- accepted ID increases by many transactions across 31 ms;
- active ID tracks accepted transactions;
- range flags are zero;
- fault and needs-reset remain zero.

This prevents a false PASS using Step 7B smoke inputs.

- [ ] **Step 4: Check control direction before performance metrics**

Using the +0.5 A interval and -0.5 A interval:

```matlab
pos = t>=1e-3 & t<11e-3;
neg = t>=16e-3 & t<26e-3;

assert(max(iq(pos)) >= 0.25);
assert(min(iq(neg)) <= -0.25);
assert(max(abs(id)) < 0.5);
assert(max(abs(iq)) < 2.0);
```

Check finite values:

```matlab
assert(all(isfinite([id iq x v theta_e omega_e]),'all'));
```

- [ ] **Step 5: Prove the motor moves in the expected force direction**

Do not merely check final position sign.

Compute approximate acceleration from velocity over windows inside the positive and negative q pulses, away from switching boundaries:

```text
positive window: 3–9 ms
negative window: 18–24 ms
```

Require:

```text
mean dv/dt in positive window > 0
mean dv/dt in negative window < 0
```

Record peak speed, final speed and final position.

- [ ] **Step 6: Prove duty actually reaches the plant without the old extra delay**

Compare each change in `active_command_id` with the first subsequent change in inverter vd/vq or selected duty.

At 1 us communication require the selected FPGA duty/bridge state applied by the shared inverter no later than one communication interval after it becomes visible to Simulink.

Also assert the FPGA selected path never traverses `PWM_Update_HalfTs` using the Task 2 structural report.

- [ ] **Step 7: Write dynamic ideal evidence**

Write `dynamic_ideal.txt` with:
- scenario parameters;
- timing;
- id/iq min/max and tracking metrics;
- theta/we range;
- x/v range;
- accepted/active counts;
- duty/CMP range;
- bridge enable;
- fault/reset/range flags;
- positive/negative acceleration estimates;
- Step 7C marker:

```text
STEP7C_DYNAMIC_IDEAL_PASS
```

- [ ] **Step 8: Commit Task 4**

```bat
git add scripts/step7c_run_scenario.m ^
        scripts/step7c_run_dynamic.m ^
        "simulink模型/PMLSM_ThreeLoop_Simple.slx" ^
        docs/reports/step7c/dynamic_ideal.txt
git diff --cached --check
git commit -m "test: close free-moving FPGA current loop"
```

**Task 4 deliverable:** current references alter real motor current and motion through the HDL→active-CMP→shared-inverter→plant→HDL feedback loop.

---

## Task 5: Run deadtime and stop scenarios on the same closed loop

**Files:**
- Modify: `scripts/step7c_run_scenario.m`
- Create: `docs/reports/step7c/dynamic_deadtime.txt`
- Create: `docs/reports/step7c/dynamic_stop.txt`

**Interfaces:**
- Consumes: accepted ideal free-motion loop.
- Produces: evidence that average deadtime is applied once and stop invalidates plant actuation.

- [ ] **Step 1: Run Scenario B with exactly 1 us average deadtime**

Set together:

```text
PMLSM_deadtime_s = 1e-6
PMLSM_deadtime_ratio = PMLSM_deadtime_s / Ts = 0.01
```

Do not modify RTL deadtime.

Keep all other dynamic parameters identical to Scenario A.

- [ ] **Step 2: Apply the same stability/safety assertions**

Require:
- fault=0;
- needs_reset=0;
- range flags=0;
- all signals finite;
- `|id|<0.5 A`;
- `|iq|<2.0 A`;
- iq reaches at least +0.25 and -0.25 A in corresponding windows;
- motor moves and changes acceleration direction.

- [ ] **Step 3: Compare deadtime on/off without demanding equality**

Report:
- q tracking RMS error during positive/negative plateaus;
- max |id|;
- peak |v|;
- final x;
- min/max active duties.

Write `dynamic_deadtime.txt` ending:

```text
STEP7C_DYNAMIC_DEADTIME_PASS
```

No test should require the deadtime and ideal traces to match.

- [ ] **Step 4: Run Scenario C stop during motion**

Use the ideal-inverter case, but define a Step 7C scripted run gate:

```text
run gate = 1 from start through 8 ms
run gate = 0 from 8 ms onward
```

The stop occurs during the positive-current interval when velocity and theta are nonzero.

`run_enable` must be:

```text
live PWM_EN && scripted_run_gate
```

- [ ] **Step 5: Assert stop semantics**

After stop:
- `active_valid==0`;
- `fpga_bridge_enable==0`;
- shared inverter uses disabled behavior;
- old CMP values may remain visible, but selected plant duty is not enabled;
- no NaN/Inf;
- no auto restart is required;
- `needs_reset` may assert according to existing 6D stop contract and must be reported, not hidden.

Write `dynamic_stop.txt` ending:

```text
STEP7C_DYNAMIC_STOP_PASS
```

- [ ] **Step 6: Commit Task 5**

```bat
git add scripts/step7c_run_scenario.m ^
        docs/reports/step7c/dynamic_deadtime.txt ^
        docs/reports/step7c/dynamic_stop.txt
git diff --cached --check
git commit -m "test: add deadtime and dynamic stop scenarios"
```

**Task 5 deliverable:** plant-side deadtime works as one abstraction layer and disabling the FPGA backend prevents stale commands from remaining enabled.

---

## Task 6: Verify 1 us numerical convergence against a 0.5 us short reference

**Files:**
- Create: `scripts/step7c_compare_convergence.m`
- Create: `docs/reports/step7c/convergence_1us_vs_0p5us.txt`

**Interfaces:**
- Consumes: Scenario A runner and parameterized HDL block PortTimes.
- Produces: evidence that 1 us is an adequate Step 7C reference step.

- [ ] **Step 1: Use a short common convergence horizon**

Use Scenario A only and run to:

```text
12 ms
```

This covers:
- initial zero-current period;
- full +0.5 A pulse;
- first 1 ms after returning to zero.

Run once with:

```text
commTs = plant step = 1 us
```

and once with:

```text
commTs = plant step = 0.5 us
```

Before each run set the HDL block `PortTimes` in memory to the same `commTs` and close without saving transient 0.5 us metadata.

- [ ] **Step 2: Compare at common 1 us timestamps**

The 0.5 us trace contains every 1 us timestamp. Select common samples rather than interpolating when possible.

Compute:

```text
max |iq_1us - iq_0.5us|
max |id_1us - id_0.5us|
max |v_1us - v_0.5us|
max |x_1us - x_0.5us|
```

Require:

```text
< 0.05 A
< 0.05 A
< 2 mm/s
< 0.02 mm
```

- [ ] **Step 3: Also compare command scheduling**

Record accepted and active command counts for both rates.

The HDL transaction count over the same physical time must agree except for a possible startup observation-grid difference explicitly justified in the report.

Changing communication rate must not change the 100 us control transaction period.

- [ ] **Step 4: Write convergence evidence**

Write `convergence_1us_vs_0p5us.txt` ending:

```text
STEP7C_CONVERGENCE_PASS
```

If the thresholds fail, stop and investigate timing/sample application before changing thresholds.

- [ ] **Step 5: Restore/save the 1 us reference block state**

After convergence testing, ensure the committed SLX and generation configuration return to:

```text
PortTimes = 1 us
PMLSM saved default CONTROL_BACKEND = 0
```

Do not commit a 0.5 us temporary block state.

- [ ] **Step 6: Commit Task 6**

```bat
git add scripts/step7c_compare_convergence.m ^
        docs/reports/step7c/convergence_1us_vs_0p5us.txt ^
        "simulink模型/PMLSM_ThreeLoop_Simple.slx"
git diff --cached --check
git commit -m "test: verify Step 7C timestep convergence"
```

**Task 6 deliverable:** 1 us communication/plant integration is quantitatively checked rather than assumed.

---

## Task 7: Final regression, documentation, GitHub synchronization, and open implementation PR

**Files:**
- Create: `scripts/step7c_acceptance.m`
- Create: `docs/reports/step7c/regression_summary.txt`
- Create: `docs/reports/step7c/acceptance_console.txt`
- Create: `docs/reports/step7c/README.md`
- Create: `coordination/reports/step7c_codex_report.md`
- Modify: `coordination/HANDOFF.md` only after all acceptance checks pass.

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: one reproducible Step 7C implementation PR and a clear Step 7D handoff boundary.

- [ ] **Step 1: Create one final acceptance driver**

`scripts/step7c_acceptance.m` must run fresh, in this order:

```text
1. Step 7C structure check
2. legacy backend run from project root with no HDL setup
3. legacy before/after comparison
4. Step 7B minimal Simulink HDL co-sim
5. Step 7B standalone wrapper XSim
6. Step 6D profile0 DEMO=0
7. Step 6E profile0 DEMO=0
8. Step 7C 1 us timing check
9. Step 7C ideal free-motion current loop
10. Step 7C 1 us average-deadtime current loop
11. Step 7C dynamic stop
12. 1 us vs 0.5 us convergence
```

If a Step 7B helper assumes 50 us model metadata that Step 7C intentionally changed, use the unchanged minimal model and XSim tests directly; do not rewrite history or fake its old timing marker.

- [ ] **Step 2: Re-run after the final model/script change**

No PASS result generated before the final SLX/script modification may be used as final evidence.

Capture console output to:

```text
docs/reports/step7c/acceptance_console.txt
```

Require final marker:

```text
STEP7C_FULL_ACCEPTANCE_PASS
```

- [ ] **Step 3: Check tracked files for generated/cache pollution**

Run:

```bat
git status --short
git diff --check
git ls-files ".Xil/*" "*xsim.dir*" "*.slxc" "simulink模型/slprj/*" "*.dll" "*.wdb"
```

No new Step 7C cache/binary output may be tracked.

- [ ] **Step 4: Write the regression summary**

`regression_summary.txt` must include actual numeric values for:
- legacy max differences;
- 1 us timing;
- ideal/deadtime iq and id bounds;
- motion/acceleration direction;
- final x/v;
- accepted/active command counts;
- stop state;
- convergence deltas;
- Step 7B minimal/wrapper and 6D/6E regression markers.

Do not write literal PASS values that were not parsed from the fresh run.

- [ ] **Step 5: Write reproduction instructions**

`docs/reports/step7c/README.md` must explain from a fresh checkout:

```matlab
cd('D:/Project/FPGA_XC7A200T');
addpath(fullfile(pwd,'scripts'));

% legacy only: no XSI generation required
step7c_run_scenario('legacy',1e-6);

% FPGA backend:
step7c_generate_foc_cosim(1e-6,true);
step7c_run_scenario('ideal',1e-6);
step7c_run_scenario('deadtime',1e-6);
step7c_run_scenario('stop',1e-6);
step7c_compare_convergence;
```

Use the actual final function signatures if they differ only because R2026b requires a syntax adjustment; document that exact adjustment.

- [ ] **Step 6: Write the Codex report**

Create `coordination/reports/step7c_codex_report.md` with:

```text
A. branch/main state and preserved user changes
B. pre-refactor legacy baseline
C. normalized duty boundary refactor
D. static backend/XSI isolation
E. Step 7C 1 us timing contract
F. live plant feedback sources and fixed-point adapters
G. dynamic ideal free-motion result
H. average 1 us deadtime result
I. dynamic stop result
J. 1 us vs 0.5 us convergence
K. 6D/6E/7B regressions
L. limitations / no speed-position loop / no hardware
M. exact Step 7D entry point
```

Explicitly state:
- motor was free-moving;
- no travel clamp was added;
- no FPGA PI retuning was used;
- no gate-level deadtime was double-counted;
- no legacy PWM update delay was used on the FPGA path.

- [ ] **Step 7: Update HANDOFF only after acceptance**

Mark Step 7B accepted and Step 7C implementation complete/awaiting Review.

Record:
- static `CONTROL_BACKEND` semantics;
- normalized active-duty interface;
- 1 us reference timing;
- dynamic current profile;
- deadtime ownership;
- convergence numbers;
- Step 7D will restore outer loops, not redefine the current-loop boundary.

- [ ] **Step 8: Push and open the implementation PR**

Verify:

```bat
git status --short
git log --oneline --decorate -10
git diff origin/main...HEAD --stat
git diff --check
```

Push:

```bat
git push -u origin step7c-dynamic-current-loop-cosim
```

Open:

```text
PR title:
Step 7C: Close dynamic FPGA current loop with free-moving PMLSM
```

PR body must report:
- legacy backend numeric equivalence;
- legacy mode without XSI setup;
- direct FPGA normalized-duty path;
- 1 us timing result;
- ideal/deadtime/stop dynamic results;
- convergence deltas;
- required 6D/6E/7B regressions;
- no speed/position loop;
- no hardware/bitstream/Step 7D.

- [ ] **Step 9: Stop for ChatGPT Review**

Return:
- PR URL;
- local model path;
- commands to run legacy and FPGA scenarios;
- report/README paths;
- any non-blocking limitations.

Do not merge the PR and do not begin Step 7D.

---

## Codex Start Prompt

After this task-document PR is merged, send this to the local Codex session:

```text
开始 Step 7C，严格按 executing-plans 顺序执行。

先读取：
coordination/HANDOFF.md
coordination/specs/step7c_dynamic_motor_current_loop_cosim_design.md
coordination/tasks/step7c_dynamic_motor_current_loop_cosim.md

只在：
D:/Project/FPGA_XC7A200T
工作。

先核对 Git 主工作树、origin/main 和所有本地 tracked/untracked 修改。
不要创建 worktree/额外 clone，不 stash，不 reset/clean，不覆盖或删除我的文件。

Step 7C 的目标是第一次让 FPGA HDL current loop 真正驱动自由运动的
PMLSM_ThreeLoop_Simple average inverter + motor plant。

非常重要：
1. 不锁定位置/速度，不增加行程限制。
2. 先抓取当前 legacy numeric baseline，再改 SLX。
3. CONTROL_BACKEND 必须是静态选择：
   0 = legacy Simulink，
   1 = FPGA HDL。
   legacy 模式必须能从项目根目录运行，不调用 HDL setup、不依赖 XSI runtime。
4. 只保留一套 inverter/deadtime 和一套 motor plant。
5. legacy 保留原 PWM_Update_HalfTs 和旧 count/polarity mapping。
6. FPGA backend 必须直接使用 CMP_active/2500，
   严禁再走旧 PWM delay、旧 count mapping 或旧 polarity inversion。
7. average deadtime 只由 Simulink 负责，不接 Step 6E gate deadtime。
8. FPGA live feedback 必须来自正在运动的 plant：
   ia/ib/ic/theta_e/omega_e。
9. Step 7C 直接使用 scripted id/iq current test；
   不接速度环和位置环。
10. PI_PROFILE=0，不先调 PI。

参考 timing：
HDL clock = 20 ns
current/PWM period = 100 us
Simulink-HDL communication = 1 us
plant step = 1 us
XSI reset = 200 ns
PreRunTime = 0
physical timescale = 1:1

控制周期 Ts_ACR 必须继续是 100 us，不能跟 plant step 变成 1 us。

默认自由运动 iq profile：
0-1 ms      0 A
1-11 ms    +0.5 A
11-16 ms    0 A
16-26 ms   -0.5 A
26-31 ms    0 A
id_ref=0，vdc=48 V，load=0 N。

按任务书完成：
- legacy before/after equivalence；
- static backend + normalized-duty refactor；
- 1 us HDL block timing；
- ideal inverter dynamic current loop；
- 1 us average deadtime dynamic loop；
- stop during motion；
- 1 us vs 0.5 us convergence；
- Step 7B minimal/wrapper、6D profile0、6E profile0必要回归。

如果第一次动态闭环发散，按任务书顺序检查：
duty polarity -> phase order -> theta -> we -> current signs ->
duplicate PWM delay -> duplicate deadtime -> communication timing -> PI。
不要第一反应就改 PI，也不要用换相/最终负号掩盖接口错误。

最终写：
coordination/reports/step7c_codex_report.md
docs/reports/step7c/

推送分支并创建：
Step 7C: Close dynamic FPGA current loop with free-moving PMLSM

停在开放 PR 等待 ChatGPT Review。
不要开始 Step 7D，不跑 bitstream，不操作硬件。
```
