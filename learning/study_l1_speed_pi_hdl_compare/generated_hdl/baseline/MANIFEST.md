# HDL Coder baseline manifest

Generated SystemVerilog is copied byte-for-byte from the passing fresh run. Do not edit these files; change the HDL-facing model/configuration and regenerate.

| Item | Recorded value |
|---|---|
| MATLAB | R2026b GA / 26.2.0.3386108 |
| HDL Coder / HDL Verifier / Simulink | 26.2 / 26.2 / 26.2 |
| Language | SystemVerilog |
| Frozen numerical source | `models/speed_pi_fixed.slx` from merged PR38 |
| B1 SHA256 | `b87195c56830254e65ecc6b9b2d395c2e48c30319fd9c804e71474757742f26c` |
| HDL-facing source | `models/speed_pi_hdl.slx` |
| DUT / top | `speed_pi_hdl/HDLCore` / `HDLCore` |
| Part | `xc7a200tfbg484-2`, audited from all four existing XPR files and installed Vivado part database |
| Clock | one physical 50 MHz / 20 ns clock; speed events first at 0.9 ms, then every 1 ms |
| Clock/reset ports | `clk`, synchronous active-high `init_reset`, `clk_enable`; sampled `pi_reset`, `enable`, `sample_tick` |
| Boundary pipeline | InputPipeline=1, OutputPipeline=1; Coder reports 2 cycles |
| Valid alignment | source launch just after edge k -> input capture k+1 -> PI/output hold k+2; 40 ns in the testbench |
| Update interval | 50,000 physical clocks; sustained-high tick is one event |
| Generation timestamp | 2026-10-04 17:18:43, Asia/Hong_Kong |
| Generation base commit | `33536f7c0567d53a1c0530e316aa047971d3f51b`; generator script/config are included in this checkpoint commit |
| Timing scope | non-project OOC IP core, 2 ns interface budgets, BUFGCTRL_X0Y0 clock-source assumption |

Generation: `study_l1_run_hdlcoder(freshRunDirectory)` calls `checkhdl('speed_pi_hdl/HDLCore')` before `makehdl`. [Exact configuration](../../reports/checkpoint_b/generator_config.json), [all effective parameters](../../reports/checkpoint_b/codegen/generator_parameters.txt), [native generation status/latency](../../reports/checkpoint_b/codegen/hdlcodegenstatus.json).

TargetLanguage=SystemVerilog, TargetFrequency=50, TriggerAsClock=off, ResetType=Synchronous, Traceability=on, GenerateValidationModel=on. Resource sharing/adaptive/distributed pipelining are not enabled. Delay balancing/absorption handles the two boundary pipeline settings. EDAScriptGeneration=off avoids the default unrelated-device EDA sample template; execution uses `scripts/study_l1_vivado_baseline.tcl` with the audited part.

| Untouched output file | SHA256 |
|---|---|
| [PI.sv](PI.sv) | `37ced0b1a1532011d9fde2d1761e02f11f6596161d43c274e21b26ae10d88e06` |
| [HDLCore.sv](HDLCore.sv) | `0322a7cf3f9f8d10df94966743671655b6688b475b042bd9453b0823fb7e24ae` |

HDL report pages, traceability, latency and resource metadata are preserved under `reports/checkpoint_b/codegen/`. The complete interactive report and generated/validation SLX remain locally under the fresh run's `generated/speed_pi_hdl/` directory (temporary runtime contents are not committed).
