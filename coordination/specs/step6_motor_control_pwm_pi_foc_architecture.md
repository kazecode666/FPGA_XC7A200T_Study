# Step 6 — Motor-Control PWM + Basic PI-FOC Architecture

Date: 2026-09-17

Status: **Design specification for review**. Do not implement until this spec is approved.

## 1. Purpose

The project now moves from PWM learning demos to a reusable motor-control PL architecture.

The first objective is **not** to reproduce every feature in the historical DSP/Simulink project. The first objective is to build a clean and independently verifiable digital current-loop framework that can later connect to:

- ACM/AD9238 current sampling;
- encoder/electrical-angle acquisition;
- complementary outputs, dead time and trip protection;
- an eventual Zynq UltraScale+ MPSoC PL.

The first current-loop algorithm is the ordinary PI FOC path audited in Step 6A.

Advanced research controllers (DPCC, DPICC, PICDO-DPICC), speed loop, position loop, startup/alignment and commissioning-mode management are deferred.

---

## 2. Reference priority

When references disagree, use this priority:

1. **This FPGA motor-control contract** — timing, interfaces, PWM polarity/count semantics.
2. **Step 6A PI-FOC algorithm audit and golden vectors** — mathematical behavior.
3. **MIL/ControlCore Simulink model** — algorithm reference and later closed-loop comparison.
4. **Previously proven F28335 experience** — physical plausibility/reference only.
5. **Unverified F28388D code-generation integration** — historical reference only.

Do not import the unresolved F28388D/MIL raw PWM count conventions into the FPGA motor PWM.

Step 6A established several historical inconsistencies (raw modulation scaling, DSP/MIL polarity and period differences). They are not blockers for this FPGA architecture because this design defines a new normalized modulation contract.

---

## 3. Overall partition

```text
Testbench / future ADC+encoder adapter
 ia ib ic theta_e we id_ref iq_ref vdc sample_valid
                        |
                        v
              +--------------------+
              | foc_current_core   |
              |                    |
              | Clarke             |
              | sin/cos            |
              | Park               |
              | d/q PI             |
              | dq limiter         |
              | inverse Park       |
              | sector SVPWM       |
              +---------+----------+
                        |
                 duty_u/v/w [0,1]
                 command_valid
                        |
                        v
              +--------------------+
              | duty_to_cmp        |
              | round + clamp      |
              +---------+----------+
                        |
                 cmp_u/v/w command
                        |
                        v
              +--------------------+
              | motor_pwm_core     |
              | shared up/down TB  |
              | shadow compare     |
              | atomic ZERO load   |
              | 3-phase AQ         |
              +---------+----------+
                        |
                  pwm_u pwm_v pwm_w
```

The algorithm core and the PWM engine are separate units.

This separation is mandatory so that:

- FOC math can be verified without physical PWM;
- PWM timing can be verified without FOC;
- later ADC/encoder interfaces do not change the algorithm core;
- future Zynq migration changes board/processor integration rather than rewriting the motor-control math.

---

# Part A — Step 6B Motor PWM Core

## 4. Clock and carrier contract

Learning-board fabric clock:

```text
f_clk = 50 MHz
T_clk = 20 ns
```

Initial motor PWM switching frequency:

```text
f_pwm = 10 kHz
T_pwm = 100 us
```

Use one shared center-aligned up/down time base for all three phases.

Define:

```text
TBPRD = f_clk / (2*f_pwm) = 2500
```

Registered carrier states are:

```text
0,1,2,...,2499,2500,2499,...,2,1,0,...
```

The interval from one ZERO state to the next ZERO state is exactly:

```text
2*TBPRD = 5000 fabric clocks = 100 us
```

All U/V/W channels share this single carrier. Three motor phases do **not** use three phase-shifted carriers.

### Endpoint events

Expose one-clock registered event pulses:

- `carrier_zero`: current carrier state has reached ZERO;
- `carrier_peak`: current carrier state has reached TBPRD;
- `compare_load_event`: a pending three-phase shadow command became active.

