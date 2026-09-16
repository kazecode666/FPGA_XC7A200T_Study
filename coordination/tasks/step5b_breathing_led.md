# Step 5B — BX72 PWM Breathing LED

This task is the current ChatGPT → Codex execution handoff for the FPGA learning project.

## Preconditions

- PR #6 (`Step 5A: Add BX72 LED blink board bring-up`) is merged into `main`.
- The user physically verified the fitted FPGA as `xc7a200t` in Vivado Hardware Manager.
- Step 5A bitstream programming succeeded on the physical BX72.
- Physical Step 5A behavior was confirmed:
  - LED1 alternates approximately 0.5 s OFF / 0.5 s ON.
  - Holding KEY2 turns LED1 OFF.
  - Releasing KEY2 restarts the 1 Hz blinking sequence.
- Pull latest `main` before creating the Step 5B branch.

## Frozen hardware facts from Step 5A

Do not re-guess or auto-assign these values:

- Target device: `xc7a200tfbg484-2` (physical JTAG detection confirmed `xc7a200t`).
- Board clock: 50 MHz.
- `clk`: PACKAGE_PIN `Y18`, Bank 14, `LVCMOS33`.
- `key2_n`: PACKAGE_PIN `V17`, Bank 14, `LVCMOS33`, active LOW, external 4.7 kohm pull-up.
- `led1`: PACKAGE_PIN `AA18`, Bank 14, `LVCMOS33`, active HIGH.
- `CFGBVS = VCCO`.
- `CONFIG_VOLTAGE = 3.3`.

Step 5A's `pwm_demo_top`, constraints, reports, runs, and behavior are historical baselines and must remain reproducible.

## Frozen PWM-core behavior

Do not modify `pwm_controller` in Step 5B unless an actual blocking defect is found and reported before any redesign.

Definitions:

- `N = period_set`
- `C = compare_value_set`
- for `N > 0`, counter runs `0 ... N-1`
- `counter >= C` → PWM HIGH
- `counter < C` → PWM LOW
- `C = 0` → constant HIGH
- `C >= N` → constant LOW
- `N = 0` → disabled / LOW
- `HIGH duty = (N - C) / N`

Important limitation of the current learning core:

- asserting `config_en` loads the new period/compare values **and resets `time_cnt` to zero**.
- Therefore Step 5B is a learning/demo architecture, not the final shadow-compare architecture for SPWM/SVPWM.

## Goal

Add a separate BX72 board demo that uses a high-frequency PWM carrier and a slowly changing compare value so LED1 visibly breathes:

```text
OFF → gradually brighter → brightest → gradually dimmer → OFF → repeat
```

Do not replace or mutate the Step 5A blink demo. Add an independent board top, suggested name:

`pwm_breathe_top.sv`

The purpose is to learn the separation between:

1. system clock frequency;
2. PWM carrier frequency;
3. compare/duty update rate;
4. slow modulation envelope.

## Real hardware parameters

System clock:

- `F_CLK = 50_000_000 Hz`

PWM carrier:

- target `F_PWM = 1_000 Hz`
- therefore `PWM_PERIOD_CYCLES = 50_000`

Brightness/compare update:

- update once every `10` complete PWM periods;
- update interval = `10 ms`;
- `COMPARE_STEP = 500`, equal to 1% of 50,000.

Compare trajectory:

```text
50_000 → 49_500 → ... → 500 → 0 → 500 → ... → 49_500 → 50_000 → repeat
```

Because:

`HIGH duty = (N - C) / N`

this means:

```text
C = 50_000 →   0% HIGH → LED OFF
C = 37_500 →  25% HIGH
C = 25_000 →  50% HIGH
C = 12_500 →  75% HIGH
C =      0 → 100% HIGH → LED brightest
```

At 100 steps × 10 ms per half-cycle:

- OFF → brightest ≈ 1 s;
- brightest → OFF ≈ 1 s;
- full breathing cycle ≈ 2 s.

A linear duty ramp is acceptable for this learning step. Do not add gamma/perceptual correction yet.

## Architecture

Create a new board-level top around the frozen core:

```text
BX72 50 MHz clk
      │
      ├──→ reset-release synchronizer ← KEY2
      │
      ├──→ PWM/update scheduler
      │       ├── update interval counter
      │       ├── compare_command
      │       └── direction (brighten/dim)
      │
      └──→ pwm_controller
              │
              └──→ LED1
```

Board-facing ports remain only:

```systemverilog
input  clk;
input  key2_n;
output led1;
```

Reuse the Step 5A reset concept:

- asynchronous assertion from KEY2;
- two-flop synchronous release;
- `ASYNC_REG=TRUE`;
- no new reset synchronizer inside `pwm_controller`.

## Update scheduling requirement

The current core resets `time_cnt` whenever `config_en` is asserted. Therefore compare updates must be deliberately aligned to an integer number of carrier periods.

For the default hardware parameters:

```text
1 PWM period       = 50_000 clk
10 PWM periods     = 500_000 clk
compare update     = every 500_000 clk
```

The update scheduler must start/reset in a deterministic relationship with the initial PWM configuration, and after each compare update its interval counter must restart so subsequent updates remain phase-aligned.

Do not assert `config_en` continuously.

Each configuration/update event must be exactly one clock interval as observed by the PWM core.

Do not reach into `u_pwm.time_cnt` hierarchically from synthesizable top-level RTL to schedule updates. Keep the top-level scheduler self-contained.

## Compare endpoint behavior

The modulation state must never generate compare values outside:

`0 <= compare_command <= PWM_PERIOD_CYCLES`

Required direction behavior:

