# Simulink 主导的 PMLSM FPGA 电机控制

本仓库从 FPGA / SystemVerilog / PWM 学习，转向**以 Simulink 为主要算法源、以 HDL Coder 生成控制算法 HDL、以 Vivado 完成硬件实现与验证**的电机控制开发路线。

**路线更新：2026-10-23。** PR46 计划已按检查点实施：新增独立纯 Simulink PI-FOC 浮点基线，外部 `.m` 加载 Base Workspace，统一电机、归一化 duty 和控制时基。数学/时序、九个源 backend0 迁移场景及步长检查已在 R2026b 实测通过；当前完成交付复核，停在开放实现 PR 等待 Review。

已有手写 PWM、FOC 和电流环 RTL 保留为学习成果、时序理解和回归参考，**不是正式控制器必须沿用的生产代码底座**。后续不再要求每个算法维护“纯 Simulink、HDL Coder、手写 SV”三套实现。

## 当前入口

| 内容 | 入口 |
|---|---|
| 直接运行新浮点基线 | [中文运行指南](docs/PMLSM_FLOAT_BASELINE_GUIDE_ZH.md)、[实施报告](coordination/reports/m1a_pure_simulink_float_baseline.md)、[结果索引](docs/reports/m1a_float_baseline/README.md) |
| 当前阶段：纯 Simulink 浮点模型及外部参数入口 | [M1A 设计](coordination/specs/m1a_pure_simulink_float_baseline_design.md)、[Codex 实施任务](coordination/tasks/m1a_pure_simulink_float_baseline.md)、[逐项计划](docs/superpowers/plans/2026-10-23-m1a-pi-foc-float-baseline.md) |
| 项目目标与阶段关系 | [Simulink 主线路线图](docs/SIMULINK_MAINLINE_ROADMAP.md) |
| 完整 MIL / Simple / DSP 的实际差异和已有资料 | [模型与资料核查表](docs/MODEL_DIFFERENCE_AND_ASSET_AUDIT.md)、[M0 报告](coordination/reports/m0_simulink_model_asset_audit.md) |
| 当前交接与工作区保护约定 | [HANDOFF](coordination/HANDOFF.md) |
| 旧 Simple + 手写 RTL 联合仿真的操作方法 | [模型中文指南](docs/PMLSM_MODEL_GUIDE_ZH.md)，仅适用既有验证路径 |

## 项目目标

先在纯 Simulink 中建立清楚、可复现的浮点闭环基线；面向 FPGA 建立独立且可追溯的定点实现模型；从 Simulink 电流环 FOC 模型生成 HDL，再做模型/RTL 验证、资源与时序分析、闭环联合仿真。随后逐步集成实机指令、参数管理、安全行为和已确定的板级接口，最终在另行批准的上板阶段控制真实驱动板与电机。

浮点参考与定点实现可以分开，但不长期维护两套互相漂移的电机、工况和控制需求。参数、采样周期、使能/复位及误差口径必须可追溯。

## 模型分工

| 模型 | 定位 |
|---|---|
| `simulink模型/PMLSM_PI_FOC_Float_Baseline.slx` | M1A 独立纯 Simulink 浮点基线；已完成限定场景仿真验证 |
| `simulink模型/init_PMLSM_PI_FOC_Float_Baseline.m` | 外部参数/默认场景入口，显式加载 Base Workspace；不依赖旧 MAT 和隐藏 Model Workspace 参数 |
| `simulink模型/PMLSM_ThreeLoop_Simple.slx` | 保留已修正、已验证的核心控制与旧联合仿真成果；作为新副本来源和迁移对照，不直接当作完整实机控制器 |
| `simulink模型/PMLSM_MIL_ControlCore_Sim.slx` | 完整系统仿真、启动/命令/反馈/日志的参考；其 `PMLSM_ControlCore_Block.slx` 一并保留 |
| `simulink模型/PMSLM_Close_Loop_MBDL4.slx` | DSP 实机运行逻辑、参数、保护及外设语义参考；不直接转换成 FPGA 顶层 |

不覆盖原模型，不把三份旧模型强行改成一份。后续统一的是新主线的算法、物理量和接口责任，不是抹去历史差异。

## 现在做什么

**M1A 实现等待 Review。** 新模型以 Simple 的 `Control_Task_10kHz/FOC_Algorithm` 为来源，保留 PI-FOC、外环及自由运动 plant，使用归一化上管 duty 和明确的外部参数。按运行指南复现、审阅实现报告；不自动进入 M1B/M2。

M1A 没有混入对齐/故障恢复等运行管理重构，没有定点化、HDL/C 生成、Vivado 构建或硬件操作，也未全量重跑 Step6/7/StudyL1。旧模型及用户未提交版本保留，后续工作另行批准。

M0 中启动依赖、调制标度和参数遮蔽问题由 M1A 处理；真实采集、线缆和板级适配仍留后。已有接口先查仓库与原始资料，不要求用户重复填写。

## 已有成果与资料

- 三个旧主模型、ControlCore、相关初始化脚本、最小 HDL co-sim 模型，以及 M0 补齐的 8 份说明/兼容入口已在仓库；文件存在不等于动态或实机验证通过。
- 远端根目录已有 BX72、ACM9238、MBDL4、转接板及 DSP 核心板/底板资料；本地用户已放在 `硬件说明/`，对应关系见 M0 清单。
- `PWM_Controller/`、`PWM_Breathe/`、`Motor_PWM/`、`FOC_*/`、`motor_control_ip/`、`learning/` 和历史报告保留，不搬迁、不删除。
- M1A 文档基线：`main@2e10c2dc576648165f541ad5b1530ef90c1e3791`。本地 Simple 仍可能有未提交变化，必须按 M0 证据核对，不能强制覆盖。

历史环境记录包括 Vivado 2026.1、MATLAB R2026b、BX72 / `xc7a200tfbg484-2`。纯浮点新模型不因已有这些工具就必须调用 HDL/Vivado。

## 协作与历史说明

ChatGPT 维护架构、设计、任务交接和 Review；Codex 在 `D:/Project/FPGA_XC7A200T` 完成实际模型创建及 MATLAB 验证。保留用户本地修改，不新建额外 clone/worktree，不强制清理，不自动合并 PR。

[旧交接记录](coordination/HANDOFF_LEGACY_20261021.md)原样保留。旧任务的暂停或验收数字只描述当时状态，不覆盖当前范围。历史 PWM 实验入口仍为 `PWM_Controller/PWM_Controller.xpr` 和 `PWM_Breathe/PWM_Breathe.xpr`；复现时读取对应历史任务与报告。
