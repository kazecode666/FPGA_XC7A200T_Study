# Simulink 主导的 FPGA 电机控制主线

更新：2026-10-25。**M3已随PR53合并 `4470e35` 接受：p3的数值/状态/RTL和20ns核心OOC通过。** 原−58.833ns失败属于历史构建，不是当前阻塞。下一轮按用户要求扩大为 **完整三闭环、原对齐、必要指令/故障处理共同生成HDL，再一次性联合仿真和模块级布局布线**，不再先做电流环单独联合仿真的中间交付。

待执行入口：[M4完整三闭环HDL任务](../coordination/tasks/m4_full_three_loop_hdl_cosim.md)。本次更新只规划，不表示完整三环已定点化或生成。

## 1. 目标与非目标

以Simulink/Stateflow维护控制算法和控制状态机，保留浮点参考，建立定点实现，经HDL Coder生成SystemVerilog；在Vivado验证数值/资源/时序，再与同一电机环境联合仿真，最后接入真实控制器和板级接口。

首版仍为现有PI-FOC级联控制；完整MIL中的DPCC/DPICC/PICDO保留研究。旧手写FOC/PWM是学习及验证资产，不恢复为正式代码底座。已有StudyL1速度PI模型、类型及向量应复用，不从零重复。

不把含Host、plant和逆变器的整个MIL顶层生成HDL；不同时维护多套独立电机对象；不把仿真/核心时序通过视为可安全上电。验证合并成一轮自动化流程，不删掉新增类型和集成边界的必要检查。

## 2. 平台与功能划分

| 功能 | 当前单FPGA目标 | 后续MPSoC 5EV建议 |
|---|---|---|
| 位置控制、速度PI、FOC/SVPWM | 全部PL，模型生成 | 优先复用同一PL核，不必因有ARM而迁回CPU |
| Reference_Manager、原对齐执行、角度/电流选择 | PL，显式状态和多速率 | 保留PL执行；PS可承担启动策略和配置 |
| 命令快照、PWM实际许可、最小故障锁存/快速禁止 | PL实时路径 | 仍保留PL/驱动硬件；PS负责记录及恢复决策 |
| 界面、S曲线/连续点位参考、记录与通信管理 | 当前PC/Simulink参考源；板内自主轨迹另行任务 | 可由PS承担，保持控制接口 |
| ADC/编码器、门极PWM、驱动器协议 | 后续板级集成 | 按已有硬件资料分配PL/PS，快速关断不依赖普通应用软件 |
| plant、平均逆变器、测试负载 | 共享仿真环境 | 不进入控制核 |

本轮接收轨迹参考，不声称只下发绝对终点后FPGA自行规划全部轨迹。上位机产生参考不等于上位机执行位置/速度闭环；三个反馈控制环必须在RTL中。

## 3. 模型与产物职责

| 对象 | 职责 |
|---|---|
| `PMLSM_PI_FOC_Float_Baseline.slx` | 共享Host/plant/逆变器和观测；M4拟增加原参考/完整定点/完整RTL选择 |
| `init_PMLSM_PI_FOC_Float_Baseline.m` | 唯一人工初始化，参数和类型自动加载，普通Run不启动HDL工具 |
| `PMLSM_FOC_FixedPoint.slx/FOC_DUT` | 已接受FOC数值来源，M3 p3配置和报告保持历史可追溯 |
| `PMLSM_ThreeLoop_FixedPoint.slx/Control_DUT`（拟新增） | 位置P、速度PI、参考/对齐、调度及FOC的完整定点生产核 |
| StudyL1 fixed/carrier | 速度PI复用来源；旧25/15输出与当前FOC32/24接口显式处理 |
| gm/validation、生成SV | 同源/配置的派生产物，不手改算术以修结果 |
| 薄集成适配 | 输入/命令锁存、结果有效/应用和快速禁止，不另写控制数学 |
| 旧Simple/MIL/ControlCore/DSP | 只读语义来源，不重写或覆盖 |

M4优先整核生成，允许在工具确有约束时统一脚本组装模型生成的模块；最终必须是完整HDL控制顶层及相同范围的定点参考。原触发父层不能直接充作HDL顶层。继承p3流水线策略需要按新层次重新映射，而非照抄SID/输出314拍。

## 4. 阶段与退出条件

| 阶段 | 工作 | 状态/退出条件 |
|---|---|---|
| M0 | 来源/功能审计 | PR44已接受 |
| M1A | 浮点基线、外部init、面板和具名观测 | PR47已接受，基础参数固定 |
| M1B | 连续点位、原可选对齐 | PR49已接受；未知非零偏置物理识别未冒称通过 |
| M2 | 独立定点FOC与共享闭环 | PR51带M2-E-REPEAT-001例外接受，原严格FAIL保留 |
| **M3** | FOC SV、gm/RTL位状态验证、核心OOC | **PR53已接受并合并**；p3 20ns WNS+5.317ns，尚非routed/板级签核 |
| **M4：待实施，整轮集成** | 三环/参考/原对齐/最小命令故障HDL、时序适配、实际电机联合仿真及模块place/route | 完整定点→RTL位/事件正确，真实反馈闭环及代表场景通过，同版完整模块routed时序/资源满足，一次Review |
| M5 | 完整板级控制器 | 真实ADC/光栅磁栅/测速/六路门极PWM、驱动板关断恢复、通信参数及CDC/IO验证 |
| M6 | 另行批准上板 | 先I/O和安全关断，后受控功率级/电机；需独立授权和真实记录 |

