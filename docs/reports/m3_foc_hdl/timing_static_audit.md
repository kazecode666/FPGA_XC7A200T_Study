# M3 来源、时序和位比较静态核查

2026-10-24，独立只读核查本机最新磁盘文件；没有使用MATLAB MCP、没有加载/保存模型、没有运行Vivado或修改算法。本文件是A阶段运行核查的检查清单，**不把静态XML当作实测事件顺序、时延或deadline证据**。

## 共享模型的真实更新链

来源：`simulink模型/PMLSM_PI_FOC_Float_Baseline.slx`内部`system_root.xml`、`system_771.xml`、`system_866.xml`，以及唯一初始化脚本。

| 项 | 静态事实 |
|---|---|
| 控制调用 | root SID785 `Control_Tick_10kHz`：FunctionCallGenerator，SampleTime=`Ts`，Priority=`100`；调用SID505 `Control_Task_10kHz` |
| 外部控制周期 | init第24—27行：`T_pwm=Ts_ACR=Ts=1e-4`，`Ts_ASR=10*Ts_ACR`，`Ts_POS=10*Ts_ASR` |
| 对象周期 | `Ts_Plant=PMLSM_Ts_s=1e-6` |
| PWM更新链 | Inverter SID771中SID866 `PWM_Update_HalfTs`，三相均为100µs ZOH→50µs UnitDelay |
| 三相ZOH | SID870/875/878，`ZeroOrderHold`，SampleTime=`Ts` |
| 三相UnitDelay | SID871/876/879，SampleTime=`M1A_PWM_Update_Delay_s=T_pwm/2`，InitialCondition=`0.5` |
| 源中保存的速率表 | `ScheduleCore.xml`列1µs、50µs、100µs三个周期，调度方向`HighNumberLast`；不是逐块执行顺序报告 |
| 原死区 | init第50—52行：1µs平均死区，比率=`1e-6/1e-4`，电流判定阈值1e-4A；保持原值 |

这不是一个连续时间的“命令后无条件延迟50µs”。100µs ZOH和50µs UnitDelay在0、100µs等时刻有共同采样事件，UnitDelay输出也有状态读取/更新阶段。Priority=100提示需要关注顺序，但数据依赖和编译排序也参与，**不能仅凭priority断言ZOH一定看到旧值或新值**。若ZOH看到当前控制帧，下一50µs边界才可能应用该帧；若看到上一帧，关系会不同。

根执行者须在隔离副本记录三相command、ZOH输出、UnitDelay输出及实际compiled/sorted顺序：至少覆盖0、50、100、150、200µs，并用可辨认的逐帧值或真实有变化的command验证样本归属。对0.5初始保持、第一非零命令和同一时刻执行顺序分别记录。由这个实测关系冻结采样→目标应用边界；不要因为变量名为HalfTs便预先保证2500个硬件时钟。

## 独立固定FOC接口与状态

来源：最新`simulink模型/PMLSM_FOC_FixedPoint.slx`的root、system_23/52/184；参数来自`pmlsm_foc_fixed_config.m`。M2历史`compiled_types.csv`提供对应类型记录，但M3仍须重新编译确认当前源。

| 根端口 | 类型来源 | 预期固定表示 |
|---|---|---|
| ia/ib/ic，1—3；iq_ref/id_ref，6—7 | Current | signed32，小数24 |
| theta_e，4 | Angle | signed40，小数32 |
| omega_e，5 | Omega | signed40，小数24 |
| PI_Reset_EN，8 | boolean | 1bit，数据帧的一部分 |
| Vdc_V，9 | Bus | unsigned32，小数24 |
| duty_u/v/w_cmd，输出1—3 | Duty | unsigned32，小数30；为更新/死区前command |

| 状态/关键中间量 | 源SID | 采样/类型事实 |
|---|---:|---|
| `FOC_DUT/Id/x_d_z` | 47 | UnitDelay，SampleTime=-1；M2编译记录sfix64_En40 |
| `FOC_DUT/Iq/x_q_z` | 78 | 同上 |
| `FOC_DUT/dq_voltage_limiter/Unit Delay`，d轴AW | 213 | UnitDelay，SampleTime=-1；输入为SID210的raw-minus-limited，M2记录sfix64_En40 |
| 同子系统`Unit Delay1`，q轴AW | 214 | 输入SID211，M2记录sfix64_En40 |
| 同子系统`Unit Delay2`，限幅观测标志 | 215 | UnitDelay，SampleTime=-1；M2记录boolean；不应被误当第三个积分器 |
| 同子系统`Divide` | 192 | 输出DivideWide=unsigned72，小数40；不是64bit状态 |

