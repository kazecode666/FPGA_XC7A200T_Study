# PMLSM Current PI Discrete Form

Scope: `PMLSM_ControlCore_Block.slx`, subsystem `PMLSM_ControlCore/FOC_Algorithm`.

This note records the current-loop PI implementation used by the MIL control core. It is for MIL tuning and documentation only. It does not change the original code-generation model.

## PI Gain Placement

The d-axis and q-axis current PI paths use the same controller parameters:

- Proportional path gain: `Kp_ACR`
- Integral input gain: `Ki_ACR*Ts_ACR`

Therefore the integral update is implemented in the discrete form:

```text
integral(k) = integral(k-1) + Ki_ACR * Ts_ACR * error(k)
```

It is not the form:

```text
integral(k) = integral(k-1) + Ki_ACR * error(k)
```

So theoretical continuous-time current-loop gains can be used directly:

```text
Kp_ACR = L * 2*pi*fc
Ki_ACR = R * 2*pi*fc
```

The model then applies the `Ts_ACR` factor internally.

## d-axis PI

Subsystem: `PMLSM_ControlCore/FOC_Algorithm/d`

Observed implementation:

- `id_ref - id` forms the d-axis current error.
- `Kp_ACR` acts on the proportional current-error path.
- `Ki_ACR*Ts_ACR` acts before the discrete integral accumulation.
- The output is `ud_raw` before dq voltage vector limiting.
- `Kaw_d` is used in the anti-windup feedback path from the limiter feedback term `du_d_z`.

## q-axis PI

Subsystem: `PMLSM_ControlCore/FOC_Algorithm/Iq`

Observed implementation:

- `iq_ref_for_pi - iq` forms the q-axis current error.
- `iq_ref_for_pi` selects the normal `Iq_ref` or iq test path depending on test mode logic.
- `Kp_ACR` acts on the proportional current-error path.
- `Ki_ACR*Ts_ACR` acts before the discrete integral accumulation.
- The output is `uq_raw` before dq voltage vector limiting.
- `Kaw_q` is used in the anti-windup feedback path from the limiter feedback term `du_q_z`.

## Anti-windup

The dq voltage limiter produces feedback terms:

```text
du_d_z = ud_raw - ud_lim
du_q_z = uq_raw - uq_lim
sat_flag_z
```

These delayed limiter differences are fed back through:

```text
Kaw_d
Kaw_q
```

and subtracted in the integral-state update path. The purpose is back-calculation anti-windup: when `ud_raw/uq_raw` exceed the allowed dq voltage vector, the difference between raw and limited voltage reduces the integrator drive so the integrator does not continue winding up against the limiter.

## Voltage Limiting

Subsystem: `PMLSM_ControlCore/FOC_Algorithm/dq_voltage_limiter`

The limiter uses a dq voltage vector limit based on:

```text
U_limit = 0.9 * Udc / sqrt(3)
```

The limiter computes the dq voltage vector magnitude from `ud_raw` and `uq_raw`. If the requested vector exceeds the limit, it scales the vector before output:

```text
ud_raw, uq_raw -> vector limiter -> ud_lim, uq_lim
```

The limiter also generates `sat_flag_z`, which can be used by tuning scripts when it is available in `logsout`. If `sat_flag_z`, `ud_raw`, `uq_raw`, `ud_lim`, and `uq_lim` are not logged by the current MIL top model, the tuning script falls back to checking `vd_cmd/vq_cmd` magnitude and duty limits.

## Theoretical Initial Gains

Using:

```text
Rs = 1.45 ohm
Ld = Lq = 0.0118 H
Kp = L * 2*pi*fc
Ki = R * 2*pi*fc
```

| fc Hz | Kp_ACR | Ki_ACR |
|---:|---:|---:|
| 100 | 7.4142 | 911.0619 |
| 200 | 14.8283 | 1822.1237 |
| 300 | 22.2425 | 2733.1856 |
| 500 | 37.0708 | 4555.3093 |
| 800 | 59.3133 | 7288.4940 |
| 1000 | 74.1416 | 9110.6187 |

The tuning script also searches `fc = 50 Hz` as a conservative lower-bandwidth point.
