# ChatGPT ↔ Codex Project Handoff

**当前更新：2026-10-25。** M3 A/B/C/D/F 已有真实PASS证据：实际SV、完整原定点→gm位/状态、xsim、复位/CE、重复生成及迁移smoke。**E综合完成、容量满足但20ns时序FAIL，WNS−58.833ns；M3未接受。** [整合结果](reports/m3_foc_systemverilog_rtl_verification.md)、[操作指南](../docs/PMLSM_FOC_HDL_GUIDE_ZH.md)、[机器结论](../docs/reports/m3_foc_hdl/acceptance_result.json)。停在开放实现PR等待Review，不合并、不进入M4。M2的PR51受限例外不适用于M3。

## 当前执行入口

读取 [M3：FOC SystemVerilog生成、时序合同与RTL验证](tasks/m3_foc_systemverilog_rtl_verification.md)，再读 [M2设计](../docs/FOC_FIXED_POINT_DESIGN.md)、[整合验收](reports/m2_foc_fixed_point_implementation.md)和[当前操作指南](../docs/PMLSM_FOC_FIXED_POINT_GUIDE_ZH.md)。任务合并或用户明确指定后，在原checkout连续实施A—F，正常检查点不重复求许可，最终一个开放实现PR等待Review。

- **做：** 实际SV/普通自检TB/必要ROM、gm_/validation双层数值与状态验证、硬件时钟和有效相位合同、xsim、同份RTL的核心OOC综合预检、重复构建和中文指南。
- **保持：** 当前FOC类型和数值语义、外部初始化、Host连续点位、原对齐、外环、plant、平均逆变器、默认PI/死区/时基和具名观测；不再长期复制一套完整电机模型。
- **不做：** 重整定/死区补偿/运动中重规划/热切环/对齐改造/完整故障管理/采集滤波/JMAG/Maxwell；不展开普遍缩位优化。完整place/route、RTL电机闭环、bitstream、门极/板级接口和硬件留M4以后，不由Workflow自动执行。

## M2接受与例外的准确含义

原浮点FOC仍在 `Control_Task_10kHz/FOC_Implementation/Float/FOC_Algorithm`；新 `PMLSM_FOC_FixedPoint.slx/FOC_DUT` 经 Fixed/FOC_Model 唯一引用。`FOC_Impl_Select=0/1` 在停止后选择，不是运行中模式切换。

[M2例外](../docs/reports/m2_foc_fixed_point/common_sign_diagnostic/acceptance_exception.json)只处理冻结0–4s连续点位的iq最大差、速度最大差/RMSE。原严格FAIL、原预算和M2 `closedloop/all`非零出口保持，不能通过改测试让全绿，也不让已接受的预期FAIL无限阻止M3启动。

共同死区符号是临时因果诊断，不进入正式算法。类型/PI/对象/时基/序列等改变不能自动继承例外。**它不豁免原定点→gm→RTL的位差、状态错误、漏帧或截止时间问题。** M2历史报告中待Review/原阻塞表述保留历史上下文，当前接受状态以Review、例外元数据和本交接为准。

## M3实现关系

唯一算法源仍是独立定点FOC。首选脚本在最新本地源的隔离副本应用生成配置；不手改生成SV、gm或validation为新算法，不恢复手写FOC生产后端。主模型正常init/Run不调用HDL或Vivado。

9个输入保持同拍物理意义，3个输出仍是死区/应用更新前归一化command duty。新增HDL clock/global reset/CE/输出相位逐项映射，不强行增加AXI/FIFO等事务系统。global reset与PI_Reset_EN分开，原old-state PI和前拍AW必须保持。

首版目标 `xc7a200tfbg484-2`、50MHz/20ns、100us/5000拍。A核对本机器件/旧约束和实际PWM更新相位；优先Clock-Rate Pipelining与明确倍率，不能把全局CE未经验证接成5000拍一个脉冲。记录输入捕获、状态提交、输出有效及PWM deadline，至少保留1拍提交裕量；不以“吞吐够”替代“及时到达应用边界”。

验证分为原定点→gm及gm→RTL，按真实有效帧/状态事件逐位比较；普通TB优先，DPI/C不默认开启。64/72位中间量不能经double中转后宣称逐位一致。反馈错误不能通过平移输出掩盖，真实闭环延迟留M4按事件链接入。

