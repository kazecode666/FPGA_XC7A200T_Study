# ChatGPT ↔ Codex Project Handoff

This file is the persistent coordination index for the FPGA learning project. GitHub is the source of truth between ChatGPT (planning/review) and Codex (execution).

## Working agreement

- ChatGPT owns architecture, task definition, design decisions, acceptance criteria, and PR review.
- Codex owns local repository inspection, Simulink/reference inspection, RTL/testbench/Tcl/XDC edits when a task allows them, Vivado/MATLAB execution, report generation, commits, pushes, and PR creation.
- Do not rely on copied chat snippets when this file and the repository contain the current task.
- Do not use SHA-256/file-hash verification for this learning project. Use `git status`, `git diff`, reports, simulation, synthesis, implementation, timing, DRC, and hardware behavior instead.
- Do not guess board pins, I/O standards, clock frequencies, reset polarity, algorithm equations, data scaling, PWM polarity, or timing semantics. Hardware/algorithm facts must be traced to repository evidence and, where available, physical observation.
- Each implementation/audit task is done on a feature branch and stops at an open PR for ChatGPT review. Do not merge the task PR unless explicitly instructed.
- Codex writes its execution summary to `coordination/reports/<task>_codex_report.md` when required by the task.

## Accepted baseline

Completed and accepted:

- Step 1: self-checking PWM testbench.
- Step 2: compare-value semantics and boundary behavior.
- Step 2.5: registered PWM output aligned with counter state.
- Step 3: RTL synthesis baseline.
- Step 4: 50 MHz clock constraint, placement, routing, and post-route timing analysis.
- Step 5A: BX72 board-level LED blink bring-up.
- Step 5B: BX72 PWM breathing LED demo.

Step 5A physical verification is complete:

- PR #6 is merged into `main`.
- Vivado Hardware Manager physically detected `xc7a200t`.
- Step 5A bitstream programmed successfully.
- LED1 physically alternated approximately 0.5 s OFF / 0.5 s ON.
- Holding KEY2 physically forced LED1 OFF.
- Releasing KEY2 physically restarted the 1 Hz blink sequence.

Step 5B physical verification is complete:

- PR #7 is merged into `main`.
- Step 5B breathing-light bitstream programmed successfully.
- LED1 physically showed the intended repeated dark → bright → dark breathing behavior.
- Holding KEY2 physically forced LED1 OFF.
- Releasing KEY2 physically restarted the breathing sequence from the reset state.

These hardware observations are part of the accepted project baseline.

Additional reference assets now on `main`:

