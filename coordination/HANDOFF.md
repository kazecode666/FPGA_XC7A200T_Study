# ChatGPT ↔ Codex Project Handoff

This file is the persistent coordination point for the FPGA learning project. GitHub is the source of truth between ChatGPT (planning/review) and Codex (execution).

## Working agreement

- ChatGPT owns architecture, task definition, design decisions, acceptance criteria, and PR review.
- Codex owns local repository inspection, RTL/testbench/Tcl/XDC edits, Vivado execution, report generation, commits, pushes, and PR creation.
- Do not rely on copied chat snippets when this file and the repository contain the current task.
- Do not use SHA-256/file-hash verification for this learning project. Use `git status`, `git diff`, `git log`, reports, simulation, synthesis, implementation, timing, DRC, and hardware behavior instead.
- Do not guess board pins, I/O standards, clock frequencies, reset polarity, or LED polarity. Hardware facts must be traced to the BX72 repository documents.
- Each task is done on a feature branch and stops at an open PR for ChatGPT review. Do not merge the task PR unless explicitly instructed.
- Codex should write its execution summary to `coordination/reports/<task>_codex_report.md` so ChatGPT can review the result directly from GitHub.

## Current baseline

Completed and accepted:

- Step 1: self-checking PWM testbench
- Step 2: compare-value semantics and boundary behavior
- Step 2.5: registered PWM output aligned with counter state
- Step 3: RTL synthesis baseline
- Step 4: 50 MHz clock constraint, placement, routing, and post-route timing analysis

Step 4 PR #5 has been accepted by ChatGPT. Before starting Step 5A, confirm that PR #5 has been merged into `main` and pull the latest `main`.

## Frozen PWM-core behavior

`pwm_controller` remains the verified core. Do not modify it in Step 5A unless an actual blocking defect is found and reported first.

Definitions:

- `N = period_set`
- `C = compare_value_set`
- for `N > 0`, counter runs `0 ... N-1`
- `counter >= C` → PWM HIGH
- `counter < C` → PWM LOW
- `C = 0` → constant HIGH
- `C >= N` → constant LOW
- `N = 0` → disabled / LOW

For normal operation:

`HIGH duty = (N - C) / N`

## Current task: Step 5A — BX72 board-level LED blink bring-up

### Goal

Create the first real board-level top around the verified PWM core, generate a valid bitstream for the BX72, and use the on-board LED instead of an oscilloscope for physical verification.

Target observable behavior after programming:

- LED1 toggles at 1 Hz total period.
- Nominally 0.5 s ON / 0.5 s OFF, adjusted for the actual LED electrical polarity confirmed from the schematic.
- KEY2 is used as the external reset only if the repository hardware documents confirm its signal/polarity and FPGA connection.

### Hard gate 1 — board-document audit before RTL/XDC changes

Inspect all of the following local repository files:

- `BX72-251215.pdf` — schematic
- `BX72_装配图.pdf` — assembly drawing
- `BX72管脚分配表V2.1.xlsx` — pin assignment table
- `BX72用户测试说明.txt` — functional notes

Cross-check and record, with document/page/sheet/row evidence where possible:

1. FPGA part/package and whether it matches `xc7a200tfbg484-2`.
2. On-board oscillator frequency and clock net name.
3. FPGA PACKAGE_PIN for the 50 MHz clock input.
4. LED1 FPGA PACKAGE_PIN.
5. LED1 electrical polarity: FPGA HIGH lights LED or FPGA LOW lights LED.
6. KEY2 FPGA PACKAGE_PIN.
7. KEY2 electrical polarity and pull-up/pull-down arrangement.
8. I/O bank(s) used by clock, LED1, KEY2.
9. Relevant bank voltage(s) and therefore justified IOSTANDARD(s).
10. Configuration-bank facts needed for `CFGBVS` / `CONFIG_VOLTAGE`, if the board documents provide them.

If the schematic, spreadsheet, and any existing BX72 test project disagree on a pin or voltage, STOP. Do not guess. Report the conflict in the Codex report before creating a bitstream.

Repository text already indicates that LED1 is a user LED, KEY2 is used as reset in the vendor/user test flow, and the board has dedicated test behavior for the LEDs; exact FPGA pins and electrical polarity still require the cross-document audit above.

### Architecture

Do not expose the PWM core's 64-bit configuration buses as board pins.

Create a board-level top, suggested name:

`pwm_demo_top.sv`

Conceptual hierarchy:

```text
BX72 50 MHz clock ───────────────┐
                                 │
KEY2 ─→ reset synchronizer ──────┤
                                 ↓
                           pwm_demo_top
                                 │
             constants + one-shot config_en
                                 │
                                 ↓
                           pwm_controller
                                 │
                                 ↓
                         LED polarity mapping
                                 │
                                 ↓
                               LED1
```

Board-level top should have only the real board-facing ports needed for this experiment, ideally clock, KEY2/reset, and LED1.

### Reset

Implement asynchronous assertion + synchronous deassertion at the board/system level.

Do not bury a new synchronizer inside `pwm_controller`.

Use a small 2-FF reset-release synchronizer (or an equivalently clear implementation) after confirming KEY2 polarity. The core should receive the synchronized internal reset.

