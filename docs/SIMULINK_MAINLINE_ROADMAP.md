# Simulink 主导的 FPGA 电机控制主线

更新：2026-10-25。M3已交付[实际SV、完整位/状态及xsim验证、重复构建](../coordination/reports/m3_foc_systemverilog_rtl_verification.md)。A/B/C/D/F通过；E核心综合完成、容量满足，20ns时序FAIL，WNS−58.833ns，**M3尚未接受，等待开放实现Review，不自动进入M4**。M2以PR51受限例外接受，原严格FAIL保留。

## 1. 目标与非目标

以Simulink研究和维护控制算法，保留浮点闭环参考，建立面向硬件的定点实现；由HDL Coder生成算法HDL，以Vivado检查功能/资源/时序，回到共享闭环验证实现影响，最终接入真实控制器与板级接口。

首个FOC来源仍为PR47继承、PR49保留、PR51定点化的Simple PI-FOC；完整MIL中的DPCC/DPICC/PICDO保留研究，不加入首轮部署。旧手写FOC/PWM作为学习及验证资产，不强制作为正式代码底座。

不长期维护三套生产算法，不把整个含电机的MIL顶层生成HDL，不建设产品级基础设施，不由仿真或综合通过推定可安全上电。

## 2. 当前范围和已接受行为

M2已经抽取独立根层FOC、消除触发父层问题、定义未选中除法0/0、完成实际固定类型及共享闭环验证。Host/轨迹、原对齐、外环、平均逆变器和电机继续浮点；正式算法源与共享环境复用，不重建第二套plant。

M3做实际SystemVerilog生成、原定点→gm→RTL验证、时钟/采样/状态合同和目标核心OOC综合预检。先保持M2位宽取得真实成本，不能一边缩位一边更换算子/PI后只看最终波形。

同一次Run到位后可接新位置，Busy拒绝不排队；不做运动中重规划。三闭环默认，其他模式停止后选择。原MIL对齐默认旁路，Start=0→1→完成→0，不重设计协议、不加入未知偏置新算法。

PWM关闭后机械/仿真继续、PI复位不清全部故障均是正常既定行为。完整故障/驱动板恢复、行程管理、死区补偿、真实反馈滤波、JMAG/Maxwell接入继续留后。

## 3. 模型与产物职责

| 对象 | 职责 |
|---|---|
| `PMLSM_PI_FOC_Float_Baseline.slx` | 唯一共享闭环环境，float/fixed停止后选择；M3不增RTL电机后端 |
| `init_PMLSM_PI_FOC_Float_Baseline.m` | 唯一人工初始化，Base参数/命令和自动类型配置；不自动执行HDL工具 |
| `PMLSM_FOC_FixedPoint.slx/FOC_DUT` | M3唯一正式算法源，生成配置在受控副本应用 |
| `pmlsm_foc_fixed_config(p)` | 同一实际类型、量化系数及工程验证范围来源 |
| gm_/validation与生成SV | 从同一源/配置再生成的派生产物，不手改作为独立算法 |
| M3验证harness/TB | 只提供刺激、协议/位比较和观察，不另写FOC参考公式替代模型 |
| 旧Simple/MIL/ControlCore/DSP | 来源与实机语义参考，旧文件只读 |

M3默认保留主模型与定点源数值，生成文件由manifest追踪；必要正式源变化必须单列、证明不改变原语义并复验受影响项。真实角与控制角继续分离。

## 4. 阶段与退出条件

| 阶段 | 工作 | 退出条件 |
|---|---|---|
| M0：已合并 | 模型/参数/资料审计 | PR44接受，动态/板级未冒称完成 |
| M1A：已合并 | 浮点基线、外部init、面板、日志、限定回归 | PR47接受，基础控制参数固定 |
| M1B：已合并 | 连续点位、原可选对齐、操作及准备 | PR49接受，未知非零偏置未冒称已验证 |
| **M2：已合并，带受限例外接受** | 独立定点FOC、状态/范围/共享闭环和兼容性 | PR51及M2-E-REPEAT-001；原严格FAIL保留，不等于所有原门槛通过 |
| **M3：实现待Review，20ns时序阻塞** | 实际SV、gm/validation、xsim、时序合同、核心OOC综合预检 | 可再生成；原定点→gm→RTL位/状态正确、deadline满足；资源及20ns综合估算无阻塞；开放实现PR待Review |
| M4：实现与闭环验证 | 布局布线时序、实际RTL接入共享电机环境 | 布线后时限/资源及真实采样—计算—应用时序下闭环通过 |
| M5：完整控制器与板级集成 | 运行保护、驱动恢复、在线参数、测量链和外设 | 完整顶层与异常场景验证，不沿用单算法结论替代 |
| M6：另行批准上板 | 先I/O和安全关断，后受控功率级和电机 | 独立方案、授权和真实结果 |

