# Simulink 主导的 PMLSM FPGA 电机控制

本仓库从 FPGA / SystemVerilog / PWM 学习，转向**以 Simulink 为主要算法源、以 HDL Coder 生成控制算法 HDL、以 Vivado 完成硬件实现与验证**的电机控制开发路线。

**路线更新：2026-10-21。** StudyL1 学习已结束，后续不再要求每个算法都维护“纯 Simulink、HDL Coder、手写 SV”三套实现。已有手写 PWM、FOC、电流环 RTL 保留为学习成果、时序理解和回归参考，**不是正式控制器必须沿用的生产代码底座**。

## 当前入口

| 内容 | 入口 |
|---|---|
| 当前目标、阶段边界与后续路线 | [Simulink 主线路线图](docs/SIMULINK_MAINLINE_ROADMAP.md) |
| 完整 MIL / Simple / DSP 的初步差异、已有资料与待核查项 | [模型与资料核查表](docs/MODEL_DIFFERENCE_AND_ASSET_AUDIT.md) |
| Codex 当前任务：模型审计、资料补齐和下一阶段建议 | [M0 执行任务](coordination/tasks/m0_simulink_model_asset_audit.md) |
| 当前交接与工作区保护约定 | [HANDOFF](coordination/HANDOFF.md) |
| 现有 Simple + 手写 RTL 联合仿真的操作方法 | [模型中文指南](docs/PMLSM_MODEL_GUIDE_ZH.md)，属于既有验证路径，不代表新 HDL Coder 主线已经完成 |

## 项目目标

先在纯 Simulink 中建立清楚、可复现的浮点闭环基线；面向 FPGA 建立独立且可追溯的定点实现模型；从 Simulink 电流环 FOC 模型生成 HDL，再做模型/RTL 验证、资源与时序分析、闭环联合仿真。随后逐步集成实机指令、参数管理、安全行为和已确定的板级接口，最终在另行批准的上板阶段控制真实驱动板与电机。

浮点参考与定点实现可以分开，但不长期维护两套互相漂移的电机、工况和控制需求。参数、采样周期、使能/复位及误差口径必须可追溯。

## 三类模型的分工

| 模型 | 当前定位 |
|---|---|
| `simulink模型/PMLSM_ThreeLoop_Simple.slx` | 保留已修正、已验证的核心控制与联合仿真成果；继续作为快速调试和回归基础，不直接当作完整实机控制器 |
| `simulink模型/PMLSM_MIL_ControlCore_Sim.slx` | 完整系统仿真、启动/命令/反馈/日志结构的参考；其中 `PMLSM_ControlCore_Block.slx` 也须一起审计 |
| `simulink模型/PMSLM_Close_Loop_MBDL4.slx` | DSP 实机运行逻辑、参数、保护及外设映射的参考；不是可直接转换成 FPGA 顶层的模型 |

不预先认定旧大模型比 Simple 更正确，也不从 Simple 删除功能较多就推断每项保护都不存在。具体迁移取舍由 M0 的实际模型核查决定。

## 现在做什么

**当前只推进 M0：梳理三个模型的功能差异、实际参数来源、已有硬件资料和中间工程依赖，补齐缺项，明确下一步 Simulink FOC 整理范围。**

这轮不改控制算法、不重整定 PI、不创建新的完整控制器、不重新实现手写 FOC、不生成 bitstream、不操作硬件，也不为了整理文档完整重跑 Step 6、Step 7 或 StudyL1。

已知资料先从仓库和用户原始本地主项目查找；不要求用户重新讲一遍已经提供的接口。只有查找后仍缺失、且阻碍当前工作的具体信息，才集中报告。

## 已有成果与资料

- 仓库已有上述三个主模型、`PMLSM_ControlCore_Block.slx`、初始化脚本和最小 HDL co-sim 模型；文件存在不等于本地依赖完整或模型已经重新验证。
- 根目录已有 BX72、ACM9238、MBDL4、转接板及 DSP 核心板/底板资料；详见核查表。接口参数以既有资料和实际连接为依据，不在此重新猜测。
- `PWM_Controller/`、`PWM_Breathe/`、`Motor_PWM/`、`FOC_*/`、`motor_control_ip/`、`learning/` 和历史报告保留，不搬迁、不删除。
- 本次文档核查基线：`main@319ee0103c4f4b42752fad49014ead2cfbefceea`，包含已合并 PR #41（StudyL1 Checkpoint D）。这不是新主线模型已完成的声明。

历史环境记录包括 Vivado 2026.1、MATLAB R2026b、BX72 / `xc7a200tfbg484-2`；Codex 核查当前实际安装和工程配置即可，不因文档整理重装工具链。

## 协作与历史说明

ChatGPT 维护架构、任务说明和 Review；Codex 在 `D:/Project/FPGA_XC7A200T` 完成实际 MATLAB/Vivado 核查、资料同步与后续经批准的实现。保留用户本地修改，不新建额外 clone/worktree，不强制清理，不自动合并 PR。

[旧交接记录](coordination/HANDOFF_LEGACY_20261021.md)原样保留。旧阶段的任务书、验收数字和“尚未进入下一步”等表述只描述当时状态，不覆盖本次主线调整。历史 PWM 实验入口仍为 `PWM_Controller/PWM_Controller.xpr` 和 `PWM_Breathe/PWM_Breathe.xpr`；需要复现实验时读取对应历史任务与报告。