- `ACM9238-SCH.pdf` (PR #8 merged).
- `simulink模型/` reference package (PR #9 merged), including the PI/advanced-current-control Simulink models, MIL environment, DSP real-hardware model, parameter scripts, and `FPGA_Simulink_Model_Guide.md`.

## Frozen hardware facts

- Target learning-board part: `xc7a200tfbg484-2`.
- Physical JTAG detection: `xc7a200t`.
- Board clock: 50 MHz.
- `clk`: Y18, Bank 14, LVCMOS33.
- `key2_n`: V17, Bank 14, LVCMOS33, active LOW, external 4.7 kohm pull-up.
- `led1`: AA18, Bank 14, LVCMOS33, active HIGH.
- `CFGBVS = VCCO`.
- `CONFIG_VOLTAGE = 3.3`.

Do not re-guess or auto-assign these in later BX72 learning steps.

## Legacy learning PWM-core baseline

`pwm_controller` remains a verified learning core used by Steps 1–5. Do not silently turn it into the future motor-control PWM engine.

Definitions:

- `N = period_set`
- `C = compare_value_set`
- for `N > 0`, counter runs `0 ... N-1`
- `counter >= C` → PWM HIGH
- `counter < C` → PWM LOW
- `C = 0` → constant HIGH
- `C >= N` → constant LOW
- `N = 0` → disabled / LOW
- `HIGH duty = (N - C) / N`

Important: this learning core resets its counter when `config_en` is asserted. It is **not** the final motor-control PWM/shadow-compare architecture.

## Motor-control direction

The project now transitions from basic FPGA/PWM learning to a motor-control PL architecture intended to be portable later from XC7A200T to a Zynq UltraScale+ MPSoC PL.

The near-term baseline shall be a **basic PI FOC current loop**, not the research DPCC/DPICC/PICDO branches currently present in the Simulink project.

First golden algorithm chain:

```text
phase currents + electrical angle + id/iq references
                    ↓
                 Clarke
                    ↓
                  Park
                    ↓
              d/q PI control
                    ↓
             dq voltage limiter
                    ↓
              Inverse Park
                    ↓
          existing sector-based SVPWM
                    ↓
              three-phase duty/CMP
```

The advanced current-control branches, complex startup/alignment state machine, speed loop, position loop, and commissioning/mode-management logic remain valuable references but are intentionally deferred until the basic PI current-loop path is understood and reproduced.

Reference timing target inherited from the real DSP project:

- PWM switching frequency: 10 kHz.
- Basic current-loop period: `Ts_ACR = 100 us`.
- DSP ePWM reference clock: 100 MHz.
- DSP center-aligned raw period reference: 5000 counts.
- XC7A200T fabric clock: 50 MHz; raw FPGA period counts will differ even when normalized duty behavior is equivalent.

Do not compare raw DSP CMP counts directly to future FPGA CMP counts; compare normalized duty/polarity/timing semantics.

## Current task

**Step 6A — Basic PI FOC Simulink Reference Audit**

This is a **read-only audit task**. No new FOC/PWM/ADC RTL is to be implemented yet.

Governing specification:

`coordination/tasks/step6a_pi_foc_reference_audit.md`

Execution plan:

`coordination/tasks/step6a_pi_foc_reference_audit_plan.md`

Required reference entry point:

`simulink模型/FPGA_Simulink_Model_Guide.md`

Primary files to inspect after reading the guide:

1. `simulink模型/PMLSM_ControlCore_Block.slx` — primary PI-current-loop algorithm topology.
2. `simulink模型/PMSLM_Close_Loop_MBDL4.slx` — real DSP ADC/ePWM/integration timing reference.
3. `simulink模型/PMSLM_Init_Params_MBDL4.m` — real control parameters and PWM/current-loop timing.
4. `simulink模型/PMLSM_MIL_ControlCore_Sim.slx` — golden MIL environment/logging reference.
5. `simulink模型/init_PMLSM_mil_test_params.m` — MIL test mode/override reference.
6. `simulink模型/init_PMLSM_plant_params.m` — plant/scaling reference.
7. `simulink模型/init_PMLSM_control_params.m` — parameter-load entry reference.

Step 6A target is explicitly `Current_Control_Mode = 1` (PI).

The MIL script currently defaults to `Current_Control_Mode = 2` (DPCC); that default must not redirect the audit away from PI.

Step 6A must extract the exact existing behavior for:

- Clarke;
- Park / inverse Park;
- angle and sign conventions;
- discrete d/q PI equations;
- integrator and reset semantics;
- anti-windup;
- dq voltage limiting;
- sector-based SVPWM (Sector / XYZ / T1T2 / Duty);
- duty range/polarity/phase ordering;
- duty-to-DSP-ePWM mapping;
- 10 kHz current-loop/PWM timing contract;
- real DSP commissioning parameter values versus MIL overrides.

Reference files under `simulink模型/` are read-only for this task.

Primary deliverable:

`coordination/reports/step6a_pi_foc_reference_audit.md`

Optional, only if trustworthy MATLAB/Simulink execution is possible without modifying the references:

`coordination/reports/step6a_pi_foc_golden_vectors.csv`

Branch:

`step6a-pi-foc-reference-audit`

PR title:

`Step 6A: Audit basic PI FOC Simulink reference`

Codex must stop at the open PR. Do not implement Step 6B/motor PWM, CORDIC, Clarke/Park RTL, PI RTL, SVPWM RTL, ADC9238 interface, dead time, or power-stage output logic in Step 6A.

## Codex start command

```text
Read coordination/HANDOFF.md first.
Then read coordination/tasks/step6a_pi_foc_reference_audit.md and coordination/tasks/step6a_pi_foc_reference_audit_plan.md.
Execute Step 6A exactly as specified.
This is a read-only Simulink/FOC reference audit: target only the basic PI current-loop path (Current_Control_Mode = 1), do not implement RTL, do not modify any simulink模型 reference asset, and do not analyze DPCC/DPICC/PICDO in depth.
Create the required audit report (and golden-vector CSV only if it can be generated from trustworthy model execution), open the specified PR, and stop for ChatGPT review.
```
