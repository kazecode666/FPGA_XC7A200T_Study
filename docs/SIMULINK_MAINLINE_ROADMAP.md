# Simulink 主导的 FPGA 电机控制主线

更新：2026-10-24。PR48的M1B任务已在原checkout实施，实际SLX和[验收](../coordination/reports/m1b_repeat_moves_and_alignment.md)随开放实现PR等待Review。9场景240指标、默认12路等价及连续live已取得证据；FOC只读checkhdl发现触发层次错误，未进入M2。历史报告保留当时状态。

## 1. 目标与非目标

以Simulink研究和维护控制算法，保留浮点闭环参考，另建面向硬件的定点控制器实现；由HDL Coder生成算法HDL，使用Vivado检查资源和时序，并回到共享闭环验证实现影响，最后接入真实控制器与板级接口。

首个FOC算法来源仍为PR47继承的Simple PI-FOC；完整MIL中的DPCC/DPICC/PICDO继续保留研究，不加入首轮迁移。旧手写FOC/PWM作为学习及验证资产，不强制作为正式实现底座。

不长期维护三套并行生产算法，不把整个带电机的MIL顶层生成HDL，不建设产品级基础设施，不由仿真通过推定可安全上电。

## 2. 当前范围的最新澄清

本轮需要的是**同一次仿真中到位后再发位置目标**，不是运动中承接非零速度/加速度的在线重规划。先实测现状，再复用原S曲线作最小分段封装；命令由唯一Host边界进入，默认三闭环。其他模式保留为停止后选择的调试功能，不做热切环。

对齐直接迁移原完整MIL的 `PMLSM_ControlCore_Block/PMLSM_ControlCore/Angle_Init` 及外围连接，DSP图用于核对；保留实际MIL的渐降、偏置和采样语义，默认旁路，不换算法、不另建未知偏置发生器。

PWM关闭后机械/仿真继续是正常既定行为；PI复位不是全部故障清除。本轮不展开完整故障锁存/驱动板恢复、行程管理、死区补偿、真实测速滤波或电磁有限元模型替换。上述集成功能不是当前FOC准备工作的必需前置项。

## 3. 模型与参数职责

| 对象 | 职责 |
|---|---|
| `PMLSM_PI_FOC_Float_Baseline.slx` | 唯一纯Simulink主线入口，保留单plant、共享参数和场景；按任务增量增加Host点位和可选原对齐 |
| `init_PMLSM_PI_FOC_Float_Baseline.m` | 唯一人工初始化入口，Base Workspace参数和默认命令，简洁中文分节 |
| 旧Simple | 已修正算法、外环和plant来源及历史迁移对照，原文件不改 |
| 完整MIL + ControlCore | 原启动对齐及系统语义来源，读取和复制必要内容，原文件不改 |
| DSP实机模型 | 对齐及外设语义核对，TI外设不视为FPGA已实现接口 |
| 后续定点控制器 | 同一控制需求下的实现源，共用浮点环境，不复制另一套独立电机/工况 |

已有理想位置/速度反馈继续保留，实际采集和差分/滤波延迟在相应集成阶段再验证。可选对齐所需真实角/控制角分离只按旧MIL语义接入，不能把估计角当物理真实角证明成功。

## 4. 阶段与退出条件

