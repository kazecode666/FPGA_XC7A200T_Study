# FOC定点化/HDL只读准备（M1B）

2026-10-24，MATLAB/Simulink R2026b 26.2.0.3386108。仅盘点当前浮点源和临时副本，**没有定点SLX、HDL/C生成、综合或硬件操作**。审计入口 `scripts/m1b_foc_readiness_audit.m`；原始输出见[结果索引](reports/m1b_repeat_moves_alignment/README.md)。

## 实际边界

DUT候选为 `PMLSM_PI_FOC_Float_Baseline/Control_Task_10kHz/FOC_Algorithm`，SID546。它在function-call控制任务内继承执行，编译采样标识含 `[Inf 0]`（常量）和 `[-1 -1]`（继承），不能将继承标识当周期。内部算术实测日志间隔100 µs，外层Function-Call Generator为Ts=100 µs；速度1 ms、位置10 ms在边界外。

| 端口 | 当前数据类型/单位 | 实际来源/含义 |
|---|---|---|
| ia/ib/ic，1—3 | double，Apeak | 同一plant三相电流反馈，经显式Control_Task端口 |
| theta_e，4 | double，rad | Alignment_Interface选择理想角度或原MIL固定/反馈控制角；物理真实角不跟随此选择 |
| omega_e，5 | double，rad/s | 原理想电速度；原对齐Angle_Init_EN时按原路径置0 |
| iq_ref，6；id_ref，7 | double，Apeak | 原Reference_Manager之后的原对齐电流/禁止选择器最终值；日志iq_ref/id_ref对应这里 |
| PI_Reset_EN，8 | boolean | 原请求 OR PWM禁止路径，有效复位。没有全局故障清除语义 |
| duty_u/v/w_cmd，输出1—3 | double，归一化上管占空比 | PWM应用更新/平均死区之前的command duty，不是active duty或门极 |

**没有Vdc输入端口，也没有独立enable端口。** 母线来自Base参数Udc（48 V）及FOC内部SVPWM/圆限幅Constant。使能在外层PWM路径和有效PI复位路径体现；M2是否增加母线/enable接口必须明确设计，不能宣称现在已存在。[编译类型](reports/m1b_repeat_moves_alignment/foc_compiled_interface.json)、[参数和使用位置](reports/m1b_repeat_moves_alignment/foc_parameters.csv)。

## 实际模块与状态

[完整块表](reports/m1b_repeat_moves_alignment/foc_blocks.csv)列出具体SID、BlockType、库链接及表达式，包括当前活动库变体内部；不把不可见/非活动变体当成已执行。

| 路径/关键SID | 实际结构 | 定点准备事项 |
|---|---|---|
| Clark，553 | 自建Gain/Sum矩阵 | 电流输入范围、系数量化、加法扩展位 |
| Park，617；InversePark，590 | Motor Control Blockset `mcbeeMathTransformLib`库链接；当前mcb分支有sine/cosine LUT、索引/包角 | 角度单位、周期边界、LUT/插值与量化误差；不能只按名字认定最终HDL架构 |
| Id，566；Iq，591 | 自建Gain/Product/Sum/Switch、解耦/前馈及离散PI | Kp=8.725、Ki=11850、Kaw=0.1358166189111748；Ts=100 µs。保留old-state输出、复位和前拍AW语义 |
| x_d_z，586；x_q_z，613 | UnitDelay，初值0 | 电流积分状态，无独立全局硬限；AW不能替代已证明的状态最大范围 |
| dq_voltage_limiter，698 | 平方/加法/Sqrt/Divide/MinMax/比较/乘法 | 开方、除法保护、圆限幅前原始电压和中间平方的位增长 |
| du_d_z，727；du_q_z，728 | UnitDelay，初值0 | 前拍AW反馈。另有延迟sat_flag，仅观测/终结，不能误当本拍AW |
| SVPWMG | 自建Fcn（表达式）、Product/Math、Switch/MultiPortSwitch、归一化和扇区选择 | Sector控制当前为double；T1/T2重标定存在分母为0时的未选中分支，必须在定点实现中定义 |

速度积分 `x_speed/speed_memory` 位于外层，实测1 ms，**不属于首个FOC定点DUT**。

## 当前工具检查结果与限制

