# Step 6A PI FOC Reference Audit Execution Plan

> **For Codex:** Execute this plan as a read-only reference-audit task. The governing specification is `coordination/tasks/step6a_pi_foc_reference_audit.md`.

**Goal:** Extract an unambiguous basic PI-FOC golden reference from the existing Simulink/DSP project without modifying reference assets or implementing FPGA RTL.

**Architecture:** Treat `PMLSM_ControlCore_Block.slx` as the primary algorithm topology reference, `PMSLM_Init_Params_MBDL4.m` as the real-control parameter source, `PMSLM_Close_Loop_MBDL4.slx` as the DSP hardware-integration timing/polarity reference, and the MIL files as the validation/test-vector environment. Ignore DPCC/DPICC/PICDO and advanced startup/mode-management logic except where needed to disambiguate the PI path.

**Tech stack:** MATLAB/Simulink read-only inspection if available; otherwise SLX ZIP/XML static inspection. Markdown/CSV outputs only. No Vivado/RTL implementation in this task.

**Spec:** `coordination/tasks/step6a_pi_foc_reference_audit.md`

## Global constraints

- First FPGA current-loop baseline is PI only (`Current_Control_Mode = 1`).
- Do not modify any file under `simulink模型/`.
- Do not run code generation, HDL generation, hardware deployment, or DSP download.
- Do not implement Clarke/Park/PI/SVPWM RTL in this task.
- Do not treat MIL default DPCC (`Current_Control_Mode = 2`) as the target.
- Do not guess unresolved formulas, polarity, data ranges, or timing.
- Clearly distinguish real DSP commissioning parameters from MIL overrides.
- Use Git diff/status; do not perform SHA/hash verification.

---

### Task 1: Establish the reference map and branch

**Files:**
- Read: `simulink模型/FPGA_Simulink_Model_Guide.md`
- Read: `coordination/tasks/step6a_pi_foc_reference_audit.md`
- Create later: `coordination/reports/step6a_pi_foc_reference_audit.md`

- [ ] Confirm latest `main` contains the Simulink reference upload and merged Step 5B baseline.
- [ ] Create branch `step6a-pi-foc-reference-audit` from latest `main`.
- [ ] Read the full guide before opening any SLX.
- [ ] Record the authoritative file mapping for algorithm topology, real PI parameters, DSP PWM/ePWM behavior, MIL test environment, and plant parameters.
- [ ] Confirm `Current_Control_Mode = 1` is the only current-control branch to audit in depth.

Expected deliverable after this task: a short working note or report skeleton containing the reference hierarchy.

---

### Task 2: Extract the PI FOC topology from the control-core model

**Files:**
- Read-only: `simulink模型/PMLSM_ControlCore_Block.slx`

- [ ] Load the model read-only with MATLAB/Simulink if available; otherwise inspect SLX XML.
- [ ] Locate the full PI path from phase currents to duty outputs.
- [ ] Record exact subsystem/block paths for Clarke, Park, PI d-axis, PI q-axis, voltage limiter, inverse Park, SVPWM, and duty outputs.
- [ ] Identify the signal names connecting those blocks.
- [ ] Identify where the PI branch is selected and how advanced DPCC/DPICC branches are bypassed when PI is selected.
- [ ] Do not inspect advanced branches beyond what is necessary to prove the PI selection path.

Expected deliverable: exact block-path chain, not a generic textbook diagram.

---

### Task 3: Extract exact Clarke/Park/inverse-Park math and conventions

**Files:**
- Read-only: `simulink模型/PMLSM_ControlCore_Block.slx`

- [ ] Extract the exact Clarke equations implemented by the model.
- [ ] Determine whether the model uses 2-current or 3-current Clarke and document normalization constants.
- [ ] Extract the exact Park sign/matrix convention.
- [ ] Extract the exact inverse-Park sign/matrix convention.
- [ ] Determine the electrical angle unit/range and positive direction.
- [ ] Determine phase ordering and d/q orientation.
- [ ] Record any Unit Delay/Memory behavior that changes which control sample's angle is used.

Expected deliverable: equations copied/reconstructed from actual blocks, with source block paths and no textbook substitutions.

---

### Task 4: Extract exact PI and anti-windup equations

**Files:**
- Read-only: `simulink模型/PMLSM_ControlCore_Block.slx`
- Read-only: `simulink模型/PMSLM_Init_Params_MBDL4.m`

- [ ] Locate the d-axis and q-axis PI subsystems used in PI mode.
- [ ] Reconstruct the discrete-time equations exactly.
- [ ] Determine whether `Ki` is multiplied by `Ts` in the block or is already discretized elsewhere.
- [ ] Identify integrator state variables and Unit Delay/Memory semantics.
- [ ] Identify PI reset/hold behavior.
- [ ] Identify output saturation and anti-windup/back-calculation equations.
- [ ] Map the parameters `Kp_ACR`, `Ki_ACR`, `Kaw_d`, `Kaw_q` to the exact block inputs.
- [ ] Explicitly separate `Kp_ACR_Baseline` / `Ki_ACR_Baseline`, commissioning-scaled gains, and MIL overrides.

Expected deliverable: a d/q PI equation section precise enough for later RTL implementation and reference-model reproduction.

---

### Task 5: Extract the dq voltage limiter behavior

**Files:**
- Read-only: `simulink模型/PMLSM_ControlCore_Block.slx`
- Read-only: parameter scripts as needed

- [ ] Locate the dq limiter actually used by the PI path.
- [ ] Record the exact magnitude/axis limiting algorithm.
- [ ] Determine the role of `Udc` in the limit.
- [ ] Trace `ud_raw`, `uq_raw`, `ud_lim`, `uq_lim`, `du_d_z`, `du_q_z`, and saturation flags.
- [ ] Determine whether anti-windup correction uses current-cycle or previous-cycle limiter error.
- [ ] Record reset/initial-state behavior of any delayed limiter feedback.