| 阶段 | 工作 | 退出条件 |
|---|---|---|
| M0：已合并 | 模型/参数审计与资料补齐 | PR44接受，动态/板级事项未冒充完成 |
| M1A：已合并 | 独立浮点模型、外部init、操作面板、具名记录及限定回归 | PR47接受，当前三环基础参数作为参考固定 |
| **M1B：实现待Review** | 连续点位命令、原MIL可选对齐、手动操作/受影响回归、FOC只读准备 | 一次Run多次新目标、原chart迁移/闭环证据、保存日志、操作指南和FOC准备报告；开放实现PR待Review |
| M2：定点实现模型 | 独立FOC数据范围、位宽、舍入/饱和、状态/采样、HDL适配 | 数据类型表、浮点/定点误差与边界工况；不以所有外设完成作为前提 |
| M3：生成与RTL验证 | 从实现模型生成HDL，与相应实现参考比较 | 状态/复位/使能/有效数据/延迟映射正确，可复现生成 |
| M4：实现与闭环验证 | Vivado资源/布局布线时序，RTL接入共享环境 | 满足时限/资源，真实采样/计算/PWM延迟进入闭环 |
| M5：完整控制器及板级集成 | 按真实需求完善运行保护、驱动故障恢复、在线参数、测量链及外设 | 完整顶层和异常场景验证，不沿用单算法通过代替 |
| M6：另行批准的上板 | 先I/O和安全关断，后受控功率级和电机 | 独立方案、授权和实际结果 |

M1B不再指此前笼统提出的完整运行管理重构。本轮FOC检查只是M2准备，不创建定点SLX、不生成HDL/C、不执行Vivado或硬件。M3/M4为迭代关系，实现改变后补受影响验证。

## 5. 必须保持的边界

FOC候选覆盖Clarke/Park、dq PI/前馈、圆限幅、反Park及SVPWM；首个DUT不包含Host/轨迹、对齐管理、plant、平均逆变器和日志。外环先留浮点环境。

三相输出为死区前、PWM应用更新前的归一化上管command duty，不等于active duty或门极。电流/PWM100us，速度1ms，位置10ms，plant1us；半周期50us更新和单一1us平均死区的责任保持。后续接实际RTL时替换相应时序，不重复叠加。

基本PI参数不为消除未补偿纹波反复重调；位宽也不继承旧RTL的24bit/2500。设计最大范围与测试观察范围分开，后续定点方案必须有来源。

## 6. 验证与历史复用

| 比较/检查 | 回答的问题 |
|---|---|
| 连续点位live/同入口回归 | 一次Run是否真正接收新命令、使用新段起点与时间，不由预定阶跃代替 |
| 原/新对齐chart与闭环 | 源动作是否保持，物理角度和实际电流是否符合要求；DONE不独自证明正确 |
| 旁路新功能 vs PR47 | 管理/观测改动是否影响正常FOC和plant数值 |
| 浮点 vs 定点 | 量化、状态、饱和是否满足性能要求，不要求逐数相等 |
| 定点参考 vs RTL | 实现与状态/使能/复位、流水线映射是否一致 |
| RTL闭环 vs 参考 | 保留真实延迟后的控制效果 |
| 外设/完整顶层 vs 实机需求 | 协议、超时、CDC、I/O时序和异常保护 |

复用未受影响的数学/历史证据，不全量重跑Step6/7/StudyL1，不改旧报告的验收结论。所有PWM/FOC工程和学习文件原位保留；真实接口先查已有资料，不重新泛问用户。

## 7. 阅读顺序

[HANDOFF](../coordination/HANDOFF.md) → [本轮M1B任务书](../coordination/tasks/m1b_repeat_moves_and_alignment.md) → [当前操作指南](PMLSM_FLOAT_BASELINE_GUIDE_ZH.md)与[PR47修订报告](../coordination/reports/pr47_host_interface_revision.md) → [M0报告](../coordination/reports/m0_simulink_model_asset_audit.md)/[差异表](MODEL_DIFFERENCE_AND_ASSET_AUDIT.md)。

[M1A设计](../coordination/specs/m1a_pure_simulink_float_baseline_design.md)、[旧Simple指南](PMLSM_MODEL_GUIDE_ZH.md)、[旧模型说明](../simulink模型/FPGA_Simulink_Model_Guide.md)、[旧交接](../coordination/HANDOFF_LEGACY_20261021.md)和[StudyL1](../learning/study_l1_speed_pi_hdl_compare/README.md)保留历史范围，不覆盖用户最新澄清。