The event definition must be deterministic and self-checking-testbench observable.

---

## 5. PWM compare/duty convention

The future algorithm interface is normalized active-high duty:

```text
duty = 0.0  -> 0% HIGH
duty = 0.5  -> 50% HIGH
duty = 1.0  -> 100% HIGH
```

The motor PWM engine itself accepts integer compare counts:

```text
0 <= CMP <= TBPRD
```

Mapping is performed in a separate `duty_to_cmp` layer:

```text
CMP = round(clamp(duty,0,1) * TBPRD)
```

Exact fixed-point duty representation is defined later with the FOC numeric-format task; the PWM core does not depend on that representation.

For an interior compare value:

```text
0 < CMP < TBPRD
```

use ePWM-like center-aligned action semantics:

```text
ZERO                     -> set phase output HIGH
up-count compare event   -> clear phase output LOW
down-count compare event -> set phase output HIGH
```

Therefore:

```text
HIGH duty = CMP / TBPRD
```

Special endpoint behavior is explicit and overrides event ambiguity:

```text
CMP = 0       -> constant LOW
CMP >= TBPRD  -> constant HIGH
```

No historical DSP or MIL `1-CMP/period` polarity is inherited.

---

## 6. Three-phase command transaction

U/V/W compare values form **one atomic command**.

Interface concept:

```text
cmp_u_cmd
cmp_v_cmd
cmp_w_cmd
cmp_cmd_valid
cmp_cmd_ready
```

A valid handshake captures all three phases into shadow registers on the same fabric clock.

A one-entry pending command is sufficient for the baseline.

Baseline rules:

1. `cmp_cmd_ready=1` only when no command is pending.
2. Accepted command -> latch U/V/W together -> `shadow_pending=1`.
3. While enabled, a pending command becomes active only on the next `carrier_zero` event.
4. All three active compares load in the same clock; `compare_load_event` pulses once.
5. A command presented on the same clock as ZERO is **not** eligible for that just-occurring ZERO; it targets the following ZERO.
6. Upstream logic must not overwrite a pending command. A future diagnostic may count/reject invalid attempts; silent partial updates are forbidden.

The baseline load mode is ZERO-only.

The architecture must keep carrier/load logic sufficiently isolated that future modes can add PRD or ZERO+PRD loading without redesigning the whole PWM core.

---

## 7. Reset and enable semantics

Reset is safe and deterministic:

```text
carrier = 0
direction = UP
active compares = 0
shadow compares = 0
shadow_pending = 0
outputs U/V/W = LOW
```

`pwm_enable=0`:

- forces all phase outputs LOW;
- holds carrier at ZERO with direction UP;
- produces no repeating ZERO/PEAK events;
- allows a new three-phase command to be preloaded safely while disabled.

For the baseline, a command accepted while disabled may update the active and shadow values immediately because outputs are inhibited and the carrier is stationary. Enabling then begins at ZERO with a complete coherent command.

No complementary outputs or dead-time are generated in Step 6B.

---

## 8. Step 6B observability

Expose enough internal/debug signals for learning and verification:

- `tbctr`;
- direction;
- `carrier_zero`;
- `carrier_peak`;
- shadow U/V/W compare;
- active U/V/W compare;
- `shadow_pending`;
- `compare_load_event`;
- three raw phase PWM outputs.

These do not all need to remain external top-level pins in the final system; they must be accessible to testbench/ILA integration.

---

## 9. Step 6B required tests

Use reduced `TBPRD` values in testbench for fast simulation while preserving identical logic.

At minimum verify:

1. full carrier period is exactly `2*TBPRD` fabric clocks;
2. ZERO and PEAK events occur once at the expected endpoints;
3. 0%, 25%, 50%, 75%, 100% phase duty;
4. center alignment around ZERO;
5. U/V/W can hold three different duty values simultaneously;
6. shadow command does not affect active PWM immediately;
7. U/V/W shadow values become active atomically at ZERO;
8. a mid-period command never resets/truncates the carrier;
9. a command arriving on the ZERO clock targets the following ZERO;
10. `pwm_enable=0` forces safe LOW and deterministic carrier state;
11. reset produces safe LOW and clears pending state;
12. preloading while disabled starts coherently when enabled.