已先阅读本机 `help('checkhdl')` 和当前官方[checkhdl文档](https://www.mathworks.com/help/hdlcoder/ref/checkhdl.html)。采用 `checks=checkhdl(dut)` 返回值形式，在独立进程临时SLX上执行，不生成报告/HDL；未调用makehdl、makehdltb或Workflow。官方同时说明检查通过也不能保证代码生成完成。

实际结果：**1 Error、11 Warning、3 Message，未通过HDL兼容性**。[完整诊断](reports/m1b_repeat_moves_alignment/foc_audit.json)。

- Error `hdlcoder:validate:DutInsideTrigger`：候选DUT位于触发/function-call子系统内部，不能直接作为当前层次的顶层设计单元。M2应抽取独立离散FOC实现，外部明确保持采样/使能和状态合同；本轮不为通过检查改浮点层次。
- Warning包括 `ControlPortIsFlPtType`、`InefficientSwitchCriteria`：SVPWM扇区/Multiport控制为浮点，潜在额外转换和延迟；另有可调参数影响共享的 `ReuseRequiresInvariantConstants`。中文注释产生3条I18N Message。
- 因层次检查失败，且本轮仍是double，**不能声称已证明所有块的定点HDL支持、延迟或资源**。每个最终数据类型、运算架构、参数组合仍须在M2独立DUT逐项复查。
- 临时观测SVPWM全部数值分支时，T1T2 Calculate/Fcn1、Fcn2各出现1199个NaN（0/0）。它们位于零矢量/未选中候选分支；本轮标准工况所有实际FOC输出、PI状态及正常具名信号有限，默认数值与参考一致。有限输出不代表内部除法已具备定点安全语义。原算法未修改，该项是明确的M2风险。

[makehdl](https://www.mathworks.com/help/hdlcoder/ref/makehdl.html)属于生成操作，本轮未执行。审计副本、观测MAT和缓存留在 `.runtime/m1b_20261024/foc_audit_*`，源SLX不由审计保存。

## 观察范围与设计范围分开

[全部170个数值端口范围](reports/m1b_repeat_moves_alignment/foc_observed_ranges.csv)包含1 mm/1.2 s的输入、中间量、积分/AW和输出，列出有限min/max及NaN/Inf数量；NaN不能被当作0纳入范围。[多场景表](reports/m1b_repeat_moves_alignment/foc_scene_ranges.csv)补充实际live正反短程及4.5 s标称对齐的输入/状态观察。它们都只是**仿真已观察范围**，不是硬件最大值。

设计依据：Udc=48 V时圆限幅半径 `0.9*Udc/sqrt(3)=24.9415316289918 V`，限定的是输出电压向量，不限定限幅前PI/解耦中间量。速度环Iq限幅1 A仅限制该外环路径；手动电流参考并无同一全局硬上限。对齐目标0.5 A也不能代替传感器/驱动器极限。θ周期范围需要对输入接口约束，当前理想反馈不能证明真实测量链永远合法。

以下设计上限仍缺，**不猜Q格式或沿用旧RTL24bit/2500**：相电流与过载持续时间、母线最大/最小值、最大机械/电速度、允许安装偏差、积分/AW最坏状态、原始电压和平方/乘积动态范围、系数更新范围、扇区异常输入处理。Clarke/Park应由实际Gain矩阵及确定的输入最大值推导位增长，再用边界场景验证；观察min/max只提供量级。

## M2最小工作包建议（未实施）

保留同一Host、外环、原对齐、平均逆变器、延迟/死区和plant浮点环境；只新增独立FOC定点实现，共享物理参数和输入场景。先定义八个接口和母线策略，再确定电流、角度、速度、电压、duty、积分/AW及平方/乘积的字长候选与舍入/饱和规则；控制布尔量与sector整数分开。没有设计上限的类型项先标待定。

按Clarke/Park→dq PI/前馈→圆限幅/AW→反Park/SVPWM逐段验证。必须保持old-state PI、前拍AW、同拍复位和采样相位，覆盖正负电流、极限速度/母线、圆限幅、0分母、θ=0/2π、扇区边界、PWM禁止/复位及溢出。最后比较共享闭环误差，单独定义计算延迟预算；不能用增加流水线后仍按零延迟闭环来验收。M2评审接受后才进入HDL生成阶段。