各UnitDelay没有在块XML里显式保存InitialCondition；不要仅把缺省属性当成当前运行的已核对初值。须用MCP读回真实初值并记录首帧；当前配置工程范围规定零状态起点。独立源输入/状态继承采样，configSet0.json明确`STIndependent`及`FixedStepDiscrete`；继承`-1`不能作20ns硬件速率。生成副本或最小调度必须先建立100µs数据周期，再核对5000:1实际硬件调度。

## PI复位、状态事件与global reset

d轴SID42/43、q轴SID73/74分别是`Reset_Integral`和`Reset_Output`：PI_Reset_EN经>0.5判定，选择Work类型零或正常结果。积分正常递推来自旧积分、KiTs误差及前拍AW；当前raw输出也使用旧积分。AW UnitDelay213/214没有直接PI_Reset_EN输入，只接本帧raw-minus-limited。因此不能把PI_Reset_EN替换成全核心/全部pipeline复位。

重要定向测试：先以饱和帧建立非零前拍AW，再发一帧PI_Reset_EN。核对该帧可观察到的旧AW/旧积分、被复位的raw输出，以及提交后的次态；下一帧AW可能自然因reset后的raw/limited为0而归零，但这不等同于在PI-reset帧直接清掉旧AW。M3 global reset则要清已定义的初值和pipeline/调度并取消规定的在途帧，不能以PI复位测试代替。

生成流水线可将状态拆分/重编码；映射表应注明实际RTL/gm状态、提交cycle以及等价依据。不要把源码UnitDelay的100µs含义解释成每20ns推进一次，也不要用统一输出平移掩盖反馈递推错误。原有5个算法delay与生成器新增pipeline寄存器分列。

## 精确位串与记分器风险

M2的`m2_run_foc_sequence.m`可作刺激/记录方式参考，但`m2_test_foc_unit.m`把数据转double并按数值容差比较，**不能直接作为M3的零位差比较器**。

- 用fi对象本身的`bin`/`hex`或经验证的等价无损方式导出；先固定signed、WL、FL，再写数据。64bit状态为16个hex字符，72bit中间量为18个，不经`double(storedInteger(...))`或十进制浮点中转。负数保留二补码及扩展规则，40bit输入也保留明确宽度。
- 三相输出同一sample_id、同一有效cycle检查。禁用区间只能来自真实reset/首帧填充合同，不能自动跳过首N个不一致样本。
- testbench与独立scoreboard要证明两层：源定点→gm，gm→RTL；生成TB通常只提供后者，不能替代前者。
- 原始期望最低位翻转和有效周期错位均必须被独立比较器拒绝；不能只改变DUT或只看编译退出码。
- 全局CE测试按实际生成器协议执行。正常内部运行不能把clk_enable当每5000拍才有效的sample脉冲；CE停顿造成墙钟deadline变化须单列，正常deadline证据使用连续时钟。
- 至少1024帧连续/边界及至少256帧真实FOC输入。真实片段无合法内部快照时，从零初态保留所需完整前缀，不截峰值清状态。M2受限例外不豁免M3任何新位差/复位/时序错误。

## 目标器件与20ns既有证据

- `FOC_Current/FOC_Current.srcs/constrs_1/new/foc_current_clock.xdc:1`：`create_clock -name sys_clk -period 20.000 [get_ports clk]`。
- `FOC_Transforms/FOC_Transforms.srcs/constrs_1/new/foc_transforms_clock.xdc:1`相同。
- `PWM_Controller/.../pwm_timing.xdc:2`及`bx72_step5a.xdc:7`也有20ns目标。
- `scripts/step3_synthesis.tcl:20`、多个`step6*.tcl`明确核对`xc7a200tfbg484-2`。这些旧脚本可能含完整implementation，**本轮不得整套重跑它们**。

因此M3的器件/20ns目标有仓库来源，仍不是本轮已实现Fmax、板级clock接线或I/O时序结论。新的OOC约束必须落到实际生成clock端口，数据端口不全接常量，不引入5000倍multicycle/global false_path遮蔽每时钟路径；外部I/O没有合同就明确未签核，不虚构ADC delay。只OOC综合，不进入place/route、bitstream或硬件。
