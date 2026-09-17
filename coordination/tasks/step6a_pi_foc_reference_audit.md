# Step 6A — Basic PI FOC Simulink Reference Audit

## Purpose

Step 6A is a **read-only reference audit** before any new motor-control RTL is written.

The goal is to extract a small, standard PI current-loop golden reference from the existing Simulink/DSP project so later FPGA modules can be implemented and verified one-by-one against known behavior.

This task deliberately ignores the advanced research branches currently present in the simulation project (DPCC, DPICC, half-delay DPICC, PICDO-DPICC) and also ignores the complex startup/alignment, speed-loop, position-loop, mode-management, CCS interaction, and board commissioning logic except where they are required to understand the basic PI current loop interface.

The first FPGA current-loop baseline shall be:

```text
phase currents / electrical angle / current references
                    ↓
                 Clarke
                    ↓
                  Park
                    ↓
              Id / Iq PI
                    ↓
             dq voltage limiter
                    ↓
              Inverse Park
                    ↓
              Sector SVPWM
                    ↓
         Duty_A / Duty_B / Duty_C
```

The existing Simulink model is the **algorithm reference**, not a source to be automatically converted wholesale into RTL.

---

## Hard scope boundary

### In scope

Codex must identify and document the exact implementation used by the **basic PI current-loop path** for:

- Clarke transform;
- Park transform;
- electrical-angle convention;
- PI d-axis controller;
- PI q-axis controller;
- discrete integrator/state-update formula;
- PI reset behavior;
- anti-windup behavior used by the PI path;
- dq voltage limiter;
- inverse Park transform;
- existing sector-based SVPWM implementation;
- duty output definition and range;
- duty-to-ePWM compare relationship in the DSP implementation;
- PWM polarity and up/down counter convention;
- current-loop sample time and PWM frequency;
- current-loop execution/update timing relevant to the PI path.

### Explicitly out of scope

Do **not** analyze or implement these except for a brief note identifying where they exist:

- DPCC;
- DPICC;
- half-delay DPICC;
- PICDO-DPICC;
- observer research branches;
- speed loop;
- position loop;
- I/F startup;
- alignment state machine;
- automatic motion startup sequence;
- CCS/manual commissioning mode management;
- serial communication;
- full MBDL4 power-up sequence;
- HDL generation;
- new FPGA RTL;
- Vivado Block Design;
- CORDIC implementation;
- ADC9238 interface;
- dead-time implementation;
- complementary PWM implementation.

The report may mention these systems only to distinguish them from the basic PI FOC path.

---

## Reference files — required reading order

All reference files are under:

`simulink模型/`

### P0 — read first

1. `FPGA_Simulink_Model_Guide.md`

This is the navigation map. Respect the distinction between:

- MIL model;
- control-core model;
- DSP embedded/code-generation model;
- plant/test parameter layers.

Do not infer algorithm truth from file names alone.

### P1 — primary algorithm reference

2. `PMLSM_ControlCore_Block.slx`

This is the most important model for Step 6A.

Trace only the **PI current-control branch** (`Current_Control_Mode = 1`) and extract the exact equations and signal flow for:

```text
ia / ib / ic
→ Clarke
→ Park
→ id / iq
→ PI d/q
→ dq limiter
→ inverse Park
→ sector SVPWM
→ duty_a / duty_b / duty_c
```

Do not treat the currently selected MIL default DPCC mode as the Step 6A target.

### P1 — DSP real-hardware integration reference

3. `PMSLM_Close_Loop_MBDL4.slx`

Use this model only to identify the real DSP implementation details needed to interpret the PI current loop:

- ADC/current feedback entry point;
- current-loop interrupt or execution trigger;
- ePWM frequency and up/down mode;
- duty/ePWM compare mapping;
- PWM polarity;
- compare update timing;
- any PI reset signal affecting the current controller;
- any limiter or enable that directly changes the PI current-loop output.

Do not attempt to reproduce all MBDL4 startup and commissioning logic in Step 6A.

### P1 — real control parameter source

4. `PMSLM_Init_Params_MBDL4.m`

Extract and distinguish at least:

- `PWM_Freq`;
- `Ts_ACR`;
- `EPWM_Clock`;
- `TBCLK`;
- `PWM_Period`;
- `Kp_ACR_Baseline`;
- `Ki_ACR_Baseline`;
- `ACR_Commissioning_Scale`;
- `Kp_ACR`;
- `Ki_ACR`;
- `Kaw_d`;
- `Kaw_q`;
- voltage/current limits used by the PI path;
- motor `Rs`, `Ld`, `Lq`, flux values where they directly affect current-loop equations.

Do not silently mix baseline PI gains with commissioning-scaled gains.

### P2 — MIL environment/reference-vector source

5. `PMLSM_MIL_ControlCore_Sim.slx`

Read only enough to understand:

- where the control core receives currents and electrical angle;
- how duty outputs connect to the inverter/plant;
- which signals are logged and can be used as golden comparison points.