Expected deliverable: limiter and anti-windup timing semantics, not only numerical bounds.

---

### Task 6: Extract the sector-based SVPWM algorithm

**Files:**
- Read-only: `simulink模型/PMLSM_ControlCore_Block.slx`

- [ ] Locate Sector Calculate, XYZ Calculate, T1/T2 Calculate, and Duty Calculate logic.
- [ ] Record exact sector numbering and sector boundary equations.
- [ ] Record exact X/Y/Z formulas.
- [ ] Record exact T1/T2 formulas.
- [ ] Record exact Duty_A/B/C formulas for every sector or the shared rule used by the model.
- [ ] Determine duty numerical range, polarity, phase ordering, and Udc normalization.
- [ ] Record behavior at zero vector and sector boundaries.
- [ ] Do not replace the model with Min-Max SVPWM in this task.

Expected deliverable: a step-by-step SVPWM reference that later FPGA modules can reproduce and test independently.

---

### Task 7: Audit the DSP ePWM mapping and timing contract

**Files:**
- Read-only: `simulink模型/PMSLM_Close_Loop_MBDL4.slx`
- Read-only: `simulink模型/PMSLM_Init_Params_MBDL4.m`

- [ ] Locate the ePWM blocks receiving duty commands.
- [ ] Determine the exact mapping from duty output to CMPA/CMP values.
- [ ] Determine whether larger duty increases or decreases compare count.
- [ ] Record up/down mode, TBPRD convention, action-qualifier polarity, and complementary-output behavior if visible.
- [ ] Record shadow-load/update behavior and ZERO/PRD event if visible.
- [ ] Identify the current-loop execution trigger and ADC/current-sample entry point.
- [ ] Record current-loop sample period and PWM period.
- [ ] Distinguish real DSP update timing from MIL delay emulation.

Expected deliverable: a normalized-duty timing contract that can be reproduced later on the 50 MHz FPGA without copying raw DSP compare counts.

---

### Task 8: Audit the MIL environment for future golden-vector generation

**Files:**
- Read-only: `simulink模型/PMLSM_MIL_ControlCore_Sim.slx`
- Read-only: `simulink模型/init_PMLSM_mil_test_params.m`
- Read-only: `simulink模型/init_PMLSM_plant_params.m`
- Read-only: `simulink模型/init_PMLSM_control_params.m`

- [ ] Identify the signals logged around the PI current-loop path.
- [ ] Identify how to select PI mode without modifying source files.
- [ ] Identify how deterministic test vectors can be injected safely.
- [ ] Identify whether the current model can be run without C2000 hardware support dependencies.
- [ ] Record MIL-only overrides that differ from real DSP parameters.
- [ ] Do not run DPCC/DPICC validation in this task.

Expected deliverable: a documented safe route to generate PI golden vectors later or now if MATLAB execution is available.

---

### Task 9: Generate golden vectors if executable, otherwise document why not

**Files:**
- Optional create: `coordination/reports/step6a_pi_foc_golden_vectors.csv`
- Optional create: read-only helper scripts under `scripts/reference_audit/`

- [ ] If MATLAB/Simulink is available and the PI path can be executed without modifying reference files, generate deterministic vectors.
- [ ] Cover zero, d-axis, q-axis, multiple angle quadrants, positive/negative PI errors, unsaturated output, saturated limiter case, and representative SVPWM sectors.
- [ ] Export intermediate values through the columns specified in the Step 6A spec.
- [ ] If execution is not possible, do not fabricate CSV values. State exactly why golden vectors were not generated and what dependency is missing.

Expected deliverable: either a trustworthy CSV or an explicit NOT EXECUTED explanation.

---

### Task 10: Produce the final Step 6A audit report

**Files:**
- Create: `coordination/reports/step6a_pi_foc_reference_audit.md`

The report must answer all acceptance questions from the spec and include:

- reference hierarchy;
- exact PI signal chain;
- exact Clarke equations;
- exact Park/inverse-Park equations;
- exact d/q PI and anti-windup equations;
- exact dq limiter;
- exact sector SVPWM;
- duty/ePWM compare mapping;
- timing contract;
- real-vs-MIL parameter distinctions;
- future minimal FPGA PI-current-core interface recommendation;
- unresolved items with evidence required to close them;
- golden-vector generation status.

- [ ] Review the report for assumptions not backed by block paths or parameter sources.
- [ ] Search for vague statements such as “standard Clarke”, “standard PI”, or “typical SVPWM”; replace them with exact audited behavior or mark UNRESOLVED.
- [ ] Confirm no reference `.slx` or `.m` file changed.
- [ ] Confirm no generated Simulink cache/code artifacts were added.

Expected deliverable: one audit document that can serve as the golden specification for later FPGA modules.

---

### Task 11: Git verification and PR

- [ ] Run `git status`, `git diff`, and `git diff --stat`.
- [ ] Confirm changes are limited to the audit report, optional golden CSV, optional read-only helper scripts, and PR metadata.
- [ ] Commit with a concise message such as `docs: audit basic PI FOC Simulink reference`.
- [ ] Push branch `step6a-pi-foc-reference-audit`.
- [ ] Create PR `Step 6A: Audit basic PI FOC Simulink reference` targeting `main`.
- [ ] PR description must explicitly state that no FPGA RTL has been implemented and advanced DPCC/DPICC branches were intentionally excluded.
- [ ] Stop at the open PR for ChatGPT review.

Do not proceed to motor PWM RTL, CORDIC, Clarke/Park RTL, PI RTL, SVPWM RTL, ADC interface, dead time, or Step 6B until this PR is reviewed and accepted.
