# Simulink 主导的 PMLSM FPGA 电机控制

本仓库从 FPGA / SystemVerilog / PWM 学习，转向**以 Simulink 为主要算法源、以 HDL Coder 生成控制算法 HDL、以 Vivado 完成硬件实现与验证**的电机控制开发路线。

**路线更新：2026-10-24。** 已按PR48任务在原浮点主线完成M1B增量：同一次Run连续绝对点位、原MIL可选对齐、操作/日志回归及FOC只读准备。实际SLX、脚本和[验收报告](coordination/reports/m1b_repeat_moves_and_alignment.md)随开放实现PR等待Review；未自动合并或进入M2。

已有手写 PWM、FOC 和电流环 RTL 保留为学习成果、时序理解和回归参考，**不是正式控制器必须沿用的生产代码底座**。后续不再要求每个算法维护“纯 Simulink、HDL Coder、手写 SV”三套实现。

## 当前入口

| 内容 | 入口 |
|---|---|
| M1B任务与验收依据 | [M1B：连续点位、原对齐迁移与 FOC 准备](coordination/tasks/m1b_repeat_moves_and_alignment.md) |
| 直接运行已合并浮点基线 | [中文运行指南](docs/PMLSM_FLOAT_BASELINE_GUIDE_ZH.md)、[M1A实施报告](coordination/reports/m1a_pure_simulink_float_baseline.md)、[PR47操作修订](coordination/reports/pr47_host_interface_revision.md) |
| 已完成 M1A 的设计和计划 | [M1A设计](coordination/specs/m1a_pure_simulink_float_baseline_design.md)、[历史任务](coordination/tasks/m1a_pure_simulink_float_baseline.md)、[逐项计划](docs/superpowers/plans/2026-10-23-m1a-pi-foc-float-baseline.md) |
| 项目目标与阶段关系 | [Simulink 主线路线图](docs/SIMULINK_MAINLINE_ROADMAP.md) |
| 完整 MIL / Simple / DSP 的实际差异和资料 | [模型与资料核查表](docs/MODEL_DIFFERENCE_AND_ASSET_AUDIT.md)、[M0报告](coordination/reports/m0_simulink_model_asset_audit.md) |
| 当前交接与工作区保护约定 | [HANDOFF](coordination/HANDOFF.md) |
| 旧 Simple + 手写 RTL 联合仿真 | [旧模型中文指南](docs/PMLSM_MODEL_GUIDE_ZH.md)，仅适用既有验证路径 |

## 项目目标

先在纯 Simulink 中建立清楚、可复现的浮点闭环基线；面向 FPGA 建立独立且可追溯的定点实现模型；从 Simulink 电流环 FOC 模型生成 HDL，再做模型/RTL 验证、资源与时序分析、闭环联合仿真。随后逐步集成实机指令、参数管理、安全行为和已确定的板级接口，最终在另行批准的上板阶段控制真实驱动板与电机。

浮点参考与定点实现可以分开，但不长期维护两套互相漂移的电机、工况和控制需求。参数、采样周期、使能/复位及误差口径必须可追溯。

## 模型分工

| 模型 | 定位 |
|---|---|
| `simulink模型/PMLSM_PI_FOC_Float_Baseline.slx` | M1A浮点基线；本轮仅在此主线模型增量补充指令和可选原对齐 |
| `simulink模型/init_PMLSM_PI_FOC_Float_Baseline.m` | 唯一人工初始化入口，显式加载Base Workspace，简洁中文分段；无旧MAT/XSI依赖 |
| `simulink模型/PMLSM_ThreeLoop_Simple.slx` | 原算法修正、外环及plant来源和迁移对照；原文件保留 |
| `simulink模型/PMLSM_MIL_ControlCore_Sim.slx` | 原系统级仿真和对齐来源；其 `PMLSM_ControlCore_Block.slx` 一并只读保留 |
| `simulink模型/PMSLM_Close_Loop_MBDL4.slx` | DSP运行与外设语义参考；用于核对原对齐，不直接转换成FPGA顶层 |

不覆盖原模型，不把三份旧模型强行改成一份。统一的是新主线的算法、物理量和接口责任，不是抹去历史差异。

## 现在做什么

**M1A已由PR47合并，基础参数继续固定。** M1B实施与验证见[整合报告](coordination/reports/m1b_repeat_moves_and_alignment.md)、[精简结果](docs/reports/m1b_repeat_moves_alignment/README.md)和[FOC准备报告](docs/FOC_FIXED_POINT_READINESS.md)。HDL检查因当前触发层次未兼容；未知非零偏置和鼠标操作未冒充通过。

本轮指“到位后再发目标”，**不做运动中轨迹重规划、不做运行中切换闭环模式**。正常三闭环，其他模式仅作停止后选择的调试入口。对齐采用原MIL的Angle_Init及必要选择器，默认旁路；不另外设计对齐算法或未知偏置发生器。

默认电机、PI、控制周期、单一PWM更新和未补偿平均死区保持；PWM关闭后仿真/机械体继续运动，PI复位不是全故障清除。完整故障/驱动板恢复、实际反馈滤波、死区补偿及JMAG/Maxwell接入留后，不把这些作为本轮定点化准备的前置任务。

只读准备不等于M2已开始：本轮不创建正式定点模型、不生成HDL/C、不构建Vivado或操作硬件，不全量重跑Step6/7/StudyL1。实现应交一个开放PR，完成后停止。

## 已有成果与资料

- 旧主模型、ControlCore、初始化、最小HDL co-sim及M0补齐资料已在仓库；文件存在不等于实机验证通过。
- 远端根目录已有BX72、ACM9238、MBDL4、转接板及DSP板卡资料；用户本地已放在 `硬件说明/`，对应关系见M0清单。
- `PWM_Controller/`、`PWM_Breathe/`、`Motor_PWM/`、`FOC_*/`、`motor_control_ip/`、`learning/`和历史报告保留，不搬迁、不删除。
- 当前文档起点为 `main@67cecb0f8fe4f4907cf5896bab4e9003fe0a0c85`。本地SLX可能有后续用户改动，实施必须先查，不强制覆盖。

历史环境记录包括Vivado 2026.1、MATLAB R2026b、BX72 / `xc7a200tfbg484-2`。只核对本机当前实际环境，不因文档整理重装工具链。

## 协作与历史说明

ChatGPT维护架构、任务和Review；Codex在 `D:/Project/FPGA_XC7A200T` 实施和验证。保留本地修改，不新建额外clone/worktree，不强制清理，不自动合并。已有接口先查资料，不要求用户重复填写。

[旧交接记录](coordination/HANDOFF_LEGACY_20261021.md)原样保留。旧任务的暂停、范围和验收数字只描述当时状态；本轮以最新任务书为准。历史PWM实验入口仍为 `PWM_Controller/PWM_Controller.xpr` 和 `PWM_Breathe/PWM_Breathe.xpr`。