6. `init_PMLSM_mil_test_params.m`

Record the test-mode configuration, but for Step 6A explicitly select/describe the PI path:

`Current_Control_Mode = 1`

The existing default `Current_Control_Mode = 2` is DPCC and is **not** the target of this audit.

7. `init_PMLSM_plant_params.m`

Read only the plant parameters necessary to understand units/scaling and to construct later offline current-loop comparison tests.

8. `init_PMLSM_control_params.m`

Read only to confirm parameter loading order/source.

---

## SLX inspection method

### Preferred method — MATLAB available

If MATLAB/Simulink is available locally:

- use `load_system` / `find_system` / `get_param` or other read-only inspection APIs;
- inspect subsystem hierarchy, MATLAB Function blocks, mask parameters, Stateflow content, data stores, Unit Delay/Memory blocks, Saturation blocks, and referenced parameters;
- do **not** build C code;
- do **not** generate HDL;
- do **not** deploy hardware;
- do **not** save changes back to the `.slx` files.

If a short MATLAB script is useful for extracting block paths/parameters, it may be created under `scripts/reference_audit/`, but it must be read-only with respect to the Simulink models.

### Fallback — MATLAB unavailable

`.slx` files are ZIP containers. Inspect them read-only using their XML contents:

- `simulink/*.xml`;
- `simulink/systems/*.xml`;
- Stateflow XML;
- embedded MATLAB Function content if present.

Clearly mark any item that cannot be verified without MATLAB as **UNRESOLVED**, rather than guessing.

---

## Required audit results

Create:

`coordination/reports/step6a_pi_foc_reference_audit.md`

The report must contain the following sections.

### 1. Reference hierarchy

State which file is authoritative for each of:

- algorithm topology;
- real PI parameters;
- DSP PWM/ePWM behavior;
- MIL test environment;
- plant parameters.

### 2. PI-current-loop signal chain

Give exact block/subsystem paths for the PI path from phase current input to duty outputs.

At minimum document:

```text
ia, ib, ic
↓
Clarke
↓
i_alpha, i_beta
↓
Park(theta_e)
↓
id, iq
↓
id_ref / iq_ref
↓
D-axis PI / Q-axis PI
↓
ud_raw / uq_raw
↓
dq voltage limiter
↓
ud_lim / uq_lim
↓
Inverse Park(theta_e)
↓
V_alpha / V_beta
↓
SVPWM
↓
duty_a / duty_b / duty_c
```

### 3. Exact Clarke equations

Do not write a generic textbook Clarke transform unless the model actually uses it.

Record:

- exact equation;
- two-current or three-current form;
- normalization coefficient;
- phase sequence/sign convention;
- input/output units.

### 4. Exact Park / inverse-Park equations

Record:

- exact matrix/sign convention;
- meaning of positive `theta_e`;
- d/q axis orientation;
- whether Park and inverse Park use the same stored angle for one control transaction;
- angle units/scaling in Simulink.

### 5. PI discrete-time equations

This is a critical section.

For each d/q axis, identify the actual implemented discrete equations, not only block names.

Document:

- error definition;
- proportional term;
- integrator update equation;
- whether `Ki` already contains `Ts` or whether `Ts` is applied separately;
- Unit Delay/Memory state meaning;
- reset behavior;
- output saturation;
- anti-windup/back-calculation equation;
- order of saturation and integrator update;
- initial values.

If the d and q paths differ, document both.

### 6. dq voltage limiter

Document the exact limiter behavior used in the PI path:

- magnitude/axis limit formula;
- `Udc` relationship;
- saturation output values;
- anti-windup feedback values such as `du_d_z` / `du_q_z` if used;
- one-sample state/update semantics.

Do not infer these signals from their names; trace the actual model.

### 7. SVPWM implementation

For the existing sector-based SVPWM path, document exact subsystem/block paths and formulas for:

- sector calculation;
- X/Y/Z calculation;
- T1/T2 calculation;
- duty calculation;
- sector numbering convention;
- boundary behavior at sector edges;
- duty range and polarity;
- `Udc` normalization;
- output phase ordering.

The first FPGA implementation should reproduce this algorithm before any Min-Max/zero-sequence alternative is evaluated.

### 8. Duty → ePWM compare mapping

Trace the real DSP model and record:

- whether duty increases or decreases CMPA;
- exact formula or block chain;
- ePWM up/down mode;
- `TBPRD` convention;
- compare action/polarity if visible;
- compare shadow/load behavior if visible;
- ZERO/PRD update event if visible.

Important: the DSP reference uses a 100 MHz ePWM clock and a 10 kHz center-aligned PWM, while the current XC7A200T fabric clock is 50 MHz. Compare normalized duty behavior, not raw compare counts.

### 9. Timing contract

Document the PI reference timing as precisely as the files allow:

- PWM frequency;
- current-loop update frequency;
- current sample time;
- control execution trigger;
- compare update event;
- any intentional PWM update delay model;
- whether the MIL delay model differs from real DSP implementation.