Step 6B is a reusable core test. No physical motor board, bitstream or 40-pin output mapping is required yet.

---

# Part B — Step 6C Basic PI-FOC Current Core

## 10. First-version external transaction interface

The first PI-FOC version deliberately does **not** connect ADC9238 or an encoder.

All inputs come directly from testbench / golden vectors:

```text
ia
ib
ic
theta_e
we
id_ref
iq_ref
vdc
sample_valid
reset
enable
```

The core accepts one coherent transaction only when ready.

Conceptual handshake:

```text
sample_valid + sample_ready
```

First version supports only one FOC transaction in flight:

```text
IDLE -> BUSY -> COMMAND_VALID -> IDLE
```

No second sample may overwrite a transaction already being processed.

This is intentionally simpler than a fully streaming design. Individual internal math stages may still be pipelined/parallel.

---

## 11. Coherent sample rule

On one accepted `sample_valid`, latch together:

```text
ia, ib, ic,
theta_e,
we,
id_ref, iq_ref,
vdc
```

All calculations in that transaction must use this captured dataset.

In particular:

- Park and inverse Park use the same captured electrical angle;
- PI feedforward uses the same captured `we`;
- the voltage limiter/SVPWM use the same transaction's `vdc`;
- PI states update exactly once per accepted current-control transaction.

The 50 MHz fabric clock advances the hardware pipeline; it is **not** the PI integration sample rate.

---

## 12. Mathematical algorithm reference

The first FPGA algorithm follows the Step 6A audited PI path.

### Clarke

```text
i_alpha = (2/3)*(ia - 0.5*ib - 0.5*ic)
i_beta  = (ib - ic)/sqrt(3)
```

The algorithm core initially accepts three currents to match the golden model.

When the two-channel ADC is integrated later, a separate adapter may reconstruct:

```text
ic = -(ia + ib)
```

before this core. Do not silently change the Clarke implementation itself.

### Park

```text
id =  i_alpha*cos(theta_e) + i_beta*sin(theta_e)
iq = -i_alpha*sin(theta_e) + i_beta*cos(theta_e)
```

### PI + decoupling/feedforward

Per accepted control transaction `k`:

```text
e_d[k] = id_ref[k] - id[k]
e_q[k] = iq_ref[k] - iq[k]

ud_raw[k] = Kp*e_d[k] + x_d[k] - we[k]*Lq*iq[k]
uq_raw[k] = Kp*e_q[k] + x_q[k]
            + we[k]*(Ld*id[k] + psi_f)

x_d[k+1] = x_d[k] + Ki*Ts*e_d[k] - Kaw_d*du_d_z[k]
x_q[k+1] = x_q[k] + Ki*Ts*e_q[k] - Kaw_q*du_q_z[k]
```

`Ts = 100 us` for the baseline current loop.

The PI state update occurs once per accepted transaction, never once per 20 ns fabric clock.

The implementation shall allow both Step 6A PI gain profiles to be tested, but neither gain set is treated as final motor tuning until real hardware commissioning.

### dq circular voltage limiter

```text
Umax = 0.9*vdc/sqrt(3)
r = sqrt(ud_raw^2 + uq_raw^2)
s = min(1, Umax/(r + 1e-6))

ud_lim = s*ud_raw
uq_lim = s*uq_raw

du_d = ud_raw - ud_lim
du_q = uq_raw - uq_lim
```

Anti-windup correction is consumed according to the one-control-transaction delayed state semantics established by Step 6A.

### Inverse Park

```text
v_alpha = ud_lim*cos(theta_e) - uq_lim*sin(theta_e)
v_beta  = ud_lim*sin(theta_e) + uq_lim*cos(theta_e)
```

### Sector SVPWM

