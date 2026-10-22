# PMLSM ePWM Polarity Check

## Current Status

PWM polarity is no longer treated as a current blocking risk.

The current code-generation model and the real DSP F28335 hardware have
already driven the motor successfully in previous hardware runs. Therefore the
MIL average inverter should stay consistent with the already-runnable
code-generation path instead of being changed only from theoretical ePWM action
analysis.

## Confirmed DSP F28335 ePWM Setup

- ePWM output type: complementary high-active PWM.
- TBCLK: `150 MHz`.
- PWM frequency: `10 kHz`.
- PWM period count: `7500`.
- Counter mode: Up-Down.
- ePWMA action:
  - CAU: Clear.
  - CAD: Set.
  - ZERO/PERIOD: Do nothing.
- Deadband polarity: Active high complementary.
- RED/FED: `150` counts each.
- Deadtime: `150 / 150 MHz = 1 us`.

## MIL Inverter Polarity Policy

The current MIL `Inverter_Model` uses the legacy average-voltage conversion in
`Plant_Input_Mode = 2`:

```text
duty_ratio = 1 - CMPA / PMLSM_pwm_period_counts
```

This path should not be changed now. It is kept because the current
code-generation model and real hardware have already been validated as a
runnable combination.

The key rule for the current MIL stage is:

```text
Keep Inverter_Model polarity consistent with the already-running code-generation model.
```

Do not switch the MIL inverter to another duty polarity solely because of the
standalone ePWM theoretical mapping. Only revisit this conversion if a future
oscilloscope test, hardware current response, or motor-force direction test
shows that the MIL inverter voltage polarity is inconsistent with the real
system.

## Diagnostic Script

The script:

```matlab
check_pwm_polarity_mapping
```

still documents the two mathematical mappings:

```text
duty_high_A = CMPA / PWM_Period
duty_high_B = 1 - CMPA / PWM_Period
```

It is retained as a diagnostic aid, not as a reason to modify the current MIL
inverter model.