Distinguish clearly between:

- FPGA fabric clock;
- PWM carrier period;
- current-loop control period;
- algorithm pipeline latency;
- PWM command load latency.

### 10. Step 6A minimal FPGA interface recommendation

Based only on the audited PI path, propose a future minimal FPGA current-core interface.

Do not implement it.

It should contain only what is required for a basic PI current loop, conceptually similar to:

Inputs:

- `ia`, `ib`, `ic` or the minimal compatible current set;
- `theta_e`;
- `id_ref`;
- `iq_ref`;
- `vdc`;
- `sample_valid` / transaction start;
- reset/enable.

Outputs:

- `cmp_u`, `cmp_v`, `cmp_w` or normalized duty commands;
- `command_valid`;
- useful observation points (`id`, `iq`, `ud`, `uq`, sector).

Do not include speed-loop or position-loop interfaces in this first current-core proposal.

### 11. Unresolved items

List anything that could not be established unambiguously.

Every unresolved item must include:

- exact file/block path involved;
- why it is unresolved;
- what evidence would resolve it.

Do not guess.

---

## Golden-reference vectors

If MATLAB/Simulink can be run safely without modifying source files, additionally create:

`coordination/reports/step6a_pi_foc_golden_vectors.csv`

Use the PI path only.

Capture a small deterministic set of vectors covering, where practical:

- zero currents / zero references;
- one d-axis current case;
- one q-axis current case;
- several electrical angles including quadrant boundaries;
- positive and negative current error;
- unsaturated PI output;
- saturated voltage-limiter case;
- representative SVPWM sectors including sector boundaries.

Preferred columns:

```text
case_id,
ia,ib,ic,
theta_e,
id_ref,iq_ref,vdc,
i_alpha,i_beta,
id,iq,
ud_raw,uq_raw,
ud_lim,uq_lim,
v_alpha,v_beta,
sector,
t1,t2,
duty_a,duty_b,duty_c
```

Do not fabricate values if the model cannot be executed. In that case, create only the audit report and explicitly mark golden-vector generation as not executed.

---

## Known baseline facts — do not rediscover incorrectly

From the current parameter/reference files:

- PWM target frequency: 10 kHz;
- basic current-loop sample time: `Ts_ACR = 100 us`;
- real DSP ePWM clock reference: 100 MHz;
- real DSP center-aligned `PWM_Period` reference: 5000 counts;
- XC7A200T learning board fabric clock: 50 MHz;
- a future equivalent 10 kHz up/down carrier on 50 MHz fabric will use a different raw period count than the DSP;
- the MIL test script currently defaults to DPCC (`Current_Control_Mode = 2`), but **Step 6A explicitly audits PI (`Current_Control_Mode = 1`)**;
- advanced DPCC/DPICC/PICDO branches are research references, not Step 6A implementation targets.

Do not mix MIL-overridden PI gains with real commissioning gains without labeling the source.

---

## Reference-file protection

The following files are read-only reference assets for this task:

- `simulink模型/*.slx`
- `simulink模型/*.m`
- `simulink模型/FPGA_Simulink_Model_Guide.md`

Do not rewrite, auto-format, save, regenerate, or modify them.

Do not create generated Simulink caches or commit `slprj`, `.slxc`, generated C, or HDL artifacts.

---

## Git workflow

Start from latest `main` after confirming the Simulink-reference upload is present.

Create branch:

`step6a-pi-foc-reference-audit`

Allowed changes are limited to:

- `coordination/reports/step6a_pi_foc_reference_audit.md`;
- optional `coordination/reports/step6a_pi_foc_golden_vectors.csv`;
- optional read-only extraction scripts under `scripts/reference_audit/`;
- a concise PR description.

Do not modify PWM RTL, Step 5 demos, XDC, board projects, or Simulink reference assets.

Suggested commit:

`docs: audit basic PI FOC Simulink reference`

Create PR:

`Step 6A: Audit basic PI FOC Simulink reference`

Stop at the open PR for ChatGPT review.

Do not implement Step 6B / motor PWM RTL or any FOC RTL in this task.

---

## Acceptance criteria

Step 6A is accepted only if the report makes it possible to answer, without guessing:

1. What exact Clarke/Park/inverse-Park equations does the existing model use?
2. What exact discrete PI and anti-windup equations does the basic PI path use?
3. What exact dq voltage limiter is used?
4. What exact SVPWM sector/T1/T2/duty implementation is used?
5. What do the duty outputs mean numerically and how do they map to DSP ePWM compare values?
6. What is the real 10 kHz current-loop/PWM timing contract?
7. Which parameters come from real DSP commissioning versus MIL test overrides?
8. What is the smallest clean interface for a future FPGA PI-current-loop core?
9. Which facts are still unresolved?

If any of these cannot be answered, report the missing evidence explicitly rather than replacing it with textbook assumptions.
