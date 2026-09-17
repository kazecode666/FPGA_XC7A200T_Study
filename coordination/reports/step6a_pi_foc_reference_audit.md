# Step 6A — Basic PI FOC Simulink reference audit

Date: 2026-09-17. Base: `main` at `79b3598`. Branch: `step6a-pi-foc-reference-audit`.

**Scope: `Current_Control_Mode = 1` only.** This is an audit and an extracted-source-block simulation, not an FPGA implementation or a motor commissioning result. No reference asset was saved or changed. No advanced controller was simulated, no C/HDL was generated, and no Vivado or hardware operation was performed. Stop at the open PR for ChatGPT Review.

The PI equations and signal routes are recoverable. **The integrated reference is not yet an unambiguous physical PWM specification:** CPU-clock compare scaling, DSP-versus-MIL polarity/period, and transform lookup resolution disagree across the supplied assets/runtime. These are findings for Review, not corrections made in this task. In particular, a zero-voltage command produces **5000 raw counts**, not a normalized duty of 0.5; DSP `TBPRD` is also 5000. See sections 7–9 and 11 before using this reference for motor outputs.

## 1. Reference hierarchy and method

All reference paths below are relative to `simulink模型/`.

| Authority | File | Use in this audit |
|---|---|---|
| Navigation, read first | `FPGA_Simulink_Model_Guide.md` | Distinguish algorithm, integration, test and plant layers |
| Primary algorithm topology | `PMLSM_ControlCore_Block.slx` | Actual PI, transforms, limiter, SVPWM blocks and wiring |
| Real control parameters | `PMSLM_Init_Params_MBDL4.m` | Commissioning gains, clocks, motor constants, reset defaults |
| DSP integration | `PMSLM_Close_Loop_MBDL4.slx` | ADC trigger, interrupt, compare wiring, action qualifier and shadow events |
| MIL environment | `PMLSM_MIL_ControlCore_Sim.slx` | Wrapper, feedback, inverter, logging and delay emulation |
| MIL test overrides | `init_PMLSM_mil_test_params.m` | PI gain override, default mode, delay configuration |
| Plant/scaling | `init_PMLSM_plant_params.m` | Electrical period, current convention, nominal bus, MIL count denominator |
| Initialization entry | `init_PMLSM_control_params.m` | Calls the real parameter script before later MIL overrides |