同一manifest的RTL/ROM用于生成模型、xsim和综合。OOC只做核心综合、utilization及初步timing/check_timing；不虚构板级I/O约束、不靠false_path或5000倍multicycle遮盖路径、不把综合估算称布线后签核。当前宽类型先取得实际成本，必要等价配置候选单独记录和复验。

## 已接受行为，不重新开任务

连续点位在同一次Run到位后接收新绝对目标，Busy拒绝、不排队；用户10mm/5s/V10/A100默认保持。1mm/1.2s/V5/A50是显式回归，不能覆盖日常默认。

对齐来自原完整MIL的Angle_Init及选择器，默认旁路。Start=0→1→完成→0，DONE不因Start保持1自行重入；不修改启动/复位协议或增加未知偏置算法。未知非零偏置识别仍不作为已验收能力。

100us电流/PWM、1ms速度、10ms位置、1us plant、既有半周期更新/保持与单一1us平均死区不改。PWM关闭后机械/仿真继续，PI复位不是全部故障清除。真实角与控制角分离保持。

## 文件、操作与证据

M3主入口为 `scripts/m3_foc_hdl.m`；集中生成配置、向量、xsim和OOC脚本见任务书的文件表。最终交付实际生成SV/TB/ROM清单、时序合同、逐位结果、资源/预检报告、指南和 `coordination/reports/m3_foc_systemverilog_rtl_verification.md`；实际文件及逐项状态已交付，E物理时序阻塞保留。

正常用户仍只手动执行 `init_PMLSM_PI_FOC_Float_Baseline.m`，必要类型自动派生；InitFcn仅检查，中文注释简短。生成/测试是独立开发入口，不要求正常Run先执行一串helper。

`.runtime/m3_<run_id>`存隔离源、gm_/validation、缓存、波形和DCP；最终受审RTL/必要数据及manifest入库。来源、配置、工具版本和结果身份一致；失败/未测分别报告，负例必须真的能检测错误。重构建使用新目录，保留旧失败，不覆盖M2历史证据。

## 工作区保护

- 正式工程仅 `D:/Project/FPGA_XC7A200T`；`D:/Project/PMSLM_Simulation`只读。无额外clone/worktree、云端实现工程、computer use或批量删除。
- 保留tracked/untracked、用户未保存MATLAB窗口、硬件资料移动、旧模型/RTL和布局。先记录状态，不自动stash/reset/clean或远端覆盖。
- 测试只后台加载由最新本地源派生的副本，断言实际FileName；cwd/path/缓存配置恢复，onCleanup只关闭本任务拥有对象，不关闭全部模型。
- 旧Simple/MIL/ControlCore/DSP及原初始化/轨迹/整定只读；不要调用旧全局脚本覆盖新参数或清空工作区。
- 同层local From/Goto，跨层显式端口；仅必要新增区域局部布局，不递归重排原库。
- 每检查点小步提交；真实数值/状态/资源/时限失败保留最小复现，继续独立可做的诊断，不能放宽指标掩盖。禁止自动合并和硬件操作。
- 不全量重跑M0、Step6/7、StudyL1、无变化的60s场景；不建设产品级基础设施。

## 历史与后续

[M1A报告](reports/m1a_pure_simulink_float_baseline.md)、[PR47修订](reports/pr47_host_interface_revision.md)、[M1B报告](reports/m1b_repeat_moves_and_alignment.md)、[M0审计](reports/m0_simulink_model_asset_audit.md)和[M2任务](tasks/m2_foc_fixed_point_implementation.md)保留历史范围；不回写成已完成实机标定或所有性能优化。

[路线图](../docs/SIMULINK_MAINLINE_ROADMAP.md)当前为M3开放实现Review，20ns综合时序阻塞。M3结束后停在开放实现PR，M4完整布局布线和带真实时序的电机联合仿真另行任务。旧“先完成整套运行管理再定点化”范围不恢复，硬件接口先查已有资料，不要求用户重复说明。

[旧交接](HANDOFF_LEGACY_20261021.md)、[M0任务](tasks/m0_simulink_model_asset_audit.md)、[M1A任务](tasks/m1a_pure_simulink_float_baseline.md)、[M1B任务](tasks/m1b_repeat_moves_and_alignment.md)原样作为历史保留。

开放实现PR：[PR53](https://github.com/kazecode666/FPGA_XC7A200T_Study/pull/53)，等待Review，未合并；M3的20ns时序阻塞仍保留。
