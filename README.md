# Simulink 主导的 PMLSM FPGA 电机控制

本仓库从 FPGA / SystemVerilog / PWM 学习，转向**以 Simulink 为主要算法源、以 HDL Coder 生成控制算法 HDL、以 Vivado 完成硬件实现与验证**的电机控制开发路线。

**路线更新：2026-10-24。** 按已合并 PR50 交付 M2 独立 FOC 定点 SLX、共享 float/fixed 闭环、类型配置及本机证据。单元和11类共享场景通过，**连续点位数值预算未通过，作为开放实现PR的Review阻塞项保留**。[操作指南](docs/PMLSM_FOC_FIXED_POINT_GUIDE_ZH.md) · [整合验收](coordination/reports/m2_foc_fixed_point_implementation.md)。原浮点默认、三环参数、连续点位、原对齐和默认死区保留；未生成 HDL/C 或运行 Vivado。

后续用户授权的[共同死区符号诊断](docs/reports/m2_foc_fixed_point/common_sign_diagnostic/README.md)使该场景iq/速度峰值与RMSE差下降超过99.99%，命令/Ready仍一致；已明确提出只针对冻结场景的受限例外`M2-E-REPEAT-001`，等待PR51 Review。原严格FAIL、预算和正常测试退出保持，不等于完整M2严格通过，诊断不进入生产模型。

已有手写 PWM、FOC 和电流环 RTL 保留为学习成果、时序理解和回归参考，**不是正式控制器必须沿用的生产代码底座**。后续不再要求每个算法维护“纯 Simulink、HDL Coder、手写 SV”三套实现。

## 当前入口

| 内容 | 入口 |
|---|---|
| M2 当前实现和证据 | [任务书](coordination/tasks/m2_foc_fixed_point_implementation.md)、[设计](docs/FOC_FIXED_POINT_DESIGN.md)、[操作](docs/PMLSM_FOC_FIXED_POINT_GUIDE_ZH.md)、[结果索引](docs/reports/m2_foc_fixed_point/README.md) |
| M1B 已接受的任务与结果 | [M1B任务](coordination/tasks/m1b_repeat_moves_and_alignment.md)、[整合验收](coordination/reports/m1b_repeat_moves_and_alignment.md)、[FOC准备报告](docs/FOC_FIXED_POINT_READINESS.md) |
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
| `simulink模型/PMLSM_PI_FOC_Float_Baseline.slx` | 已接受浮点参考与共享闭环环境；M2只增加必要的float/fixed实现选择，不重建Host/对齐/外环/plant |
| `simulink模型/init_PMLSM_PI_FOC_Float_Baseline.m` | 唯一人工初始化入口，显式加载Base Workspace，简洁中文分段；类型配置由它调用 |
| `simulink模型/PMLSM_FOC_FixedPoint.slx` | 实际根层 FOC_DUT；完整固定类型电流FOC，由共享环境 Normal Model Reference 唯一引用 |
| `simulink模型/PMLSM_ThreeLoop_Simple.slx` | 原算法修正、外环及plant来源和迁移对照；原文件保留 |
| `simulink模型/PMLSM_MIL_ControlCore_Sim.slx` | 原系统级仿真和对齐来源；其 `PMLSM_ControlCore_Block.slx` 一并只读保留 |
| `simulink模型/PMSLM_Close_Loop_MBDL4.slx` | DSP运行与外设语义参考；用于核对原对齐，不直接转换成FPGA顶层 |

不覆盖原模型，不把三份旧模型强行改成一份。统一的是新主线的算法、物理量和接口责任，不是抹去历史差异。

## 现在做什么

**M1A/M1B已接受，基础参数继续固定。** M2按一个任务包连续完成：来源与接口冻结、独立浮点适配及零分母处理、范围/类型设计、定点单元与状态验证、共享闭环比较、兼容性与操作交付。不是再做一轮纯文档审计，也不直接把整个三闭环模型改成定点。

M2 独立 DUT 消除了触发父层限制，扇区用 uint8，候选除法在运算前保护分母；实际内部编译端口均为 fixed/integer/boolean。第9母线端口、`FOC_Impl_Select` 及量化预算属于 M2 新设计。原浮点候选支路已知 0/0 保留，其合法输出没有为匹配定点而改写。

连续点位和原对齐保持现状，不新增运动中重规划、热切环或启动协议。默认电机、PI、控制周期、一次PWM更新和未补偿平均死区保持；PWM关闭后仿真/机械体继续，PI复位不是全故障清除。完整保护、实际测量滤波、死区补偿及JMAG/Maxwell留后。

M2以实际固定类型SLX、类型表、数值/闭环/溢出证据与独立checkhdl结果为交付。checkhdl通过不等于已生成HDL或满足资源/时序；本轮不调用HDL/C生成、Vivado或硬件。完成提交一个开放实现PR，等待Review后再进入M3。

## 已有成果与资料

- 旧主模型、ControlCore、初始化、最小HDL co-sim及M0补齐资料已在仓库；文件存在不等于实机验证通过。
- 远端根目录已有BX72、ACM9238、MBDL4、转接板及DSP板卡资料；用户本地已放在 `硬件说明/`，对应关系见M0清单。
- `PWM_Controller/`、`PWM_Breathe/`、`Motor_PWM/`、`FOC_*/`、`motor_control_ip/`、`learning/`和历史报告保留，不搬迁、不删除。
- 当前文档起点为 `main@aa46c711e2120563fe90611805348b343a568f0a`。本地SLX可能有后续用户改动，实施必须先查，不强制覆盖。

历史环境记录包括Vivado 2026.1、MATLAB R2026b、BX72 / `xc7a200tfbg484-2`。只核对本机当前实际环境，不因文档整理重装工具链。

## 协作与历史说明

ChatGPT维护架构、任务和Review；Codex在 `D:/Project/FPGA_XC7A200T` 实施和验证。保留本地修改，不新建额外clone/worktree，不强制清理，不自动合并。已有接口先查资料，不要求用户重复填写。

[旧交接记录](coordination/HANDOFF_LEGACY_20261021.md)原样保留。旧任务的暂停、范围和验收数字只描述当时状态；本轮以最新任务书为准。历史PWM实验入口仍为 `PWM_Controller/PWM_Controller.xpr` 和 `PWM_Breathe/PWM_Breathe.xpr`。
