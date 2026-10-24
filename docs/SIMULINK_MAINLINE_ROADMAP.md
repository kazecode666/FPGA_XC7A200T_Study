# Simulink 主导的 FPGA 电机控制主线

更新：2026-10-24。按已合并 PR50 完成 M2 实际定点模型与共享闭环证据，[整合验收](../coordination/reports/m2_foc_fixed_point_implementation.md)等待实现 PR Review。M1B 历史保留；HDL/C 生成、Vivado 和硬件阶段尚未执行。

## 1. 目标与非目标

以Simulink研究和维护控制算法，保留浮点闭环参考，另建面向硬件的定点控制器实现；由HDL Coder生成算法HDL，使用Vivado检查资源和时序，并回到共享闭环验证实现影响，最后接入真实控制器与板级接口。

首个FOC算法来源仍为PR47继承、PR49保留的Simple PI-FOC；完整MIL中的DPCC/DPICC/PICDO继续保留研究，不加入首轮迁移。旧手写FOC/PWM作为学习及验证资产，不强制作为正式实现底座。

不长期维护三套并行生产算法，不把整个带电机的MIL顶层生成HDL，不建设产品级基础设施，不由仿真通过推定可安全上电。

## 2. 本轮范围和已确定行为

M2先抽取独立根层FOC，消除触发父层问题，处理内部未选中除法0/0，再设计范围/位宽并完成真正的定点数值与共享闭环验证。保留原浮点参考；Host/轨迹、原对齐、外环、平均逆变器和电机对象暂不定点化。不能外层加类型转换、内部仍浮点就称完成。

已实现的是**同一次仿真到位后再发位置目标**，不增加运动中重规划；默认三闭环，其他模式停止后选择。原对齐默认旁路，Start的既定正常操作保持，不重新设计启动/复位协议或加入未知偏置新算法。

PWM关闭后机械/仿真继续是正常既定行为；PI复位不是全部故障清除。完整故障锁存/驱动板恢复、行程管理、死区补偿、真实测速滤波及JMAG/Maxwell替换留后，不作为本轮定点化的前置工程。

## 3. 模型与参数职责

| 对象 | 职责 |
|---|---|
| `PMLSM_PI_FOC_Float_Baseline.slx` | 原浮点参考及唯一共享闭环环境；M2仅增加必要实现选择和边界适配 |
| `init_PMLSM_PI_FOC_Float_Baseline.m` | 唯一人工初始化；Base参数/命令及自动派生类型配置，简洁中文分节 |
| `PMLSM_FOC_FixedPoint.slx/FOC_DUT` | 已建立实际固定类型独立源，无触发父层，共享环境Normal Model Reference引用 |
| `pmlsm_foc_fixed_config(p)` | 实际纯配置函数，类型、量化系数和声明范围统一来源 |
| 旧Simple | 原算法、外环和plant来源及历史对照，只读 |
| 完整MIL + ControlCore | 原对齐及系统语义来源，只读 |
| DSP实机模型 | 原对齐及外设语义核对，TI外设不视为FPGA已实现接口 |

独立DUT和主模型通过同一实现源引用，不另维护一套plant/工况。原理想反馈继续保留；真实角/控制角分离保持，定点控制角不能反过来替换电机真实坐标。

## 4. 阶段与退出条件

| 阶段 | 工作 | 退出条件 |
|---|---|---|
| M0：已合并 | 模型/参数审计与资料补齐 | PR44接受，动态/板级事项未冒充完成 |
| M1A：已合并 | 独立浮点模型、外部init、操作面板、具名记录及限定回归 | PR47接受，基础控制参数作为参考固定 |
| M1B：已合并 | 连续点位、原MIL可选对齐、操作/回归和FOC只读准备 | PR49接受；未知非零偏置与鼠标UI未冒充通过 |
| **M2：实现待Review，连续点位预算未过** | 独立FOC、数值边界、范围/固定类型、状态与共享闭环、兼容性检查 | 已交实际SLX/配置/类型/数值及兼容性证据；受限范围与失败记录见整合验收；开放实现PR不自动合并 |
| M3：生成与RTL验证 | 从接受的实现模型生成HDL，与相应实现参考比较 | 状态/复位/使能/有效数据/流水线映射正确，可复现生成 |
| M4：实现与闭环验证 | Vivado资源/布局布线时序，RTL接入共享环境 | 满足时限/资源，真实采样/计算/PWM延迟进入闭环 |
| M5：完整控制器及板级集成 | 按真实需求完善运行保护、驱动恢复、在线参数、测量链及外设 | 完整顶层和异常场景验证，不沿用单算法通过代替 |
| M6：另行批准的上板 | 先I/O和安全关断，后受控功率级和电机 | 独立方案、授权和实际结果 |