Latest `main` contains the merged Step 5B baseline and reference uploads described in `HANDOFF.md` (PRs #7–#9). The branch was created from updated `main` before audit files were written.

Inspection used read-only ZIP/XML to identify callbacks and wiring, followed by MATLAB `load_system`, `find_system`, `get_param`, mask and port-connectivity APIs. MATLAB is **R2026a Update 5**, Simulink **26.1**, Motor Control Blockset **26.1**. Model loading resolved the installed linked transform libraries; therefore library-derived results are explicitly separated from self-contained SLX equations. Both loaded source models reported `Dirty=off`.

No reference initialization script was executed in the shared MATLAB workspace: the real script begins with `clear; clc`, and the MIL `InitFcn` restores mode 2. The test helper assigns the audited PI-only values in a new, unsaved model's private workspace and copies only the required numerical blocks. It does not copy or execute an advanced-controller subsystem.

Path notation used below:

- `C = PMLSM_ControlCore_Block/PMLSM_ControlCore`
- `F = C/FOC_Algorithm`
- `D = PMSLM_Close_Loop_MBDL4/FOC_3Close_Loop_Control`
- `M = PMLSM_MIL_ControlCore_Sim`
- `\n` within a block name means an actual newline, not a path separator. Names such as `Clack`, `Caculate`, lowercase DSP `id/iq`, and uppercase core `Id/Iq` are intentional source spellings. Gain names consisting of spaces are identified by SID as well.

## 2. Exact PI signal chain and selection

| Stage | Exact source path / route |
|---|---|
| Current entry | Root `ia/ib/ic` → `C/ia_in`, `ib_in`, `ic_in` → local tags `ia/ib/ic` → `F/ia`, `ib`, `ic` |
| Clarke | `F/Clack` (SID 213), outputs `ialpha`, `ibeta` → `F/Park Transform` inputs 1/2 |
| Angle | `C/Caculate_measurement/etheta` → `etheta` tag → `F/etheta` → `F/Goto8`; `F/From7` feeds Park, `F/From8` feeds inverse Park |
| Feedback | `F/Park Transform` outputs 1/2 are `obs_id`, `obs_iq`; local tags `id/iq` feed both PI axes |
| References | `F/Id_Ref` → tag `Id_Ref` → `F/Id/id_ref`; `F/iq_ref` → tag `Iq_ref` → `F/Iq/Iq_ref` |
| d controller | `F/Id` (SID 386) → tag `ud_raw` |
| q controller | `F/Iq` (SID 255) → tag `uq_raw` |
| PI selection | `F/select_ud_current_mode`, `F/select_uq_current_mode` → `selected_ud_raw`, `selected_uq_raw` |
| q override | `F/Switch2`: `Uq_Zero_EN > 0.5` selects zero, otherwise selected q voltage |
| Limiter | `F/dq_voltage_limiter` inputs 1/2 → `ud_lim/uq_lim`; outputs 3/4 are delayed corrections `du_d_z/du_q_z` back to PI input 5 |
| Inverse Park | `F/From9` (`ud_lim`) and `F/From14` (`uq_lim`) → `F/Inverse Park Transform` inputs 1/2; same `etheta` input 3 |
| Compensation bypass | Inverse Park → `F/DeadTime_Compensation` → `F/SVPWMG`. With `DeadTime_Comp_Enable=0`, its added correction is zero for finite valid inputs. This audit uses that bypass only |
| Modulation | `F/SVPWMG/Sector\nCaculate`, `XYZ\nCalculate`, `T1T2\nCalculate`, `Duty\nCalculate` |
| Outputs | `SVPWMG` outputs 1/2/3 → `F/duty_a/b/c` → `C/duty_a_core/b_core/c_core` → root `duty_a/b/c`. These are raw counts; root `vd_cmd/vq_cmd` are limited dq volts |

The two mode switches have criterion **`u2 > 1.5`**. PI raw outputs connect to input 3; the excluded controller output connects to input 1. Thus mode 1 selects PI exactly. This is **output selection**, not evidence that all parallel branches are execution-disabled in a full model simulation. The harness avoids that ambiguity by containing only the selected PI blocks and their direct connections. Advanced branches exist under `F/DPCC_Current_Controller`; their algorithms were not audited.

`Close_Loop_EN`, `Angle_Init_EN`, `Init_Done` and `fault_latch` inputs at `F` connect to the excluded branch, not directly to the core PI switches. PI reset is a separate data-store command. Upstream reference management and external power-stage gating must not be mistaken for a PI-local enable. `Uq_Zero_EN` additionally resets q PI; it does not reset d PI.

## 3. Exact Clarke equations

Source: `F/Clack/Add`, `Add1`, `Gain`, `Gain1`, `Gain2`, `Gain3` (SIDs 217–222):

```text
i_alpha = (2/3) * (ia - 0.5*ib - 0.5*ic)
i_beta  = (ib - ic) / sqrt(3)
```

This is the **three-current, amplitude-invariant** form, with positive beta for positive `ib-ic`. All currents are physical amperes, not ADC counts or per-unit values. Common-mode current is removed: `(ia,ib,ic)=(1,1,1)` gives `(0,0)`, confirmed by simulation.

The DSP front end can separately reconstruct `ic=-(ia+ib)` when `Three_Current_Sampling_EN` is false. Its supplied default is true, so all three measured currents enter the same three-input transform. Only after imposing `ia+ib+ic=0` can the equations be reduced to `i_alpha=ia`, `i_beta=(ia+2*ib)/sqrt(3)`. That reduction is not the stored Clarke implementation.

## 4. Park, inverse Park and electrical angle

Both `F/Park Transform` (SID 294) and `F/Inverse Park Transform` (SID 254) store mask values `AxisAlignment=D-axis`, `PhaseInput=Two inputs`, `ThetaInput=Electrical position`, `AngleInput=Radians`, `UseWithEmbedded=on`, `N_points=1024`.

The resolved library wiring was inspected at:

```text
F/Park Transform/Variant/mcb/Park Transform/Select/Two Inputs/Two inputs CRL
F/Inverse Park Transform/Variant/mcb/Inverse Park Transform/Select/Two Inputs/Two inputs CRL
```

Park `sum_Ds` adds `acos + bsin`; `sum_Qs` subtracts `bcos - asin`. Inverse `sum_alpha` is `dcos - qsin`, `sum_beta` is `dsin + qcos`. With actual library values `c_L(theta)` and `s_L(theta)`:

```text
id      =  i_alpha*c_L + i_beta*s_L
iq      = -i_alpha*s_L + i_beta*c_L
v_alpha =  ud_lim*c_L - uq_lim*s_L
v_beta  =  ud_lim*s_L + uq_lim*c_L
```

At theta 0, d aligns with alpha and q with beta. Positive angle rotates the d-axis from alpha toward beta. This establishes mathematical direction, not the physical sign of a motor encoder or phase wiring.

The source angle route is:

```text
C/Caculate_measurement/Data Type Conversion
→ Gain [2*pi/Tau_e_mm]
→ Add2 [add Theta_Offset_auto and Theta_Offset_Fine]
→ Math\nFunction1 [mod, second input 2*pi]
→ Switch2 → etheta
```

Outside the alignment override, `theta_e = mod(2*pi*x_mm/60 + Theta_Offset_auto + Theta_Offset_Fine, 2*pi)`. Units are radians in `[0,2*pi)`, with one electrical period per +60 mm; 30 mm is the pole pitch, not a full electrical period. When `Angle_Init_EN>0.5`, `Switch2` selects `theta_align_const`. Only this angle-interface effect is in scope.

Park and inverse Park consume the same current transaction's `etheta` tag, with **no Unit Delay between them**. The 50-sample `C/Caculate_measurement/Delay` belongs to the velocity-difference route, not the angle route. `we` is electrical rad/s from the measurement velocity route and is also a required PI feedforward input (section 5).

### Numeric library finding

Do not replace the implemented trigonometry with ideal `sin/cos` when comparing these CSV values. The installed `.../Variant/mcb/sinecos` mask selects **Lookup**. Read-only mask workspace inspection of `.../sinecos/Sine-Cosine Lookup` returned:

```text
outer N_points = 1024
dlgSett.N_points = 800
dlgSett.index_gain = 800
dlgSett.Offset = 200
dlgSett.points = 1000
dlgSett.size = 1002
dlgSett.UpperSatLimit = 2*pi
```

The observed output is consistent with a full-cycle **800-interval linearly interpolated** sine/cosine table. For theta 0.3 and alpha 0.2, beta 0, the captured `id=0.191066365401038`; ideal cosine would give `0.191067297825121`. All CSV transforms and downstream values cross-check with the 800-interval interpolation. The discrepancy between stored outer 1024 and resolved 800 is **UNRESOLVED as a portable reference requirement**; the library content is not embedded fully in the supplied SLX. No reference or library setting was corrected. Lookup interpolation also means the two transform matrices are not exactly orthonormal between knots.

## 5. PI discrete-time and anti-windup equations

Let `k` denote one 100 us control transaction. `x_d[k]`, `x_q[k]` are the **old** outputs of `F/Id/x_d_z` and `F/Iq/x_q_z`, both Unit Delay, inherited sample time, initial condition 0. Let `du_d_z[k]`, `du_q_z[k]` be the limiter outputs described in section 6.

With resets inactive and `Uq_Zero_EN=0`:

```text
e_d[k] = id_ref[k] - id[k]
e_q[k] = iq_ref[k] - iq[k]

ud_raw[k] = Kp_ACR*e_d[k] + x_d[k] - we[k]*PMLSM_Lq_H*iq[k]
uq_raw[k] = Kp_ACR*e_q[k] + x_q[k]
            + we[k]*(PMLSM_Ld_H*id[k] + PMLSM_psi_f_Wb)

x_d[k+1] = x_d[k] + Ki_ACR*Ts_ACR*e_d[k] - Kaw_d*du_d_z[k]
x_q[k+1] = x_q[k] + Ki_ACR*Ts_ACR*e_q[k] - Kaw_q*du_q_z[k]
```

This is PI **plus decoupling/back-EMF feedforward**, not just two scalar PI outputs. The d term subtracts `we*Lq*iq`; the q term adds `we*(Ld*id+psi_f)`. `Rs` is used to calculate gains, not added as an explicit `Rs*i` term in these PI blocks.

Exact implementation evidence:

| Path | Role |
|---|---|
| `F/Id/Sum`, `F/Iq/Sum` | Reference minus measured current |
| `F/Id/ ` SID 392, `F/Iq/ ` SID 262 | Gain `Ki_ACR*Ts_ACR` (one-space block name) |
| `F/Id/  ` SID 393, `F/Iq/  ` SID 263 | Gain `Kp_ACR` (two-space name) |
| `F/Id/Add1`, `F/Iq/Add1` | Add proportional result to old integrator state |
| `F/Id/Constant1`, `Product`, `Product1`, `Sum1` | d feedforward subtraction |
| `F/Iq/Ld`, `Constant`, `Product`, `Add`, `Product1`, `Sum1` | q inductance/flux feedforward addition |
| `F/Id/Add2`, `F/Iq/Add2` | Inputs `++-`: old state + integral increment − back-calculation |
| `F/Id/Gain`, `F/Iq/Gain` | `Kaw_d` / `Kaw_q`; no further Ts multiplication |
| `F/Id/Switch1`, `F/Iq/Switch1` | Choose next state or zero before writing Unit Delay |

`Ki_ACR` is a continuous-time integral gain in V/(A·s); the block separately multiplies by Ts. `Kp` is V/A; `x` and `du` are volts. `Kaw=0.2` is the per-update multiplier already used directly, not `0.2*Ts`. No local scalar saturation or integrator clipping exists in these PI subsystems. The radial limiter is downstream of feedforward and mode selection.

Reset details:

- Core `F/Id/Constant` (SID 762) and `F/Iq/Constant10` (SID 761) read data store **`PI_Reset_EN_cmd`**. `C/pi_reset_en_cmd_write` writes the root `pi_reset_en_cmd` input into this store; the interface is not a fixed zero constant.
- d `Switch` and `Switch1` use `PI_Reset_EN_cmd > 0.5`: the current output and **next** state both become zero. The Unit Delay itself is not an asynchronously reset block.
- q `Logical\nOperator` computes logical OR of `PI_Reset_EN_cmd` and `uq_zero_en`; q `Switch` and `Switch1` then force output and next state to zero. `iq_ref_for_pi` also selects measured iq instead of the reference when `uq_zero_en>0.5`, yielding zero error. Intended command domain is Boolean 0/1; non-Boolean reset values are not equivalent between d's numeric threshold and q's logical conversion.
- A held reset is reset-to-zero on every transaction, not integrator hold/freeze. There is no separate PI hold input.
- Top-level `F/Switch2` independently zeros the q input to the limiter for `Uq_Zero_EN>0.5`.
- DSP d reset parameter source is `D/FOC_Algorithm/id/Constant = PI_Reset_EN`. The real script initializes `PI_Reset_EN.Value=1`; that is an asserted reset until externally changed. It is not an assumption of automatic PI operation at script load.

Order: read old `x` and old limiter correction; calculate current raw output; limit it; schedule next `x` using **the prior correction**; schedule new limiter correction for the following transaction. Current saturation does not change the same transaction's `x` output. Consequently its effect through `x[k+1]` only begins when the delayed correction is consumed on the next update. Golden `sat_start`, `sat_hold_*`, `recovery_*`, `q_zero`, and `release` rows exercise this behavior.

### Parameter sources: do not mix profiles

| Parameter | Real script / commissioning | MIL test override |
|---|---:|---:|
| `Ts_ACR`, `Ts=1/PWM_Freq` | 0.0001 s | 0.0001 s |
| `Rs`, `PMLSM_Rs_ohm` | 2.37 ohm | 2.37 ohm |
| `Ld=Lq`, `PMLSM_Ld_H/PMLSM_Lq_H` | 0.001745 H | Same |
| `PMLSM_psi_f_Wb` | 0.141 Wb | Same |
| `Kp_ACR_Baseline = Lq/(4*Ts_ACR)` | 4.3625 | Baseline source retained |
| `Ki_ACR_Baseline = Kp*Rs/Lq` | 5925 | Baseline source retained |
| `ACR_Commissioning_Scale` | 0.5 | MIL subsequently overwrites gains |
| Actual `Kp_ACR` | **2.18125** | **4.3625**, xi=1, Tc=Ts_ACR |
| Actual `Ki_ACR` | **2962.5** | **5925** |
| `Ki_ACR*Ts_ACR` | **0.29625** | **0.5925** |
| `Kaw_d`, `Kaw_q` | 0.2, 0.2 | Same |
| Nominal `Udc` | 48 V | `MIL_Vdc_V=48`, `Udc=MIL_Vdc_V` |
| `Iq_Limit` | 0.30 A commissioning reference limit | Not a PI-internal clamp; MIL direct injection can exceed it |
| `Id_Ref_Set`, `Uq_Zero_EN` | 0, 0 | Harness explicitly selects normal PI unless reset test |

The deliberately large 30 A / −20 A vector is an **offline arithmetic saturation test**, not a recommended motor current or evidence of operation within real commissioning reference limits.

## 6. dq voltage limiter

Source: `F/dq_voltage_limiter`, especially `Constant1`, `Gain`, `Sqrt`, `Sum`, `Divide`, `MinMax`, `Product/Product1`, `Subtract/Subtract1`.

For its selected input pair `(u_d,u_q)`:

```text
Umax = 0.9 * Udc / sqrt(3)
r    = sqrt(u_d*u_d + u_q*u_q)
s    = min(1, Umax / (r + 1e-6))
ud_lim = s*u_d
uq_lim = s*u_q

du_d_z[k+1] = u_d[k] - ud_lim[k]
du_q_z[k+1] = u_q[k] - uq_lim[k]
sat_flag_z[k+1] = (s[k] < 0.999)
```

`Constant3=1`; `MinMax` is **min**, verified using MATLAB defaults. The 1e-6 is an **addition** to the norm, not `max(norm,epsilon)`. At 48 V, `Umax=24.9415316289918 V`. Direction is preserved by common scale s. There is no separate d-axis or q-axis hard limit. Because of epsilon, a saturated norm is very slightly below Umax; the flag threshold is not exactly the onset of scaling.

`Unit Delay`, `Unit Delay1`, `Unit Delay2` (SIDs 444–446) all have initial condition 0 and inherited sample time. They do **not** have reset ports and are not connected to PI reset. Under normal PI selection they store PI raw-minus-limited voltage, including feedforward; the sign is important because the PI **subtracts** `Kaw*du_z`. One asserted PI-reset transaction makes raw voltages zero and overwrites delayed corrections for the next transaction, but the old corrections can still be observed during that reset transaction.

`Udc` is a workspace **Constant parameter** in the limiter and SVPWM, not a sampled vdc port on the supplied control core. No positive-bus/finiteness guard was found on this path. Equations/ranges in this report assume finite inputs and Udc>0. A future dynamic vdc input needs an explicit transaction contract; an existing ADC scaling parameter alone does not prove measured-bus feedback reaches this constant.

## 7. Exact sector SVPWM

Let `A=v_alpha`, `B=v_beta`, `T=Ts`, `V=Udc`. Retain the decimal constants **0.866** and **1.7321** exactly; replacing them with exact radicals changes boundaries/numerics.

### Sector: `F/SVPWMG/Sector\nCaculate`

```text
B0 = B
B1 = 0.866*A - 0.5*B
B2 = -0.866*A - 0.5*B
b0 = (B0 > 0)       [Switch]
b1 = (B1 >= 0)      [Switch1 — different equality rule]
b2 = (B2 > 0)       [Switch2]
N  = b0 + 2*b1 + 4*b2
```

All three switch thresholds are 0, confirmed from MATLAB. Around positive alpha, the counterclockwise interior numbering is **3, 1, 5, 4, 6, 2**, approximately the six successive 60° regions. The actual oblique boundaries are `B=±1.732*A`, not exact 60° radicals. For nonzero exact boundary vectors `(A,B)=(1,0),(1,1.732),(-1,1.732),(-1,0),(-1,-1.732),(1,-1.732)`, predicates assign **2,3,1,4,6,6**, respectively. Floating-point upstream multiplication can place a nominal edge vector infinitesimally on either side; the captured edge rows are retained rather than relabeled.

At zero, predicates give `(0,1,0)` and **N=2**, not N=0. T1/T2 become zero and all three counts are equal.

### XYZ: `F/SVPWMG/XYZ\nCalculate`

```text
X = 1.7321*B*T/V
Y = (0.866*B + 1.5*A)*T/V
Z = (0.866*B - 1.5*A)*T/V
```

These values and T1/T2 below have units **seconds**. `Math\nFunction` forms `1/Udc`, `Product` multiplies it by Ts. There is no per-unit voltage assumption.

### T1/T2: `F/SVPWMG/T1T2\nCalculate`

The six one-based Multiport Switch inputs select provisional `(a,b)`:

| N | a | b |
|---:|---|---|
| 1 | Z | Y |
| 2 | Y | −X |
| 3 | −Z | X |
| 4 | −X | Z |
| 5 | X | −Y |
| 6 | −Y | −Z |

`Fcn = T-b-a`, `Fcn1=a*T/(a+b)`, `Fcn2=b*T/(a+b)`:

```text
T1 = a                 if T-a-b >= 0; otherwise a*T/(a+b)
T2 = b                 if T-a-b >  0; otherwise b*T/(a+b)
```

The two final switches differ at equality; when `a+b=T>0`, the scaled/unscaled expressions agree mathematically. This is overmodulation sum normalization, not a per-dwell nonnegative clamp. Multiport Switch defaults are `One-based contiguous`, `Last data port`, diagnostic **Error** on invalid selector. Do not invent a safe default vector for invalid N. The finite zero-vector simulation succeeded; unselected division expressions did not appear as nonfinite outputs.

### Duty: `F/SVPWMG/Duty\nCalculate`

```text
L = (T-T1-T2)/4      [Fcn]
M = (T+T1-T2)/4      [Fcn1]
H = (T+T1+T2)/4      [Fcn2]
```

| N | U/A time | V/B time | W/C time |
|---:|---|---|---|
| 1 | M | L | H |
| 2 | L | H | M |
| 3 | L | M | H |
| 4 | H | M | L |
| 5 | H | L | M |
| 6 | M | H | L |

`Gain`, `Gain1`, `Gain2` multiply these times by **CPU_Clock**, yielding `Duty_U/V/W` and top-level `duty_a/b/c`. No final normalization, clamp, or explicit integer conversion block is present. For valid nonnegative dwell times whose sum is <=T, the theoretical range is `[0, CPU_Clock*T/2]`, which is **[0,10000]** with the supplied real/MIL CPU-clock value. The common-zero count is `CPU_Clock*T/4=5000`. Small boundary inconsistencies can occur because sector and XYZ use rounded constants; nonnegative dwell/ordered L≤M≤H is not explicitly enforced.

An algorithm-only normalized **compare fraction** can be defined as `rho=C/(CPU_Clock*T/2)`. It is not automatically physical HIGH duty. The CSV intentionally records source raw counts in `duty_a/b/c`, not rho, not percent and not FPGA counts. No alternative Min-Max modulation was substituted.

## 8. Duty → DSP ePWM compare and polarity

Exact wiring in `D/FOC_Algorithm`:

```text
SVPWMG/Duty_A → ePWM1 input 1 (CMPA)
SVPWMG/Duty_B → ePWM2 input 1 (CMPA)
SVPWMG/Duty_C → ePWM3 input 1 (CMPA)
```

No gain, saturation or conversion block intervenes. DSP `SVPWMG/Duty\nCalculate/Gain{,1,2}` also use `CPU_Clock`. The ePWM masks explicitly select CMPA **Input port**, units **Clock cycles**. The continuous reference count is therefore `CMPA_command = CPU_Clock * selected_time`; conversion/rounding at generated register writes was not audited because code generation is excluded.

All three ePWM masks:

| Property | Stored setting |
|---|---|
| Module/type | ePWM1/2/3, C2000 Type4 F2838x |
| Timer period | `PWM_Period`, Clock cycles, dialog source |
| Counting | Up-Down; prescalers 1 and 1 |
| Period shadow | Counter equals zero |
| CMPA shadow | Counter equals zero (CTR=Zero) |
| A at ZERO / PRD | Do nothing / Do nothing |
| A at CMPA up / down | **Clear / Set** |
| A at CMPB | Do nothing |
| Deadband | Both enabled; Active high complementary; A is both sources; RED/FED=`PWM_DeadTime_Count` |
| Trip action | A and B forced Low for configured trip inputs |

The action labels were verified from the installed ePWM mask prompts, not inferred from parameter suffix numbers. For **interior** `0<CMPA<TBPRD`, the pre-deadband A signal is HIGH around zero and LOW around PRD, hence:

```text
D_A_pre_deadband = CMPA / TBPRD
```

Larger CMPA increases that HIGH duty. This is the opposite direction from `1-CMPA/TBPRD`. Endpoint event priority, CMPA>TBPRD, initial output state, deadband and external gate polarity prevent extending this formula blindly to 0/100% or out-of-range commands. No board polarity claim is made.

**Count mismatch:** real `EPWM_Clock=100 MHz`, `TBCLK=100 MHz`, `PWM_Period=TBCLK/(2*10000)=5000`, but `CPU_Clock=200 MHz` scales modulation. At zero voltage the raw command is already `CMPA=TBPRD=5000`; nonzero vectors produce phases above TBPRD (e.g. real-profile `d_current`: 5340.8203125, 4659.1796875, 4659.1796875). There is no visible clamp/scaling repair before ePWM. This is a blocking ambiguity for adopting an integrated motor-PWM reference, not a request to copy these counts into FPGA.

The supplied files also do not prove physical U/V/W wiring, gate-driver inversion, all-module synchronization, or successful motor operation with these exact settings. Those require separate evidence; Step 5 LED validation establishes none of them.

## 9. Timing contract and MIL differences

### DSP acquisition and command load

`D/FOC_Algorithm/ePWM1`: SOCA enabled at **CTR=PRD**, every first event; ePWM2/3 SOCA disabled. The ADC masks under **`D/ADC//QEP`** use a literal slash in their subsystem name (`ADC/QEP`; escaped as `ADC//QEP` for MATLAB paths):

- `ADCA_Current`: module A, SOC0, ADCIN0, 12-bit single-ended, `ePWM1_ADCSOCA`, acquisition window 24; posts ADCINT1.
- `ADCB_Current`: module B, SOC0, ADCIN0, same trigger/window, does not post interrupt.
- `ADCC_Current`: module C, SOC0, ADCIN2, same trigger/window, does not post interrupt.
- `PMSLM_Close_Loop_MBDL4/HWI_ADC_INT`: ADC group, **ADCA1_INT**, EOC event, function-call output directly triggers `D`. Preemption disabled, clear interrupt flags at end enabled.

Current entry: ADC result → double conversion → subtract auto-offset → gain `ADC_GainA/B/C=0.01664 A/count`. A/B `Switch/Switch1` output zero until `Offset_Cal_Done>0.5`; C `Select_IC_Feedback` selects measured C when `Three_Current_Sampling_EN>0.5`, otherwise `-(ia+ib)`. This is upstream conditioning, not part of the Clarke equations. The static nominal offsets are 2253; the auto-offset route supplies the actual subtractor values.

```text
ZERO -------- 50 us -------- PRD -------- 50 us -------- next ZERO
                             SOCA → ADC EOC → PI ISR → shadow write
                                                       CMPA shadow load
```

PWM period and requested control period are both **100 us / 10 kHz**. Nominal PRD-to-next-ZERO command delay is half a carrier period **provided conversion + ISR + writes finish before ZERO**. The files establish event configuration, not worst-case execution time or achieved deadline. Acquisition window 24 alone does not establish ADC EOC latency or prove B/C results are ready when A interrupts. A missed ZERO can defer the command to a later carrier. No cycle-accurate DSP timing or scope capture was performed.

### Core / MIL

Root `PMLSM_ControlCore_Block/control_tick_10k` is a Function-Call Generator with sample time `1e-4`, driving `C/function`. This is synchronous simulation scheduling, not an FPGA clock or a measured ISR duration.

`M/Control_Core` supplies currents and x feedback to the referenced core; electrical angle is derived **inside C**, not injected as a root theta port. `M/MIL_Logging/log_ia`, `log_ib`, `log_ic`, `log_id_meas`, `log_iq_meas`, `log_id_ref`, `log_iq_ref`, `log_theta_e`, `log_vd_cmd`, `log_vq_cmd`, `log_duty_a/b/c`, `log_vdc` are useful existing Timeseries outputs. The normal wrapper does not expose every Clarke/raw-PI/sector/dwell intermediate requested by this audit, so the extracted harness adds observation sinks.

`M` has `InitFcn`:

```text
init_PMLSM_control_params;
init_PMLSM_plant_params;
init_PMLSM_mil_test_params;
```

The last script sets **Current_Control_Mode=2** and replaces the PI gains. Merely assigning mode 1 before normal MIL initialization is insufficient. This audit did not run that full callback chain. A future full-MIL PI run must prove the post-initialization effective value is 1 and document its parameter overrides; the current extracted harness structurally contains PI only.

`M/Power_Plant_Feedback/Inverter_Model/PWM_Update_Delay` operates on the **raw count signals**, before phase normalization. Selection is `delay_mode + 3*accurate_enable`, zero-based:

| Selector | Behavior per phase |
|---:|---|
| 0 | Current command |
| 1 | `0.5*C[k] + 0.5*C[k-1]` |
| 2 | `C[k-1]`, Unit Delay Ts_ACR |
| 3 | `*_cmd_zoh`, sample time MIL_Current_Control_Ts_s |
| 4 | One `*_half_50us` delay after ZOH, sample time MIL_PWM_Delay_Substep_s |
| 5 | Two cascaded substep delays after ZOH |

Supplied defaults are `MIL_PWM_Update_Delay_Mode=1`, `Accurate_Enable=0`, `MIL_Current_Control_Ts_s=100 us`, `MIL_PWM_Delay_Substep_s=100 us`. Thus the selected half-delay is **an averaging approximation**, not a true held 50 us actuation delay. The block name `half_50us` does not make its default sample time 50 us. A future accurate half-period run must explicitly configure the substep and simulation schedule. All these delay ICs are **0.5**, despite the input being raw counts; they are not the 5000-count zero-voltage command.

MIL phase mapping at:

```text
M/Power_Plant_Feedback/Inverter_Model/Duty_To_DQ_With_AHC_DeadTime/
  Phase_A_DeadTime (and Phase_B_DeadTime, Phase_C_DeadTime)
```

uses `duty_norm = -1/PMLSM_pwm_period_counts` then `duty_active_high` (add 1), followed by the phase duty saturation `[0,1]`. With deadtime mode 0, `D_MIL=clip(1-C/7500,0,1)`. This has both a **different denominator** and **opposite slope** to the DSP pre-deadband formula. The zero-vector command maps to 1/3 on all phases in MIL (zero line-line average voltage), not 1/2. Counts above 7500 clip. MIL success therefore cannot certify the supplied DSP ePWM mapping.

### Distinct clocks and latencies for future FPGA

| Quantity | What is established |
|---|---|
| FPGA fabric clock | Accepted BX72 baseline 50 MHz, 20 ns |
| PWM carrier | Target 10 kHz, 100 us full up/down cycle |
| Candidate FPGA TBPRD | Ideal 50 MHz/(2×10 kHz)=2500, subject to future exact counter endpoint specification |
| Current transaction period | 100 us, independent of number of FPGA pipeline clocks |
| Algorithm pipeline latency | Not designed or measured in Step 6A |
| Command load latency | Future event contract needed; DSP reference intends next ZERO after PRD sampling |

Neither DSP 5000-count period nor source 10000-count modulation span is directly portable to 50 MHz. The accepted Step 1–5 learning PWM has different count/update semantics and must not silently become the motor PWM.

## 10. Minimal future FPGA PI-core interface recommendation — no implementation

One accepted transaction should capture a coherent set of physical-unit values:

- `ia`, `ib`, `ic` in A, preserving three-current Clarke. Two-current operation requires an explicit compatible reconstruction policy.
- `theta_e` in radians and **`we` in electrical rad/s**. `we` is necessary to reproduce the existing PI feedforward; omitting it restricts the reference to we=0 or changes the algorithm.
- `id_ref`, `iq_ref` in A; sampled positive `vdc` in V if dynamic-bus behavior is adopted.
- `sample_valid`, reset and enable with specified accepted-transaction semantics. The future policy must distinguish output inhibit, integrator reset and state hold; the source PI only establishes reset behavior. Optional `uq_zero_en` is a commissioning override, not required in the minimal normal-operation interface.

Outputs: three **explicitly named normalized compare fractions or normalized active-high duties**, `command_valid`, and observations `id`, `iq`, `ud_raw/uq_raw`, `ud_lim/uq_lim`, sector and saturation flag. After Review resolves section 8, a separate mapping can produce `cmp_u/v/w` for the chosen carrier. Do not name raw CPU-clock counts simply “duty”.

Gains, Ld/Lq/flux and Ts can be configuration constants. Numeric format, overflow behavior, trigonometric implementation, invalid-vdc behavior, sampling/backpressure, and reset of limiter history require later design decisions. Capture the same theta for both transforms in one transaction and update integrator/history once per accepted control sample, not every 50 MHz fabric clock. No speed/position-loop, startup, observer or advanced-controller interface is proposed.

## 11. Unresolved items and evidence needed

| ID | Exact file/block | What remains unresolved and why | Evidence needed to close |
|---|---|---|---|
| U1 | Both models' `FOC_Algorithm/SVPWMG/Duty\nCalculate/Gain{,1,2}`; real parameter script; `D/FOC_Algorithm/ePWM1..3` | 200 MHz CPU scaling produces a 10000-count modulation span against TBPRD 5000; no intervening repair | Review-approved intended time/count formula, correct runtime parameters and a separate verified compare-mapping test; do not infer a fix here |
| U2 | `D/FOC_Algorithm/ePWM1..3` versus MIL `.../Phase_A/B/C_DeadTime/duty_norm` | DSP interior HIGH duty grows with CMPA, MIL decreases; denominator 5000 versus 7500 | Approved phase/gate polarity convention and normalized mapping, actual driver inversion/wiring evidence, later safe waveform validation |
| U3 | Both core transform blocks `.../Variant/mcb/sinecos/Sine-Cosine Lookup` | Stored 1024 disagrees with resolved 800; linked library version affects numbers | Freeze/export the intended library configuration and resolve mask propagation under a separately authorized change; regenerated vectors if behavior changes |
| U4 | `D/ADC//QEP/ADCA_Current`, `ADCB_Current`, `ADCC_Current`; root `HWI_ADC_INT`; ePWM CMPA load | Simultaneous trigger does not prove conversion readiness, ISR deadline or atomic three-phase update before ZERO | ADC clock/latency and generated ISR ordering/WCET evidence or timestamped waveform measurement in a later task |
| U5 | `D/FOC_Algorithm/ePWM1..3` CMPA input and action qualifier | Register cast/rounding, equal-endpoint priorities, overrange outputs, module phase alignment not dynamically established | Generated-code/register audit and approved carrier boundary tests; no C build or hardware execution in this task |
| U6 | `F/dq_voltage_limiter/Constant1`, `F/SVPWMG/Udc` | Udc is constant-parameter driven; measured-bus propagation and invalid-vdc behavior not established | Explicit source of runtime Udc and a reviewed dynamic-bus/invalid-input contract |
| U7 | `M/.../PWM_Update_Delay/*_half_50us`, `*_z1`; MIL test parameters | Default half-delay is averaging, accurate substep defaults to 100 us, raw-count delay IC is 0.5 | Reviewed delay configuration/IC units and a time-resolved scheduling test before equating MIL with DSP |
| U8 | `F/SVPWMG/Sector\nCaculate` and `XYZ\nCalculate` | Rounded decimal boundaries differ slightly from dwell zero lines; finite precision affects edge selection | Freeze intended coefficients/tie rules and tolerances for future fixed-point work, rather than replacing them with textbook radicals |

These do not prevent reporting the stored/observed algorithm. They do prevent treating all supplied layers as one already-validated hardware golden contract. None was silently repaired.

## 12. Golden vectors, reproducibility and verification

**EXECUTED:** `coordination/reports/step6a_pi_foc_golden_vectors.csv`, **160 samples**, two explicitly labeled parameter profiles. The helper `scripts/reference_audit/step6a_pi_vectors.m` creates an unsaved in-memory Simulink model from copies of `Clack`, both linked transforms, `Id`, `Iq`, limiter and `SVPWMG`. It wires the mode-1 path directly, omits compensation with its audited enable=0, adds T1/T2 observation ports and workspace sinks, and removes exported-signal resolution metadata only on copied ports. Numerical source blocks are retained. A private reset data store is written before the copied PI blocks. The source model is never saved.

Coverage: zero, pure d/q current, common-mode rejection, theta 0/π/2/π/3π/2/2π, positive/negative errors, all six sector interiors, nominal decimal boundary directions, nonzero we feedforward, unsaturated and radially saturated outputs, repeated saturation and recovery, q-zero override, PI reset and release. Each independent case is preceded by two explicit reset rows; hold/recovery rows are intentionally sequential. CSV order, `time_s`, `pi_reset`, `uq_zero_en`, `we`, `kp/ki`, and delayed-correction columns preserve state semantics. Each gain profile starts from zero state.

Required intermediate columns are present. **Units:** currents A, voltages V, theta rad, we rad/s, T1/T2 seconds; `duty_a/b/c` are raw counts. `vdc=48` is fixed per this run, not a dynamically exercised bus input. The overmodulation rescale branch is documented from blocks but is not claimed covered by these limiter-constrained cases. The vectors are a **PI subpath golden trace**, not a full-MIL trajectory, a DSP register trace, or physical duty validation.

Reproduce in MATLAB with the current installed blocksets, without running reference scripts:

```matlab
addpath('D:\Project\FPGA_XC7A200T\scripts\reference_audit');
vectors = step6a_pi_vectors('D:\Project\FPGA_XC7A200T');
```

The Python checker reads, but never generates, golden data:

```text
python scripts/reference_audit/verify_step6a_vectors.py
PASS: 160 actual-source rows, 2926 checks, max absolute error 5.46e-12
```

It independently checks the reconstructed equations, delayed state transitions, actual 800-interval trig interpolation, dwell selection, count permutation and phase scaling. Sector comparisons within 1e-12 of a boundary use the captured sector for downstream checks rather than asserting an unstable floating-point tie; all other sector predicates are checked. Finite-value and six-sector coverage assertions also passed. The initial ideal-sine comparison exposed U3; ideal sine was not used to overwrite the Simulink data.

Repository checks: `git diff --check`, scoped staged diff and `git status` verify that only this report, the CSV and the two helper scripts are included. No change under `simulink模型/`; no new RTL, XDC, project build, `slprj`, `.slxc`, generated C or HDL is included. Pre-existing local changes to `BX72管脚分配表V2.1.xlsx`, `PWM_Breathe/PWM_Breathe.xpr`, and `PWM_Controller/PWM_Controller.xpr` are outside this commit and preserved. No SHA/hash verification was performed.

**Review handoff:** audit and source-block vectors complete; U1–U8 are explicit. Open PR title: **Step 6A: Audit basic PI FOC Simulink reference**. Stop for ChatGPT Review. No Step 6B work is authorized by this report.
