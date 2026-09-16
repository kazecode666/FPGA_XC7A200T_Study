# ChatGPT ↔ Codex Project Handoff

This file is the persistent coordination index for the FPGA learning project. GitHub is the source of truth between ChatGPT (planning/review) and Codex (execution).

## Working agreement

- ChatGPT owns architecture, task definition, design decisions, acceptance criteria, and PR review.
- Codex owns local repository inspection, RTL/testbench/Tcl/XDC edits, Vivado execution, report generation, commits, pushes, and PR creation.
- Do not rely on copied chat snippets when this file and the repository contain the current task.
- Do not use SHA-256/file-hash verification for this learning project. Use `git status`, `git diff`, reports, simulation, synthesis, implementation, timing, DRC, and hardware behavior instead.
- Do not guess board pins, I/O standards, clock frequencies, reset polarity, LED polarity, or device population. Hardware facts must be traced to repository evidence and, where available, physical hardware observation.
- Each implementation task is done on a feature branch and stops at an open PR for ChatGPT review. Do not merge the task PR unless explicitly instructed.
- Codex writes its execution summary to `coordination/reports/<task>_codex_report.md`.

## Accepted baseline

Completed and accepted:

- Step 1: self-checking PWM testbench.
- Step 2: compare-value semantics and boundary behavior.
- Step 2.5: registered PWM output aligned with counter state.
- Step 3: RTL synthesis baseline.
- Step 4: 50 MHz clock constraint, placement, routing, and post-route timing analysis.
- Step 5A: BX72 board-level LED blink bring-up.

Step 5A physical verification is complete:

- PR #6 is merged into `main`.
- Vivado Hardware Manager physically detected `xc7a200t`.
- Step 5A bitstream programmed successfully.
- LED1 physically alternated approximately 0.5 s OFF / 0.5 s ON.
- Holding KEY2 physically forced LED1 OFF.
- Releasing KEY2 physically restarted the 1 Hz blink sequence.

These hardware observations are now part of the accepted project baseline.

## Frozen hardware facts

- Target project part: `xc7a200tfbg484-2`.
- Physical JTAG detection: `xc7a200t`.
- Board clock: 50 MHz.
- `clk`: Y18, Bank 14, LVCMOS33.
- `key2_n`: V17, Bank 14, LVCMOS33, active LOW, external 4.7 kohm pull-up.
- `led1`: AA18, Bank 14, LVCMOS33, active HIGH.
- `CFGBVS = VCCO`.
- `CONFIG_VOLTAGE = 3.3`.

Do not re-guess or auto-assign these in later BX72 learning steps.

## Frozen PWM-core behavior

`pwm_controller` remains the verified core. Do not modify it unless a blocking defect is found and reported before redesign.

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

Current learning-core limitation: asserting `config_en` also resets the PWM counter to zero. Step 5B may use this deliberately at integer carrier-period boundaries, but it is not the final shadow-compare architecture for SPWM/SVPWM.

## Current task

**Step 5B — BX72 PWM Breathing LED**

Full executable task specification:

`coordination/tasks/step5b_breathing_led.md`

Codex must read that file before editing RTL/XDC.

High-level target:

- add an independent `pwm_breathe_top`;
- preserve `pwm_controller` and the Step 5A blink demo;
- real PWM carrier = 1 kHz (`N=50_000` at 50 MHz);
- compare update every 10 PWM periods = 10 ms;
- compare step = 500 = 1% duty increment;
- trajectory `50_000 → 0 → 50_000`;
- visible breathing period ≈ 2 s;
- add self-checking Step 5B TB with reduced parameters;
- rerun core and Step 5A regressions;
- use separate Step 5B synthesis/implementation runs and reports;
- generate a Step 5B bitstream only after timing/DRC pass;
- do not program physical hardware from Codex;
- write `coordination/reports/step5b_codex_report.md`;
- create PR `Step 5B: Add BX72 PWM breathing LED demo`;
- stop at the open PR and wait for ChatGPT review.

## Codex start command

When asked to execute Step 5B, use the repository as the task source:

```text
Read coordination/HANDOFF.md and coordination/tasks/step5b_breathing_led.md.
Execute the current Step 5B task exactly as specified.
Start from latest main, create the specified feature branch, run all required regressions/Vivado checks, write the Codex report, create the PR, and stop at the open PR. Do not continue to Step 6.
```
