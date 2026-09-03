# FPGA PWM Learning Project

本项目用于 FPGA、Verilog/SystemVerilog 学习和 Vivado 开发流程练习，同时用于建立 ChatGPT、GitHub 和 Codex 的协同开发流程。

## 开发环境

- Vivado：2026.1
- FPGA：`xc7a200tfbg484-2`
- Design Top：`pwm_controller`
- Simulation Top：`pwm_controller_tb`

Vivado 工程入口为 `PWM_Controller/PWM_Controller.xpr`。

## 当前状态

- 已有基础 PWM RTL。
- 已有基础 testbench。
- 当前没有 XDC 约束文件。
- 尚未完成可靠的自动化仿真验证。
- 尚未完成综合。
- 尚未完成实现。
- 尚未完成时序验证。
- 尚未进行 FPGA 上板验证。

当前实现的已知行为与风险记录在 `docs/baseline_audit.md`。后续阶段将先建立可靠的 self-checking testbench，并处理现有 testbench 的仿真竞争问题。
