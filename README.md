# FPGA PWM Learning Project

本项目用于 FPGA、Verilog/SystemVerilog 学习和 Vivado 开发流程练习，同时用于建立 ChatGPT、GitHub 和 Codex 的协同开发流程。

## 开发环境

- Vivado：2026.1
- FPGA：`xc7a200tfbg484-2`
- Step 5A Design Top：`pwm_demo_top`（内部复用 `pwm_controller`）
- Step 5A Simulation Top：`pwm_demo_top_tb`；原核回归为 `pwm_controller_tb`

Vivado 工程入口为 `PWM_Controller/PWM_Controller.xpr`。

## 当前状态

- Step 1 至 Step 4 已完成：自检仿真、比较值语义、输出对齐、综合、50 MHz 约束与布局布线时序基线。
- Step 5A 为 BX72 LED1 闪烁实验，独立约束集 `constrs_step5a` 和运行 `step5a_synth` / `step5a_impl`。
- 原 PWM 核、原测试及 Step 4 约束保留；Step 5A 构建不会重置旧的 `synth_1` / `impl_1`。
- 最新硬件审计、实际构建结果及手动下载步骤见 [Step 5A 执行报告](coordination/reports/step5a_codex_report.md)。物理硬件结果等待用户确认。
- Step 5B 呼吸灯尚未开始。

在仓库根目录用 PowerShell 运行：

```powershell
& 'E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat' -mode batch -nojournal -log step5a_build.log -source scripts/step5a_bx72_build.tcl
```

脚本执行原核回归与板级仿真，然后综合、布局布线、时序/DRC 检查，通过后生成 bitstream，不自动连接或烧写硬件。只使用已审计的时钟 Y18、KEY2 V17、LED1 AA18，均为 Bank 14 / LVCMOS33。LED1 高电平点亮；默认 50 MHz 下亮灭各 0.5 秒。

任务定义以 [交接文件](coordination/HANDOFF.md) 为准。`docs/baseline_audit.md` 是初始阶段的历史审计；旧阶段构建脚本应在对应历史版本运行。