- start/reset at `C = N` (LED OFF);
- first modulation direction = toward `C = 0` (brightening);
- at `C = 0`, reverse direction without underflow;
- at `C = N`, reverse direction without overflow;
- repeat continuously.

Avoid unsigned wraparound at both endpoints.

## Step 5B simulation

Add a self-checking board-level testbench, suggested name:

`pwm_breathe_top_tb.sv`

Do not simulate real 50,000-cycle carrier periods and a 2-second breathing cycle.

Parameterize the new top and override with small values in simulation.

Recommended simulation parameters:

```text
PWM_PERIOD_CYCLES = 8
UPDATE_PWM_PERIODS = 2
COMPARE_STEP = 2
```

Expected compare sequence:

```text
8 → 6 → 4 → 2 → 0 → 2 → 4 → 6 → 8
```

Corresponding HIGH duty:

```text
0% → 25% → 50% → 75% → 100% → 75% → 50% → 25% → 0%
```

The testbench must automatically verify at least:

1. asynchronous reset assertion;
2. two-edge synchronized reset release;
3. deterministic startup at `C=N`, LED OFF;
4. each `config_en` pulse is one clock interval;
5. compare sequence is exactly the expected up/down sequence;
6. compare never goes below zero or above N;
7. direction reverses correctly at both endpoints;
8. update interval equals exactly `UPDATE_PWM_PERIODS` complete PWM periods according to the top scheduler;
9. measured PWM HIGH/LOW counts match the active compare value for representative levels including 0%, 25%, 50%, 75%, and 100%;
10. LED output matches the PWM core output and active-high board polarity;
11. KEY2 pressed during operation forces LED OFF asynchronously;
12. KEY2 release restarts from OFF / `C=N` deterministically;
13. watchdog/fatal behavior prevents a hung simulation from appearing as PASS.

Keep the testbench readable; no UVM/class framework.

## Regression requirements

Before declaring Step 5B successful, rerun all of:

1. `pwm_controller_tb` — must still PASS.
2. `pwm_demo_top_tb` — Step 5A regression must still PASS.
3. `pwm_breathe_top_tb` — new Step 5B self-check must PASS.

Do not modify old testbench expectations merely to make regressions pass.

## Board constraints

Create a dedicated Step 5B constraint set/file rather than overwriting Step 5A history.

Use the already audited and physically verified board assignments:

```text
clk     Y18  LVCMOS33
key2_n  V17  LVCMOS33
led1    AA18 LVCMOS33
```

Include:

```tcl
create_clock -name sys_clk -period 20.000 [get_ports clk]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
```

Carry forward the narrow asynchronous-reset exception strategy only if it still targets exactly the intended synchronizer CLR pins.

Do not add invented synchronous input/output delays for KEY2 or LED1 simply to remove methodology warnings.

Do not suppress NSTD-1/UCIO-1/DRC severity.

## Vivado flow

Create separate Step 5B runs so Step 5A results remain intact.

Suggested run names:

- `step5b_synth`
- `step5b_impl`

Run with Vivado 2026.1:

1. all three behavioral regressions;
2. synthesis;
3. implementation through `route_design`;
4. post-route timing summary;
5. setup/hold worst paths;
6. DRC;
7. methodology;
8. CDC/reset checks as applicable;
9. utilization / IO / route status;
10. bitstream generation only if all blocking checks pass legitimately.

Target device remains:

`xc7a200tfbg484-2`

Do not program hardware from Codex.

## Acceptance criteria

Step 5B build can be called PASS only if:

- core regression PASS;
- Step 5A board regression PASS;
- Step 5B self-check PASS;
- synthesis completes;
- route_design completes;
- WNS >= 0;
- TNS = 0;
- WHS >= 0;
- THS = 0;
- no blocking routed DRC violations;
- all three real board ports have the audited PACKAGE_PIN/IOSTANDARD;
- bitstream generation completes;
- no RTL change to `pwm_controller`;
- no functional change to `pwm_demo_top`;
- Step 5A reports/runs are not overwritten.

Remaining methodology warnings such as the human-visible LED lacking a synchronous output delay may be documented rather than hidden when technically justified.

## Reports and evidence

Write the complete Codex execution handoff to:

`coordination/reports/step5b_codex_report.md`

Store Step 5B text evidence under a separate directory, suggested:

`docs/reports/step5b/`

Include at least:

- regression results;
- synthesis/implementation status;
- utilization;
- timing summary and worst setup/hold paths;
- DRC;
- methodology;
- CDC/reset report if applicable;
- IO assignments;
- route status;
- final build result;
- exact local `.bit` path;
- explicit `Physical hardware: NOT TESTED` until the user programs it.

Do not commit Vivado generated run directories, DCPs, `.bit` files, logs, journals, or caches.

## Git workflow

Create feature branch from the latest merged `main`:

`step5b-breathing-led`

Suggested primary commit:

`feat: add BX72 PWM breathing LED demo`

Suggested PR title:

`Step 5B: Add BX72 PWM breathing LED demo`

Do not merge the PR. Stop for ChatGPT review.

## Physical handoff after PR acceptance

If a valid bitstream is generated, the Codex report must tell the user how to:

1. open Hardware Manager;
2. confirm the detected device remains `xc7a200t`;
3. program the Step 5B `pwm_breathe_top.bit`;
4. observe LED1 breathing approximately 1 s brighter + 1 s dimmer;
5. hold KEY2 and verify LED1 OFF;
6. release KEY2 and verify breathing restarts from OFF;
7. report the physical observation back to ChatGPT.

Do not claim physical hardware PASS on behalf of the user.

## Stop condition

Stop at the open Step 5B PR. Do not continue to Step 6, triangular carrier, SPWM, shadow registers, dead time, or complementary PWM until ChatGPT reviews Step 5B and the user performs the physical LED test.