M3允许Vivado Simulator和核心synthesis，不顺带place/route/bitstream或硬件；M4才完整签核。核心预检不满足时保留准确阻塞，不伪称完成；配置迭代后补受影响的生成模型/RTL验证。

## 5. 硬件化接口与时间边界

FOC九输入保持顺序和物理单位，三相输出为死区前/应用更新前的归一化command duty，不是active duty/门极。算法覆盖Clarke/Park、dq PI/前馈、圆限幅/前拍AW、反Park及SVPWM，不包含Host/轨迹/对齐管理/外环/plant。

首轮目标`xc7a200tfbg484-2`、50MHz/20ns、100us一帧/5000拍。本机器件/时钟由A核对，不能将100us控制周期改成硬件每拍更新。生成的clock enable、输入捕获、输出valid/相位和状态提交以工具报告及仿真证明为准，不把全局CE直接当5000拍单脉冲。

原电流/PWM100us、速度1ms、位置10ms、plant1us及一次平均死区保持。PWM半周期更新/保持的实际相位先测定；若下一应用边界距采样50us，则时限是2500拍减开销/裕量，不只判断小于5000拍。不能重复相加计算延迟和整份50us，也不能删真实等待。

硬件global reset恢复算法初值和流水线/调度；PI_Reset_EN保持原old-state输出、积分与AW规则，不是每帧清所有状态。首版不建设AXI/FIFO/在线参数协议，外设CDC/I/O约束留相应阶段。

## 6. 验证层次与例外

| 检查 | 回答的问题 |
|---|---|
| 原浮点→独立浮点适配 | 抽取和数值边界整理是否改变原算法 |
| 浮点→定点/共享闭环 | 量化与状态是否满足工程目标，受限例外是否明确 |
| 原定点→生成模型 | 算子/流水线/调度是否保持每个控制样本的数值与递推 |
| 生成模型→RTL | 位级与周期级实现是否正确、无丢样/重复/混帧 |
| 核心OOC综合 | 真实资源成本与20ns初步路径风险，不是最终签核 |
| 布线后RTL→共享闭环 | 保留真实时序后是否满足控制性能 |
| 完整顶层/外设→实机需求 | 协议、超时、CDC、I/O和异常保护 |

M2-E-REPEAT-001只适用于已冻结0–4s连续点位的三项比较。原数值与严格FAIL保留，诊断共用符号不进入生产；改变类型/参数/对象/序列需重新评审。**该例外不能放行M3位差、反馈延迟错误或超deadline。**

M3使用真正量化的原始位串和有效事件，三相输出0位差；64/72位数据不能经有损double中转。模块可按实际latency匹配样本，不能用时间平移修正反馈错误；M4闭环必须保留真实延迟。综合与RTL测试使用同一manifest，不能混入旧RTL或未列ROM。

复用未受影响证据，不全量重跑Step6/7/StudyL1，不覆盖旧报告。真实硬件接口继续先查现有资料，不要求用户重复提供。

## 7. 阅读顺序

[HANDOFF](../coordination/HANDOFF.md) → [M3任务书](../coordination/tasks/m3_foc_systemverilog_rtl_verification.md) → [M2设计](FOC_FIXED_POINT_DESIGN.md) / [报告](../coordination/reports/m2_foc_fixed_point_implementation.md) / [例外](reports/m2_foc_fixed_point/common_sign_diagnostic/acceptance_exception.json) → [当前使用指南](PMLSM_FOC_FIXED_POINT_GUIDE_ZH.md)。

[M2历史任务](../coordination/tasks/m2_foc_fixed_point_implementation.md)、[M1B任务](../coordination/tasks/m1b_repeat_moves_and_alignment.md)、[M1A设计](../coordination/specs/m1a_pure_simulink_float_baseline_design.md)、[旧Simple指南](PMLSM_MODEL_GUIDE_ZH.md)、[旧模型说明](../simulink模型/FPGA_Simulink_Model_Guide.md)、[旧交接](../coordination/HANDOFF_LEGACY_20261021.md)和[StudyL1](../learning/study_l1_speed_pi_hdl_compare/README.md)保留历史范围。
