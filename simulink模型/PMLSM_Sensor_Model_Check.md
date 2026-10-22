# PMLSM Sensor Model Check

## Current MIL Sensor Configuration

The current hardware regression path uses independent three-phase ADC current
sampling. The MIL `Sensor_Model` therefore defaults to independent three-phase
current feedback:

```text
ia -> ia_meas -> ia_feedback
ib -> ib_meas -> ib_feedback
ic -> ic_meas -> ic_feedback
```

The current setting is:

```matlab
PMLSM_current_feedback_mode = 3
```

where:

- `2`: historical compatibility/debug option, two-phase sampling with
  `ic = -ia - ib`.
- `3`: current default hardware regression path, independent `ia/ib/ic`
  sampling.

The `ic = -ia - ib` reconstruction path is not the current hardware regression
path.

## Speed Measurement Delay

The confirmed speed measurement delay remains:

```matlab
PMLSM_sensor_delay_samples = 50
```

With the fixed simulation step:

```matlab
PMLSM_Ts_s = 1e-4
```

the measured speed is:

```text
v_meas_mmps = (x(k)-x(k-50))/(50*Ts)
```

This corresponds to a 5 ms position-difference window.

## Position Quantization

The grating scale resolution remains:

```matlab
PMLSM_grating_resolution_mm = 0.001
```

The model quantizes position to 1 um before the delayed difference speed
calculation.

## Interface Check

The main MIL model keeps the `Plant_Bus` feedback interface:

```text
ia_feedback
ib_feedback
ic_feedback
x_feedback
```

The expected default source is:

```text
ia_feedback <- Sensor_Model/ia_meas
ib_feedback <- Sensor_Model/ib_meas
ic_feedback <- Sensor_Model/ic_meas
```

`ic_feedback = -ia_feedback - ib_feedback` must not be the default path for the
current hardware regression model.
