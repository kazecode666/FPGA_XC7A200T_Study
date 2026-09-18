# Three-phase motor PWM core

`rtl/motor_pwm_core.sv` is device-independent SystemVerilog. It is separate
from the legacy learning `pwm_controller` and uses one shared U/V/W carrier.
The standalone `Motor_PWM/Motor_PWM.xpr` references these RTL/TB files.

## Carrier and phase outputs

Default `TBPRD=2500`, `COUNTER_WIDTH=$clog2(TBPRD+1)=12`:

```text
TBPRD = f_clk / (2*f_pwm)
50 MHz / (2*10 kHz) = 2500
carrier: 0,1,...,2500,2499,...,1,0
ZERO-to-ZERO: 5000 clocks = 100 us
HIGH duty = CMP / TBPRD     (0 <= CMP <= TBPRD)
```

Supported parameters require `TBPRD>=2` and a counter width sufficient to
represent it. Compare inputs are unsigned counts, **not normalized duty**.
For each phase, CMP=0 is constant LOW and CMP>=TBPRD is constant HIGH.
For interior compares, HIGH is centered about ZERO: clear when counting up
into CMP, set when counting down into CMP. Equivalent level rule:

```text
up half:   tbctr < CMP
down half: tbctr <= CMP
```

At PEAK, `count_up=0`; at ZERO, `count_up=1`. Carrier, direction, active
compare and registered PWM outputs describe the same edge (no extra lag).
`carrier_peak` pulses on entering TBPRD; `carrier_zero` pulses on returning
from the down half to zero. Both are one clock wide. Enabling from stationary
zero exposes a registered ZERO/UP state on the first enabled edge, with PWM
computed from the preloaded active tuple and no ZERO/PEAK/load event. Counting
starts on the following edge. PEAK occurs TBPRD clocks after that startup edge;
the first returned ZERO occurs 2*TBPRD clocks after it. Thus the very first
enabled cycle has the full period and duty, including CMP=1's opening HIGH
interval. Reset and each sampled disable re-arm this startup behavior.

## Atomic command interface

All inputs except asynchronous reset must be synchronous to `clk`. A command
is accepted on a rising edge only when `cmp_cmd_valid && cmp_cmd_ready`.
The three `cmp_*_cmd` values form one transaction.

- Enabled acceptance writes all shadow registers and sets `shadow_pending`.
- While pending, ready is LOW; neither partial writes nor overwrites occur.
- The **old** pending tuple loads all active compares together at the next
  running ZERO, asserting `compare_load_event` for that clock only.
- A command accepted on the very edge entering ZERO is too late for that
  ZERO and loads one complete carrier period later. There is no bypass.
- A pending load edge still has pre-edge ready LOW; it cannot simultaneously
  accept a replacement command. A held valid can be accepted on a later edge
  once ready returns HIGH, as in a normal ready/valid interface.
- Commands never reset or retime the carrier. No PRD-load mode exists yet;
  `load_shadow` isolates boundary eligibility from capture and phase logic.

## Disable and reset

`pwm_enable=0` takes effect at the next rising edge: raw outputs LOW,
counter ZERO/UP, all event pulses LOW. Stale pending state is discarded;
active/shadow configuration values are retained, without silently applying
the discarded command. After reset release, ready is HIGH while disabled.
A disabled accepted command immediately preloads **both** complete shadow
and active tuples, without setting pending or asserting a load event.

`reset_n` is active-LOW, asynchronously asserted. It clears active/shadow
compares, pending, PWM outputs and events, and sets the counter to ZERO/UP.
Ready is LOW during reset. A future board wrapper must synchronize reset
release; this portable core has no synchronizer or physical pin contract.

Debug ports expose counter, direction, endpoint events, shadow/active tuples,
pending and load event for testbench or later ILA integration.

## Verification and build

`tb/motor_pwm_core_tb.sv` uses TBPRD=8 at a 50 MHz simulation clock.
It checks the independent modulo-time carrier, atomic command scoreboard,
every phase level, complete-cycle HIGH counts, symmetric halves, all four-bit
compare values (including overrange), every command arrival phase, pending
rejection, ZERO collision, disabled cancellation/preload and asynchronous
reset during activity. Stimulus/check helpers settle away from rising edges;
the monitor checks after nonblocking updates. A watchdog and `$error/$fatal`
prevent silent success. Required marker:

```text
ALL STEP 6B MOTOR PWM TESTS PASSED
```

From repository root with Vivado 2026.1:

```text
vivado -mode batch -nojournal -log step6b_local.log -source scripts/step6b_motor_pwm_build.tcl
```

The build runs the motor and three unchanged legacy simulations, synthesizes
the real default, and routes `xc7a200tfbg484-2` with only a 20 ns clock XDC.
Evidence is in `docs/reports/step6b/`; internal timing is not external I/O
timing sign-off. Each invocation preserves prior run directories rather
than deleting them. No bitstream is generated.

Deferred: normalized fixed-point `duty_to_cmp`, FOC/SVPWM, dead time,
complementary outputs, trip/fault protection, minimum pulse width, ADC,
encoder, AXI and board mapping. These raw outputs are not a verified safe
power-stage driver.
