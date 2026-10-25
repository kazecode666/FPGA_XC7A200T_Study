# Simulink 主导的 PMLSM FPGA 电机控制

本仓库从 FPGA / SystemVerilog / PWM 学习，转向**以 Simulink 为主要算法源、以 HDL Coder 生成控制算法 HDL、以 Vivado 完成硬件实现与验证**的电机控制开发路线。

**路线更新：2026-10-25。** M3 已生成实际 SystemVerilog，完成原定点→gm、1024帧边界及1536帧真实前缀的严格 xsim、状态/复位/CE 和重复构建。**M3 未接受：20ns OOC 综合时序 FAIL，WNS −58.833ns；容量满足。** [实际结果](coordination/reports/m3_foc_systemverilog_rtl_verification.md)、[中文指南](docs/PMLSM_FOC_HDL_GUIDE_ZH.md)、[发布清单](generated/m3_foc/manifest.json)。M2 按 PR51 的受限例外接受仍保持。

`M2-E-REPEAT-001` 只接受原冻结连续点位场景的三项浮点/定点闭环比较偏差。[原严格FAIL、预算及正常测试失败退出](docs/reports/m2_foc_fixed_point/common_sign_diagnostic/acceptance_exception.json)仍保留，不称“全部M2严格通过”。共同死区符号仅是临时诊断，不进入正式模型；该例外不适用于 M3 原定点→生成模型→RTL 的数值或时序错误。

已有手写 PWM、FOC 和电流环 RTL 保留为学习成果、时序理解和回归参考，**不是正式控制器必须沿用的生产代码底座**。后续不再要求每个算法维护“纯 Simulink、HDL Coder、手写 SV”三套实现。

## 当前入口

| 内容 | 入口 |
|---|---|
| **M3 实现与真实阻塞** | [整合报告](coordination/reports/m3_foc_systemverilog_rtl_verification.md)、[机器结论](docs/reports/m3_foc_hdl/acceptance_result.json)、[复验指南](docs/PMLSM_FOC_HDL_GUIDE_ZH.md) |
| M3 任务依据 | [SystemVerilog生成、双层验证与核心OOC综合预检](coordination/tasks/m3_foc_systemverilog_rtl_verification.md) |
| M2 已接受实现和证据 | [任务书](coordination/tasks/m2_foc_fixed_point_implementation.md)、[设计](docs/FOC_FIXED_POINT_DESIGN.md)、[操作](docs/PMLSM_FOC_FIXED_POINT_GUIDE_ZH.md)、[结果索引](docs/reports/m2_foc_fixed_point/README.md) |
| M1B 已接受的任务与结果 | [M1B任务](coordination/tasks/m1b_repeat_moves_and_alignment.md)、[整合验收](coordination/reports/m1b_repeat_moves_and_alignment.md)、[FOC准备报告](docs/FOC_FIXED_POINT_READINESS.md) |
| 正常运行共享模型 | [浮点中文指南](docs/PMLSM_FLOAT_BASELINE_GUIDE_ZH.md)、[浮点/定点选择指南](docs/PMLSM_FOC_FIXED_POINT_GUIDE_ZH.md)；历史报告中的待Review文字保留当时状态，当前状态以本页和HANDOFF为准 |
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
| `simulink模型/PMLSM_PI_FOC_Float_Baseline.slx` | 已接受浮点参考与共享闭环环境；停止后选择float/fixed，M3不重建Host/对齐/外环/plant |
| `simulink模型/init_PMLSM_PI_FOC_Float_Baseline.m` | 唯一日常初始化入口，Base Workspace参数/命令及自动类型配置；不自动生成或综合 |
| `simulink模型/PMLSM_FOC_FixedPoint.slx/FOC_DUT` | 唯一正式定点算法源，M3从受控副本生成，不手改生成SV作为另一套算法 |
| `simulink模型/PMLSM_ThreeLoop_Simple.slx` | 原算法修正、外环和plant来源及历史迁移对照，只读保留 |
| `simulink模型/PMLSM_MIL_ControlCore_Sim.slx` | 原系统级仿真和对齐来源；其 `PMLSM_ControlCore_Block.slx` 一并只读保留 |
| `simulink模型/PMSLM_Close_Loop_MBDL4.slx` | DSP运行与外设语义参考，不直接转换成FPGA顶层 |

不覆盖原模型，不把三份旧模型强行改成一份。统一的是新主线的算法、物理量和接口责任，不是抹去历史差异。gm_/validation是可再生成的派生产物，不是第三套长期维护算法。

## 现在做什么

M3连续执行六个检查点：固定来源与时序合同；生成实际SystemVerilog/测试数据/生成模型；证明原定点与生成模型一致；xsim逐位与协议自检；同份RTL的核心OOC综合预检；重复构建、指南及实现PR交付。

首轮目标沿用 `xc7a200tfbg484-2`、50 MHz/20 ns、100 us一帧，即5000硬件时钟。实际器件/工具与PWM应用相位由Codex核对；不能把100 us当FPGA时钟、把全局CE误当采样脉冲，或只看吞吐而漏掉输出deadline。先保留M2宽度取得真实资源成本，不盲目缩位、加宽或调PI。

M3允许必要的生成配置与保持数值语义的流水线适配，要求定点源→gm→RTL分层验证；同一构建manifest用于仿真和综合。核心综合不是布线后时序签核，完整RTL电机联合仿真、实现时序、门极/板级接口、bitstream和上板留后。

连续点位、原对齐、默认电机/PI、一次PWM更新和未补偿平均死区保持；PWM关闭后仿真/机械体继续，PI复位不是全故障清除或HDL全局复位。运动中重规划、热切模式、完整保护、实际反馈滤波、死区补偿及JMAG/Maxwell不在本轮。

任务合并或用户明确指定后由本机Codex实施，最终一个开放实现PR等待Review；不自动合并或进入M4。未执行/失败事项如实列出，不把已有M2证据当成M3已运行。

## 已有成果与资料

- 旧主模型、ControlCore、初始化、最小HDL co-sim及M0补齐资料已在仓库；文件存在不等于实机验证通过。
- 远端根目录已有BX72、ACM9238、MBDL4、转接板及DSP板卡资料；用户本地已放在 `硬件说明/`，对应关系见M0清单。
- `PWM_Controller/`、`PWM_Breathe/`、`Motor_PWM/`、`FOC_*/`、`motor_control_ip/`、`learning/`和历史报告保留，不搬迁、不删除。
- 当前任务起点为 `main@aead404`；本地SLX可能有后续用户改动，先核对，不强制覆盖。

历史环境记录包括Vivado 2026.1、MATLAB R2026b、BX72 / `xc7a200tfbg484-2`。只核对本机实际环境，不因文档整理重装工具链。

## 协作与历史说明

ChatGPT维护架构、任务和Review；Codex在 `D:/Project/FPGA_XC7A200T` 实施和验证。保留本地修改、未保存模型及局部布局，不新建额外clone/worktree、不强制清理、不使用computer use、不自动合并。已有接口先查资料，不要求用户重复填写。

[旧交接记录](coordination/HANDOFF_LEGACY_20261021.md)原样保留。旧任务的暂停、范围和验收数字只描述当时状态；本轮以最新任务书为准。历史PWM实验入口仍为 `PWM_Controller/PWM_Controller.xpr` 和 `PWM_Breathe/PWM_Breathe.xpr`。