M4现在允许模块级完整place/route和实际RTL闭环，不沿用旧M3禁令阻止这两项。bitstream/硬件仍不在本轮。三环模式是调试配置，运行中不做热切换。

## 5. 固定行为与时序

现有位置只有Kp_pos，本轮保持位置P/死区/限幅，不因为“三环PI”的口语称呼新增位置积分器。速度PI保留old-state、积分/输出限幅和上一excess；FOC保留原64/72位实现、六扇区和查表，不另做算法/位宽优化。

首版器件 `xc7a200tfbg484-2`，50MHz/20ns；电流100us、速度1ms、位置10ms。单物理时钟的采样使能负责不同更新率，快流水线在控制样本间继续运行。首tick与同拍旧/新参考消费由最新源模型测定。

p3裸核心要求九路输入整5000拍保持，不能同帧晚到的外环iq_ref直接插入其运行中，或在314拍后停止内部时钟。新顶层要冻结从反馈采样、外环、参考/对齐、FOC计算到实际提交的完整事件链，含全部适配后赶上50us应用边界且至少留1拍余量。

plant1us、既有一次1us平均死区保持；实际应用等待只计一次，不机械相加“计算延迟+完整50us”。控制角/偏置与电机真实角分离，正常参考仍来自既有Host/轨迹。

连续点位同一Run到位后接受新目标，Busy拒绝不排队；10mm/5s/V10/A100用户默认不被回归覆盖。对齐默认旁路、五态和原计数不改，Start=0→1→完成→0；不新增未知偏置算法。

故障当前为已同步输入的最小PL锁存/禁止：快速撤销PWM许可，不等慢外环；故障消失且PWM请求关闭时才允许独立clear，之后新使能与有效帧/对齐条件满足才恢复。PI/Init复位不清软件故障，软件clear不冒充驱动板reset。真正异步硬件关断/安全要求留M5。

## 6. 验证与范围

原浮点→新完整定点：新增外环/对齐类型按预先冻结预算比较，不能据一次波形事后改阈值。完整定点→gm→RTL：相同输入/初态下有效数值和状态逐位一致，离散事件按同一合同执行，检查复位、慢环交汇和fault优先级。

实际RTL必须与plant组成实时反馈链；预录输入只作单元隔离，不能代替联合仿真。有限代表集覆盖点位、连续反向、对齐后运行、PWM/PI复位及fault恢复；正常用户能初始化、切换后端、Run和查看具名SDI日志。

同一代码/类型/配置manifest执行完整模块place/route，报告实际setup/hold、route完成和资源，内部无未解释未约束/无时钟/环；板级外部约束另列，不用false path、大multicycle、改时钟或自动切5EV掩盖问题。

M2-E-REPEAT-001不自动扩展到新的外环定点反馈系统，也不能放行RTL位差、错相位或deadline失败。保留原例外及数值。新增分歧先定位第一次分叉，不盲目调PI/关死区或任意平移曲线。

复用未受影响历史证据，不全量重跑StudyL1/Step6/7。精简入库报告、源/生成代码和依赖；大MAT/DCP/波形留.runtime，避免重复巨型载荷。用户本地修改/未保存窗口/布局优先保护。

## 7. 阅读顺序

[HANDOFF](../coordination/HANDOFF.md) → [M4任务](../coordination/tasks/m4_full_three_loop_hdl_cosim.md) → [M3 p3报告](../coordination/reports/pr53_critical_path_pipeline_revision.md) / [时序合同](FOC_HDL_TIMING_CONTRACT.md) → [StudyL1 C](../learning/study_l1_speed_pi_hdl_compare/CHECKPOINT_C.md) / [速度语义](../learning/study_l1_speed_pi_hdl_compare/reports/checkpoint_a/current_speed_pi_audit.md) → [M1B对齐来源](../coordination/reports/m1b_repeat_moves_and_alignment.md)。

[M3任务](../coordination/tasks/m3_foc_systemverilog_rtl_verification.md)、[PR53修订任务](../coordination/tasks/pr53_critical_path_pipeline_revision.md)、[M2](../coordination/tasks/m2_foc_fixed_point_implementation.md)、[M1B](../coordination/tasks/m1b_repeat_moves_and_alignment.md)及旧报告保留当时范围。当前文档记录M3已合并和M4待实施，不回写旧失败为通过。
