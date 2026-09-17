# ChatGPT ↔ Codex Project Handoff

This file is the persistent coordination index for the FPGA learning / motor-control project. GitHub is the source of truth between ChatGPT (architecture/review) and Codex (execution).

## Working agreement

- ChatGPT owns architecture, task definition, design decisions, acceptance criteria, and PR review.
- Codex owns local repository inspection, Simulink/reference inspection, RTL/testbench/Tcl/XDC edits when explicitly authorized, Vivado/MATLAB execution, reports, commits, pushes, and PR creation.
- Do not rely on copied chat snippets when this file and the repository contain the current task/spec.
- Do not use SHA-256/file-hash verification for this learning project. Use Git diff/status, simulation, synthesis, implementation, timing, DRC, and physical behavior.
- Do not guess board pins, clocks, I/O standards, algorithm equations, PWM polarity/count semantics, numeric formats, or timing semantics.
- Each implementation/audit task uses a feature branch and stops at an open PR for ChatGPT review unless explicitly instructed otherwise.

## Accepted baseline

Completed and accepted:

- Step 1: self-checking PWM testbench.
- Step 2: compare-value semantics and boundaries.
- Step 2.5: registered PWM output/counter alignment.
- Step 3: synthesis baseline.
- Step 4: 50 MHz constraint, implementation and post-route timing.
- Step 5A: BX72 LED blink board bring-up, physically verified.
- Step 5B: BX72 breathing LED demo, physically verified.
- Step 6A: basic PI-FOC Simulink reference audit, PR #10 merged.

Step 6A accepted reference artifacts now on `main`:

- `coordination/reports/step6a_pi_foc_reference_audit.md`
- `coordination/reports/step6a_pi_foc_golden_vectors.csv`
- `scripts/reference_audit/step6a_pi_vectors.m`
- `scripts/reference_audit/verify_step6a_vectors.py`

The advanced DPCC/DPICC/PICDO branches are **not** part of the first FPGA current-loop baseline.

## Frozen BX72 hardware facts

- Target learning-board part: `xc7a200tfbg484-2`.
- Physical JTAG detection: `xc7a200t`.
- Board clock: 50 MHz.
- `clk`: Y18, Bank 14, LVCMOS33.
- `key2_n`: V17, Bank 14, LVCMOS33, active LOW.
- `led1`: AA18, Bank 14, LVCMOS33, active HIGH.
- `CFGBVS = VCCO`.
- `CONFIG_VOLTAGE = 3.3`.

## Reference assets

- `ACM9238-SCH.pdf`
- `simulink模型/FPGA_Simulink_Model_Guide.md`
- `simulink模型/PMLSM_ControlCore_Block.slx`
- `simulink模型/PMLSM_MIL_ControlCore_Sim.slx`
- `simulink模型/PMSLM_Close_Loop_MBDL4.slx`
- accompanying `.m` parameter/test/plant scripts

The Simulink package is an algorithm/reference source. Do not silently inherit unresolved historical DSP/MIL raw PWM count or polarity conventions into the FPGA motor PWM.

## Legacy learning PWM

`pwm_controller` from Steps 1–5 remains a verified learning core.

It is **not** the future motor-control PWM engine because its semantics (`counter >= compare`, `config_en` resetting the counter) are not suitable as the final shadow-compare motor PWM architecture.

Do not mutate that historical learning core into Step 6B.

## Motor-control reference priority

When references disagree:

1. approved FPGA motor-control architecture contract;
2. Step 6A PI-FOC audit/golden vectors for math;
3. MIL/ControlCore Simulink for algorithm/closed-loop reference;
4. proven F28335 physical experience;
5. unverified F28388D code-generation integration as historical reference only.

## Approved direction from chat

The first FPGA current-loop implementation will be intentionally simple:

- PI FOC only;
- no DPCC/DPICC/PICDO;
- no speed loop or position loop;
- no startup/alignment/mode-management reproduction yet;
- first algorithm inputs come from testbench/golden vectors;
- no ACM9238 interface in the first current-core implementation;
- no encoder interface in the first current-core implementation;
- algorithm and hardware acquisition are verified separately before integration.

Conceptual chain:

```text
ia/ib/ic + theta_e + we + id_ref/iq_ref + vdc
                    ↓
                 Clarke
                    ↓
                  Park
                    ↓
           d/q PI + feedforward
                    ↓
             dq voltage limiter
                    ↓
              Inverse Park
                    ↓
          existing sector SVPWM
                    ↓
            normalized duty U/V/W
                    ↓
                duty_to_cmp
                    ↓
              motor_pwm_core
```

## Current design-review gate

A formal architecture specification has been written:

`coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`

Status: **waiting for user review/approval before Codex implementation planning**.

Key proposed contract:

- XC7A200T fabric clock: 50 MHz;
- center-aligned motor PWM: 10 kHz;
- `TBPRD = 2500`;
- one shared U/V/W up/down carrier;
- clean active-high normalized duty `[0,1]`;
- motor PWM integer compare: `CMP = round(duty*TBPRD)`;
- atomic three-phase shadow command;
- first load mode: ZERO only;
- baseline FOC sample event: carrier PEAK;
- baseline command load: following ZERO;
- first FOC implementation uses coherent testbench/golden-vector transactions;
- PI state updates once per accepted 100 us control transaction, never every 50 MHz fabric clock;
- `we` feedforward and one-control-period anti-windup state semantics are retained;
- first SVPWM reproduces the audited sector algorithm but outputs normalized duty instead of historical raw DSP counts;
- AMD CORDIC, if used, is isolated behind `sincos_core`;
- fixed-point formats are frozen in a separate numeric-format decision before FOC RTL.

Proposed implementation decomposition after spec approval:

```text
Step 6B   Motor PWM Core
Step 6C1  Numeric format + Clarke/Park/sincos foundation
Step 6C2  PI + dq limiter
Step 6C3  Sector SVPWM -> normalized duty
Step 6C4  Full PI-FOC transaction core
Step 6D   PI-FOC -> PWM timing integration
```

No Codex implementation task is authorized until the architecture spec is approved.

## Next action after approval

After the user approves `coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`, ChatGPT will create the detailed Step 6B implementation plan/task for Codex and change this handoff from design-review mode to executable Step 6B mode.
