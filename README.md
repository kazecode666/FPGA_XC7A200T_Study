# FPGA PWM Learning Project

本项目用于 FPGA、Verilog/SystemVerilog 学习和 Vivado 开发流程练习，同时用于建立 ChatGPT、GitHub 和 Codex 的协同开发流程。

PMLSM 三闭环学习入口：[模型、正式信号与后端切换中文指南](docs/PMLSM_MODEL_GUIDE_ZH.md)。包含当前 Simulink/FPGA 联合仿真路径、运行命令、观测量表和供 ChatGPT 使用的教学提示。

## 开发环境

- Vivado：2026.1
- FPGA：`xc7a200tfbg484-2`
- Step 5A Design Top：`pwm_demo_top`（内部复用 `pwm_controller`）
- Step 5A Simulation Top：`pwm_demo_top_tb`；原核回归为 `pwm_controller_tb`
- Step 5B Design / Simulation Top：`pwm_breathe_top` / `pwm_breathe_top_tb`

Step 5A 工程入口为 `PWM_Controller/PWM_Controller.xpr`。
Step 5B 使用独立入口 `PWM_Breathe/PWM_Breathe.xpr`，打开呼吸灯时请选择这个工程。

## 当前状态

- Step 1 至 Step 4 已完成：自检仿真、比较值语义、输出对齐、综合、50 MHz 约束与布局布线时序基线。
- Step 5A 为 BX72 LED1 闪烁实验，独立约束集 `constrs_step5a` 和运行 `step5a_synth` / `step5a_impl`。
- 原 PWM 核、原测试及 Step 4 约束保留；Step 5A 构建不会重置旧的 `synth_1` / `impl_1`。
- Step 5A 已完成实物验证，结果记录在 [交接文件](coordination/HANDOFF.md)；原审计与构建记录保留在 [Step 5A 执行报告](coordination/reports/step5a_codex_report.md)。
- Step 5B 呼吸灯采用 1 kHz PWM、10 ms 比较值更新、1% 占空比步进，约 2 秒完成一次呼吸。实际验证、bitstream 路径与上板步骤见 [Step 5B 执行报告](coordination/reports/step5b_codex_report.md)。Step 5B 实物结果等待用户确认。
- Step 5B 的约束、仿真输出、`step5b_synth` / `step5b_impl` 与报告单独保存，保留 Step 5A 工程及结果；尚未进入 Step 6。

在仓库根目录用 PowerShell 构建 Step 5B：

```powershell
& 'E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat' -mode batch -nojournal -log step5b_build.log -source scripts/step5b_bx72_build.tcl
```

脚本依次运行原 PWM 核、Step 5A、Step 5B 三项自检回归，随后完成综合、实现、时序/DRC 检查和 bitstream 生成；不自动连接或烧写硬件。Step 5B 默认比较值从 50,000 降到 0 再升回 50,000，每次步进 500。配置会重置 PWM 核计数器，因此调度器将更新沿固定在每 10 个完整载波周期的边界；这还不是后续 SPWM 的影子比较寄存器架构。

复现 Step 5A 闪烁实验仍使用：

```powershell
& 'E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat' -mode batch -nojournal -log step5a_build.log -source scripts/step5a_bx72_build.tcl
```

脚本执行原核回归与板级仿真，然后综合、布局布线、时序/DRC 检查，通过后生成 bitstream，不自动连接或烧写硬件。只使用已审计的时钟 Y18、KEY2 V17、LED1 AA18，均为 Bank 14 / LVCMOS33。LED1 高电平点亮；默认 50 MHz 下亮灭各 0.5 秒。

任务定义以 [交接文件](coordination/HANDOFF.md) 为准。`docs/baseline_audit.md` 是初始阶段的历史审计；旧阶段构建脚本应在对应历史版本运行。