Document the difference between:

- external asynchronous reset input;
- internal synchronized reset release.

### Fixed PWM configuration for visible blink

Assuming the audited board clock is confirmed as 50 MHz:

- `period_set = 50_000_000`
- `compare_value_set = 25_000_000`

This gives:

- PWM period = 1 s
- HIGH duration = 0.5 s
- LOW duration = 0.5 s

Do not hold `config_en` HIGH continuously, because the PWM core clears/reconfigures its counter while `config_en` is asserted.

Generate a deterministic one-clock `config_en` pulse after internal reset release so the constants are loaded once and the PWM then runs freely.

### LED polarity

Do not assume active-high or active-low.

After the schematic audit, map the PWM output explicitly to LED1 so that a 50% core PWM visibly produces equal ON/OFF times.

Document the mapping, e.g. either:

```text
LED1 = pwm_core_out
```

or

```text
LED1 = ~pwm_core_out
```

with the schematic reason.

### Simulation

Keep the original PWM-core testbench intact.

Add a small board-top testbench if useful. Do not simulate 50 million clocks merely to prove a blink.

Preferred approach: make the board demo top's period/compare constants parameterizable with hardware defaults of `50_000_000 / 25_000_000`, and override them with small values in the top-level testbench.

The board-top simulation should verify at least:

- reset assertion/deassertion behavior;
- one-shot `config_en` behavior;
- PWM starts after reset;
- LED polarity mapping;
- reset during operation restarts the demo deterministically.

Do not overbuild a verification framework.

### Board XDC

Create a dedicated Step 5A board XDC rather than mutating the Step 4 learning constraint into a mixture of temporary and real constraints.

The XDC must use only hardware-audited values for:

- clock PACKAGE_PIN;
- clock IOSTANDARD;
- `create_clock` at the audited board frequency;
- LED1 PACKAGE_PIN / IOSTANDARD;
- KEY2 PACKAGE_PIN / IOSTANDARD;
- any justified configuration-voltage properties.

Do not add arbitrary `set_input_delay` / `set_output_delay` for the pushbutton/LED just to remove methodology messages. Explain why these slow human-interface signals are handled as board-control GPIO for this bring-up rather than pretending they form a synchronous external bus.

### Vivado flow

Set `pwm_demo_top` as the Design Top for the Step 5A board build.

Run:

1. Behavioral simulation (core regression remains intact; run board-top TB if added).
2. Synthesis.
3. Implementation through route_design.
4. Timing summary.
5. DRC.
6. Generate Bitstream only if the real pin/IOSTANDARD audit is complete and blocking DRCs are resolved legitimately.

Never lower NSTD-1/UCIO-1 severity to force bitstream generation.

Do not use auto-assigned I/O locations as if they were real BX72 pins.

### Timing/DRC acceptance

For the real board top:

- `sys_clk` must be the audited on-board clock (expected 50 MHz only if confirmed by the documents).
- Setup and hold for internal synchronous paths must pass.
- No unconstrained board ports should remain for PACKAGE_PIN/IOSTANDARD.
- NSTD-1 and UCIO-1 must be gone because they are actually fixed, not suppressed.
- Any remaining DRC/methodology warning must be explained.

### Bitstream / hardware handoff

If bitstream generation succeeds, do not claim physical PASS on behalf of the user.

Produce a concise manual hardware procedure in the Codex report:

1. connect/power BX72 safely;
2. connect JTAG;
3. open Hardware Manager;
4. program the generated `.bit`;
5. identify LED1 using the assembly drawing;
6. expected LED1 behavior: 0.5 s ON / 0.5 s OFF;
7. press/release KEY2 and record the expected reset/restart behavior;
8. user reports the physical result back to ChatGPT.

Do not require an oscilloscope for Step 5A.

### Step 5B is deferred

Do NOT implement the breathing LED in Step 5A.

After the user physically confirms Step 5A, the next task will be Step 5B:

- high-frequency PWM carrier;
- slowly varying compare value;
- visible LED breathing;
- preparation for dynamic compare update / SPWM concepts.

## Git workflow for Step 5A

Start only after Step 4 PR #5 is merged.

Suggested branch:

`step5a-bx72-led-blink`

Suggested commit:

`feat: add BX72 PWM LED blink board bring-up`

Suggested PR title:

`Step 5A: Add BX72 LED blink board bring-up`

Do not merge the PR.

## Required Codex report

Create:

`coordination/reports/step5a_codex_report.md`

It must contain:

- branch / commit / PR URL;
- board-document audit table with source evidence;
- exact clock/LED1/KEY2 pins and IOSTANDARDs;
- LED and KEY2 polarity evidence;
- new/modified files;
- board-top architecture;
- reset synchronizer explanation;
- one-shot config explanation;
- simulation result;
- synthesis result;
- implementation result;
- WNS/TNS/WHS/THS;
- DRC result;
- bitstream generated: Yes/No;
- exact bitstream path if generated;
- unresolved warnings/blockers;
- manual programming/LED verification procedure;
- explicit statement that physical hardware PASS still awaits the user's observation.

## Stop condition

Stop at the open Step 5A PR and wait for ChatGPT review. Do not continue to Step 5B.