M2可连续完成任务A—F，但不自动开始M3。checkhdl通过也不保证生成成功或时序满足。M3/M4为迭代关系，实现改变后补受影响验证。

## 5. M2接口和必须保持的边界

FOC覆盖Clarke/Park、dq PI/前馈、圆限幅/AW、反Park和SVPWM。新独立实现保留原8输入顺序，新增第9母线Vdc_V端口；原报告中内部Constant Udc不能被误称成已有端口。新配置`FOC_Impl_Select`在停止后选原浮点0/定点1，不是热切控制模式。

三相输出仍为死区前、PWM应用更新前归一化上管command duty，不等于active duty/门极。电流/PWM100us、速度1ms、位置10ms、plant1us、一次50us更新及1us平均死区保持；不因定点仿真改变plant步长或重复增加死区。

M2每次调用是一份同拍输入，暂不增加sample_valid/事务握手/在线调参。PI_Reset_EN保留old-state输出、积分复位和前拍AW的不同语义，不等同于HDL全局reset。参数量化来自同一外部源，不重整定。

范围表必须分清资料上限、当前配置、仿真观察和首版工程范围。缺额定资料可做明确受限原型，不猜硬件最大值或套旧24bit/2500。类型/预算在结果前冻结；非预期数值饱和不能冒充正常圆限幅。误差超预算先改类型或等价实现，不调PI、放宽死区或删除失败场景。

## 6. 验证与历史复用

| 比较/检查 | 回答的问题 |
|---|---|
| 原浮点→独立浮点适配 | 抽取、母线显式化、局部除法保护有没有静默改算法 |
| 同拍浮点→实际定点 | 入口/系数量化和内部舍入对运算、状态与饱和的影响 |
| 同环境闭环float/fixed | 电流、位置、速度及指令/对齐功能是否符合冻结预算 |
| 编译类型/溢出/checkhdl | 是否真的定点、位增长足够、选定结构兼容；不是时序验收 |
| 定点参考→生成模型→RTL | M3验证状态和逐位逐周期、valid及流水线关系 |
| RTL闭环 vs 参考 | M4保留真实延迟后的控制效果 |
| 外设/完整顶层 vs 实机需求 | M5/M6协议、超时、CDC、I/O时序和异常保护 |

M2固定输入事件和时间轴，不平移曲线凑一致。Ready可能因量化改变时刻，单独报告，不修改原到位窗。默认保持真实死区，纹波抑制不是本轮目标。

复用未受影响证据，不全量重跑Step6/7/StudyL1，不改旧报告结论。所有PWM/FOC学习文件原位保留；真实接口先查已有资料，不重新泛问用户。

## 7. 阅读顺序

[HANDOFF](../coordination/HANDOFF.md) → [当前M2任务书](../coordination/tasks/m2_foc_fixed_point_implementation.md) → [FOC准备报告](FOC_FIXED_POINT_READINESS.md) → [M1B验收](../coordination/reports/m1b_repeat_moves_and_alignment.md)与[当前浮点指南](PMLSM_FLOAT_BASELINE_GUIDE_ZH.md)。

[M1B任务](../coordination/tasks/m1b_repeat_moves_and_alignment.md)、[M1A设计](../coordination/specs/m1a_pure_simulink_float_baseline_design.md)、[旧Simple指南](PMLSM_MODEL_GUIDE_ZH.md)、[旧模型说明](../simulink模型/FPGA_Simulink_Model_Guide.md)、[旧交接](../coordination/HANDOFF_LEGACY_20261021.md)和[StudyL1](../learning/study_l1_speed_pi_hdl_compare/README.md)保留历史范围，不覆盖当前任务。