The first FPGA SVPWM reproduces the existing Sector -> XYZ -> T1/T2 -> phase-time algorithm from Step 6A, including its original sector numbering/tie behavior and audited coefficients for golden comparison.

Do not replace it with Min-Max SVPWM in the first baseline.

The historical Simulink raw output count is **not** the new hardware duty interface.

Convert the final phase times to normalized active-high duty:

```text
duty_phase = 2 * phase_time / Ts
```

Equivalent Step 6A raw-vector normalization for the current 200 MHz/100 us source is:

```text
duty_norm = raw_source_count / 10000
```

Thus the zero-vector source value `5000` becomes the clean FPGA value `0.5`.

The normalized duty is then passed to `duty_to_cmp`, not compared directly with historical DSP/MIL counts.

---

## 13. Sin/Cos implementation boundary

Create a device-specific wrapper boundary:

```text
sincos_core(theta_valid, theta) -> sin, cos, result_valid
```

The first hardware implementation may use AMD/Xilinx CORDIC configured for sine/cosine with deterministic latency.

The rest of the FOC RTL must not depend on CORDIC-specific ports.

Verification compares:

1. mathematical ideal sine/cosine;
2. Step 6A Simulink lookup values;
3. FPGA sincos wrapper result.

The first FPGA baseline does not need to reproduce the Simulink library's observed 800-interval lookup quantization exactly. Any difference must be bounded and documented.

---

## 14. Numeric-format rule

Resource optimization is not the first objective, but numeric correctness is mandatory.

The synthesizable baseline uses fixed-point arithmetic with generous intermediate width.

Exact Q formats are **not guessed in this architecture document**. Before Step 6C RTL implementation, create a numeric-format decision from:

- Step 6A golden-vector ranges;
- expected physical current/voltage/angle/speed limits;
- required quantization error;
- multiplication growth;
- saturation/rounding policy.

Rules:

- no silent wraparound in control quantities;
- define rounding/truncation explicitly;
- define saturation explicitly;
- keep intermediate products wide enough for first-pass correctness;
- reduce width only after the chain is proven.

---

## 15. Baseline timing contract

The motor-control schedule begins with the same simple timing shape as the proven DSP concept, but with deterministic FPGA execution.

At 10 kHz center-aligned PWM:

```text
ZERO ---------------- PEAK ---------------- ZERO
0 us                 50 us                100 us
                       |
                 baseline sample event
```

Initial integrated schedule:

1. `carrier_peak` marks the baseline current-sample transaction point.
2. A future ADC/encoder adapter will provide coherent input data and assert `sample_valid` around this event.
3. For the current testbench-only phase, the testbench directly asserts `sample_valid` with golden inputs.
4. FOC computation must complete before the next ZERO command-load boundary.
5. `motor_pwm_core` atomically loads the resulting three-phase command at the next ZERO.

Hard first-integration deadline:

```text
sample acceptance -> cmp command accepted < 2500 fabric clocks (50 us)
```

A design target substantially below that limit is desirable, but the first implementation prioritizes correctness and determinism over minimum resource/latency.

Later steps may study:

- ZERO/PRD dual update;
- different sample positions;
- real-time within-period update;
- latency compensation.

They must not be mixed into the first baseline.

---

## 16. Algorithm-core outputs and observability

Minimum functional outputs:

```text
duty_u
duty_v
duty_w
command_valid
```

Observation outputs for verification/ILA should include, directly or through debug access:

```text
i_alpha
i_beta
id
iq
sin_theta
cos_theta
ud_raw
uq_raw
ud_lim
uq_lim
v_alpha
v_beta
sector
t1
t2
saturation flag
transaction busy/done
latency cycle count
```

These observation points are important during learning and golden-vector comparison even if the final production interface is later reduced.

---

## 17. Verification strategy

Every algorithm block is independently self-checked before full-chain integration.

Recommended order:

