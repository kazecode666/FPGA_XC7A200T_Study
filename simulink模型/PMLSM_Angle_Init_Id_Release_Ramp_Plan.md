# Angle_Init id_ref Release Ramp Plan

Scope: PMLSM_ControlCore_Block.slx, subsystem PMLSM_ControlCore/Angle_Init.

This document records the current Angle_Init behavior and the proposed minimal MIL validation change for reducing the vd_cmd spike at initialization exit. It does not modify PMSLM_Close_Loop_MBDL4.slx.

## Current State Machine

Current states observed in PMLSM_ControlCore_Block/PMLSM_ControlCore/Angle_Init:

| State | Init_State_Num | Key behavior |
|---|---:|---|
| IDLE | 0 | Angle_Init_EN = 0, Init_Done = 0, id_init_ref = 0 |
| RAMP_ID | 1 | Angle_Init_EN = 1, ramp id_init_ref up by Id_Init_Step until Id_Init_Target |
| HOLD_ALIGN | 2 | Angle_Init_EN = 1, hold id_init_ref = Id_Init_Target |
| DONE | 3 | Angle_Init_EN = 0, Init_Done = 1, force id_init_ref = 0 |

The transition from HOLD_ALIGN to DONE occurs after Hold_Ticks. During this transition the model captures:

```text
x_align_mm_latch = x_mm
theta_offset_mem = mod(theta_align_const - 2*pi*x_align_mm_latch/Tau_e_mm, 2*pi)
Theta_Offset_auto = theta_offset_mem
```

Then DONE immediately sets:

```text
id_init_ref = 0
Init_Done = 1
Angle_Init_EN = 0
```

This confirms the current risk:

```text
id_ref step-down causes vd_cmd spike.
```

## Proposed Minimal Change

Add one state between HOLD_ALIGN and DONE:

```text
RAMP_DOWN_ID
```

Recommended parameter:

```matlab
Id_Release_Ramp_Ticks = 2000;  % 0.2 s @ 10 kHz
```

Proposed sequence:

1. HOLD_ALIGN completes after Hold_Ticks.
2. Capture x_align_mm_latch and Theta_Offset_auto exactly as today.
3. Enter RAMP_DOWN_ID.
4. Keep Angle_Init_EN = 1.
5. Keep Init_Done = 0.
6. Ramp id_init_ref down from Id_Init_Target to 0 over Id_Release_Ramp_Ticks.
7. After id_init_ref reaches 0, enter DONE.
8. Only in DONE, set Init_Done = 1.

## State Number Recommendation

Least disruptive option:

```text
0 = IDLE
1 = RAMP_ID
2 = HOLD_ALIGN
4 = RAMP_DOWN_ID
3 = DONE
```

This keeps existing DONE = 3 behavior compatible with existing plots and checks, while adding 4 only for the new release-ramp state.

Cleaner renumbering option:

```text
0 = IDLE
1 = RAMP_ID
2 = HOLD_ALIGN
3 = RAMP_DOWN_ID
4 = DONE
```

This is easier to read but changes the current meaning of Init_State_Num = 3, so it should be avoided unless all scripts and plots are updated.

## Validation Target

The MIL validation should compare:

- id_ref / id_meas
- vd_cmd
- vq_cmd
- duty_a/b/c
- fault_latch
- Init_Done
- Init_State_Num

Expected result:

- vd_cmd spike at Angle_Init exit should decrease.
- Init_Done should be delayed by Id_Release_Ramp_Ticks * Ts_ACR.
- iq_test_mode should not start until after the release ramp finishes and Init_Done = 1.

This is a control-strategy change and should be validated first in MIL before any real-hardware or original code-generation model changes.