1. `motor_pwm_core` standalone tests;
2. numeric-format decision;
3. `clarke_core`;
4. `sincos_core`;
5. `park_core` + `inverse_park_core` round-trip tests;
6. `pi_dq_core` including reset, feedforward, saturation recovery/anti-windup;
7. `dq_limiter_core`;
8. sector/XYZ/T1T2/duty SVPWM chain;
9. full `foc_current_core` against Step 6A golden vectors;
10. FOC -> duty_to_cmp -> motor_pwm integration with timing/deadline checks.

Golden comparison must use normalized duty, not the unresolved historical raw counts.

Fixed-point/AMD CORDIC results are allowed a documented numerical tolerance; bit-exact equality to floating-point Simulink is not required unless a later task explicitly defines it.

---

## 18. Device portability

The long-term target may move from XC7A200T to Zynq UltraScale+ MPSoC PL.

Therefore:

- keep main algorithm modules device-independent SystemVerilog where practical;
- isolate AMD IP such as CORDIC behind wrappers;
- do not instantiate Artix-7-specific primitives in algorithm modules without a wrapper/strong reason;
- keep board pins/XDC outside the algorithm/PWM cores;
- define clock/enable/valid interfaces explicitly.

---

## 19. Explicitly deferred functions

Not part of Step 6B/first Step 6C baseline:

- complementary high/low gate outputs;
- dead-time insertion;
- hardware trip/fault zone;
- minimum pulse width enforcement;
- physical 40-pin motor connector mapping;
- ACM9238 RTL interface;
- current offset/gain calibration;
- encoder/QEP interface;
- speed loop;
- position loop;
- startup/alignment/I-F state machine;
- DPCC/DPICC/PICDO;
- AXI/MPSoC integration;
- UART/Ethernet;
- HRPWM/sub-clock edge resolution;
- Min-Max SVPWM replacement;
- multi-sampling/within-period update optimization.

These will be added only after the basic digital current-loop framework is proven.

---

## 20. Planned step decomposition

### Step 6B — Motor PWM Core

Deliver a verified 10 kHz, three-phase, center-aligned PWM engine with shared up/down timebase, atomic three-phase shadow command and ZERO load.

### Step 6C1 — Numeric format + transform foundation

Freeze fixed-point formats; implement/test Clarke, sin/cos wrapper, Park and inverse Park.

### Step 6C2 — PI + limiter

Implement/test the audited d/q PI, feedforward, delayed anti-windup and dq circular limiter.

### Step 6C3 — Sector SVPWM

Implement/test Sector/XYZ/T1T2/phase-time computation and produce normalized duty U/V/W.

### Step 6C4 — Full PI-FOC transaction core

Connect transforms, PI, limiter and SVPWM; verify against Step 6A golden vectors and measure fabric-clock latency.

### Step 6D — FOC/PWM timing integration

Drive `motor_pwm_core` from PI-FOC command output, sample at PEAK and atomically load at the next ZERO. Verify deadline and command identity.

Only after this baseline is accepted should later steps add dead time/trip, ADC9238 and encoder hardware.

---

## 21. Acceptance criteria for this architecture

The architecture is accepted when the project agrees that:

1. the legacy learning `pwm_controller` is not the final motor PWM engine;
2. motor PWM is 10 kHz center-aligned with 50 MHz fabric and `TBPRD=2500`;
3. the FPGA defines active-high normalized duty independently of DSP/MIL raw counts;
4. three phases use one shared carrier and one atomic command transaction;
5. shadow compare loads on ZERO in the first baseline;
6. basic PI-FOC inputs come from testbench/golden vectors first, not ADC/encoder;
7. PI state updates once per accepted 100 us transaction, not every fabric clock;
8. `we` feedforward and delayed anti-windup are retained from the audited PI reference;
9. first SVPWM baseline reproduces the existing sector algorithm but outputs normalized duty;
10. CORDIC/IP details are isolated behind `sincos_core`;
11. fixed-point formats are frozen in a separate numeric-format decision before FOC RTL;
12. baseline sample point is PEAK and baseline command load is next ZERO;
13. advanced low-latency/multi-update methods are deferred until the deterministic baseline is measured.
