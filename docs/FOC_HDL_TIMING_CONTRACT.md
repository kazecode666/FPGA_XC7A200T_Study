# FOC HDL 时序、状态与逐位验证合同

2026-10-24，M3首版合同。正式算法源为`simulink模型/PMLSM_FOC_FixedPoint.slx/FOC_DUT`，最新本地源先快照，再在隔离副本生成。本文分别标记**A阶段已测事实**、**选定的首版协议/预留预算**与**仍待C/D验证的生成行为**，不能将后两类写成已完成结果。

## 证据身份与当前验证边界

A阶段初次结果：`.runtime/m3_20261024_001/preflight_result.json`，记录MATLAB `26.2.0.3386108 (R2026b)`、HDL Coder许可可用、PID19472、preflight=PASS。后续三相运行结果为`.runtime/m3_20261024_001/phase_three/preflight_result.json`，PID10152、preflight=PASS、phases=3。两份结果均记录3个正例位串比较通过、输出翻位负例及宽位低位翻转负例被拒绝；这不等于gm/RTL已验证。

实际来源接口/状态编译证据：

- `.runtime/m3_20261024_001/phase_three/tpfb39fb50_958c_47cf_bf5d_07baf57b6f89_preflight/source_ports.csv`
- 同目录`source_states.csv`。
- 同目录`pwm_phase_raw.mat`、`pwm_phase_events.csv`，保存三相控制command、ZOH和应用输出的运行事件。`preflight_result.json`的PWM字段写相对文件名时，定位基准是这次preflight工作目录，而不是假设run根层已有同名CSV。紧凑发布副本已在`docs/reports/m3_foc_hdl/pwm_phase_events.csv`，接口/状态亦见该目录`source_ports.csv`、`source_states.csv`及`preflight_result.json`。
- 首轮U相证据保留在`.runtime/m3_20261024_001/tp0b5601b5_7a1e_4edd_a8ed_4bf58ce28918_preflight/`，未被三相复核覆盖。

静态来源与风险另见[静态核查](reports/m3_foc_hdl/timing_static_audit.md)。本合同中的生成器时钟/reset/CE名称在B锁定最终RTL manifest后必须与实际端口核对；截至A，不存在已测RTL latency、状态提交cycle或50MHz实现时序结论。

## A已编译确认的9→3接口

下表是源模型实际编译类型，编译数据采样均为`[0.0001 0]`。HDL名称、最终signed声明和位序须由B实际生成的top/manifest补齐，不能只把模型名假设为最终RTL名。

| 源方向/顺序 | 名称 | signed | 位宽 | 小数位 | 意义 |
|---|---|---:|---:|---:|---|
| 输入1 | ia | 是 | 32 | 24 | 同一帧三相电流Apeak |
| 输入2 | ib | 是 | 32 | 24 | 同上 |
| 输入3 | ic | 是 | 32 | 24 | 同上 |
| 输入4 | theta_e | 是 | 40 | 32 | 控制电角度rad，不是替换后的真实角 |
| 输入5 | omega_e | 是 | 40 | 24 | 控制电角速度rad/s |
| 输入6 | iq_ref | 是 | 32 | 24 | 最终选择后的q轴参考Apeak |
| 输入7 | id_ref | 是 | 32 | 24 | 最终选择后的d轴参考Apeak |
| 输入8 | PI_Reset_EN | boolean | 1 | 不适用 | 原控制采样上的PI复位，属于该帧数据 |
| 输入9 | Vdc_V | 否 | 32 | 24 | 同拍母线V，同时供圆限幅与SVPWM |
| 输出1 | duty_u_cmd | 否 | 32 | 30 | 更新/死区前归一化上管command duty |
| 输出2 | duty_v_cmd | 否 | 32 | 30 | 同一帧V相command |
| 输出3 | duty_w_cmd | 否 | 32 | 30 | 同一帧W相command |

Duty的原始编码：0=`00000000`、0.5=`20000000`、1=`40000000`（8位hex，unsigned32/30）；有效物理范围为[0,1]，不是旧counts。这些只是类型的可表达编码，不保证算法在零参考时必然精确输出0.5：实际`.runtime/m3_20261024_001/A_short_source_hex.csv`的sample0三相均为`1ffffffa`，不能擅自换成`20000000`。刺激起始值必须在各测试显式声明；不能因初始算法状态为0便把Vdc也给0。

新增硬件控制端口与上述九路分开。配置首选名称是`clk`、同步高有效`reset`、`clk_enable`、`ce_out`，但B/C必须从实际生成文件回读名称、语义、极性和输出有效相位。

## A已测的控制采样与PWM应用关系

原模型结构是100µs ZeroOrderHold接50µs UnitDelay，三相delay初值为0.5；`Control_Tick_10kHz`的Priority=100。结构和priority本身不足以证明共同采样点顺序，因此已运行原环境的短时事件探针。

三相复核CSV包含129行、9个具名信号：每相0—1ms的command/ZOH与0—1ms每50µs应用值；U/V/W均有真实运行记录。下表以U相展示数值，原生成RTL的三相有效相位仍待C/D核对，不能把源环境运行关系写成已测RTL输出同步。

| 时刻 | command_u | zoh_u | applied_u | 归属 |
|---|---:|---:|---:|---|
| 0 | 0.5 | 0.5 | 0.5 | 初始command与delay保持值相同，单独看这一值不能分辨帧来源 |
| 50µs | — | — | 0.5 | 可与0s command对应 |
| 100µs | 0.499999993999639 | 0.499999993999639 | 0.5 | ZOH已取得本时刻command，应用输出仍保持上一采样command |
| 150µs | — | — | 0.499999993999639 | 应用100µs的command |
| 200µs | 0.499999847757618 | 0.499999847757618 | 0.499999993999639 | 继续读取上一50µs状态 |

对CSV全部可用配对点复核：三相command与各自ZOH在0、100、…、1000µs值相同；`applied(t+50µs)=command(t)`在每相t=0、100、…、900µs的10个可用配对成立，总计30个三相配对全部相同。由实际有变化的100→150µs等事件可辨识本帧的目标应用边界为采样后50µs。没有改变原ZOH、UnitDelay、默认死区或调度。

## 选定的首版核心协议与预算

以下是A后为B/C/D选择的**目标协议及预留预算**，不是已测RTL latency。

- 器件目标`xc7a200tfbg484-2`，时钟目标50MHz/20ns；沿用仓库已有器件与20ns XDC依据，不表示实际Fmax或板级时钟接线已验证。
- 数据帧周期100µs=5000个20ns时钟。外部九路输入在capture边沿前满足setup，并保持整个5000-cycle帧；首版不加额外输入适配寄存器，预留输入适配开销0拍。RTL测试应在capture边沿前驱动，不能在同一posedge竞争赋值/采样。
- `capture_cycle=0`为选定的首帧数据捕获参考；复位后的真实native捕获相位、计数器起点和首帧填充须C/D测定。每帧只能推进一次PI/AW算法状态，内部硬件时钟正常连续运行。
- 原采样到目标PWM应用边界为50µs，因此`apply_deadline_cycle=2500`，以该控制采样参考计数；不能改成5000拍，也不能通过移动PWM边界救deadline。
- 预留一个输出提交寄存器的1拍开销，另留至少1拍提交裕量。因此首版要求`native_core_output_valid_cycle <= 2498`；若core在2498拍有效，则提交寄存器在2499拍完成，相对2500拍边界尚有1拍裕量。
- 这一个输出提交寄存器是当前合同中**预留的下游提交预算**，不是声称现有模型或生成RTL已经实现了该适配。若以后实现薄适配，只能锁存/标记/保持，不计算FOC；其真实相位须进入C/D断言。

| 字段 | A后的目标/状态 | C/D必须取得的证据 |
|---|---|---|
| capture_cycle | 选定0；实际native值NOT_RUN | 输入帧在哪个硬件边沿被各路径接受；九路不会混帧 |
| core output_valid_cycle | 预留上界2498；实测NOT_RUN | 每帧最迟三相共同有效cycle、首帧/复位恢复相位 |
| output commit cycle | 预算为有效后1拍；实际NOT_RUN | 实际提交寄存/适配与CE关系 |
| state_commit_cycle | NOT_RUN | d/q积分、AW的实际提交phase及下一帧读到正确前态 |
| apply_deadline_cycle | 固定2500 | 沿用A源更新链，不移动边界 |
| margin_cycles | 最少1；实际NOT_RUN | `2500-actual_commit_cycle >= 1` |
| frame interval | 目标5000；实际NOT_RUN | 输出帧计数/顺序/无重复，反馈每控制帧推进一次 |
| CE暂停后的墙钟deadline | 不作为正常deadline通过证据 | 根据实际工具协议单列停顿/恢复结果 |

如果实际native capture在参考cycle之后、输入需要额外寄存、输出需要更多寄存或有效信号定义不同，必须按**同一个2500拍应用边界保守扣除实际开销**。例如capture实际为c>0，core相对capture可用延迟至多`2498-c`；不能把捕获参考后移后仍给予2498拍。若重算后不满足则判时序FAIL，仍可继续独立RTL/综合诊断，不能仅因吞吐量足够而声称deadline通过。

配置`Oversampling=5000`、Clock-Rate Pipelining和50MHz目标字段只是工具请求。B须回读生效值并导出实际调度，C/D须验证5000:1与输入/输出/状态事件。原源继承采样`-1`及其UnitDelay不能直接改成20ns；正常`clk_enable`不能未经核对变成每5000拍才脉冲一次，否则多拍运算可能被暂停。

## A已核对的算法状态与复位语义

实际`source_states.csv`编译结果如下；这些是源算法状态，不是尚未生成的RTL寄存器列表。

| 源路径 | SID | 编译表示 | 初值 | 数据更新采样 |
|---|---:|---|---:|---|
| FOC_DUT/Id/x_d_z | 47 | signed64/40 | 0 | [100µs,0] |
| FOC_DUT/Iq/x_q_z | 78 | signed64/40 | 0 | [100µs,0] |
| FOC_DUT/dq_voltage_limiter/Unit Delay | 213 | signed64/40 | 0 | [100µs,0] |
| 同处Unit Delay1 | 214 | signed64/40 | 0 | [100µs,0] |
| 同处Unit Delay2，限幅观测标志 | 215 | boolean | 0 | [100µs,0] |

PI使用old-state输出、KiTs积分和前拍raw-minus-limited AW。`PI_Reset_EN`选择当前raw输出零和下一积分零；AW状态没有直接PI复位输入，不能无条件立即清掉旧AW。C/D须先用饱和帧建立非零AW，再检查PI复位帧的旧状态、被复位raw输出及下一状态，另测持续复位和解除。不能只看解除后的duty相似便说复位一致。

硬件global reset的首版目标为同域同步高有效：初始化所需状态和调度/pipeline，reset期间不发布有效帧，计算中reset后不能泄漏旧帧。实际支持/复位寄存器映射和在途帧取消规则为NOT_RUN，必须由生成器报告、gm和RTL定向测试补齐。global reset不是原PI数据复位，也不是正常PWM禁止；不对板级异步reset同步释放作本轮承诺。

源状态→gm→RTL允许有经过证明的重编码/拆分，但必须记录实际名称、位宽、reset/enable与提交事件。不存在的同名RTL寄存器不能写成已逐位检查；无法直接一一对应时要给出等价映射和独立递推/后续输出证据。状态必须在下一控制帧读取前正确可用，不能用统一输出平移隐藏反馈错误。

## 数值、有效帧和实现时序的独立验收

| 层次 | 必须证明 | A后当前状态 |
|---|---|---|
| 原定点源→gm | 同一量化输入/初态、正确phase，三相有效输出0 bit mismatch，PI/AW对应状态正确 | NOT_RUN |
| gm→SystemVerilog/xsim | 同cycle有效帧逐位、无X/Z/漏帧/重复/三相混帧；至少1024连续帧及256真实前缀帧 | NOT_RUN |
| 输出→应用边界 | 上述固定deadline、实际开销及至少1拍margin；状态下一帧可用 | NOT_RUN |
| 核心OOC综合 | 同份已验证RTL，20ns约束，真实资源和内部寄存路径估算 | NOT_RUN |
| 布线时序/RTL电机联合仿真/硬件 | 明确留M4以后，本轮不执行 | NOT_RUN、范围外 |

PI/AW64位和DivideWide72位必须从fi对象无损导出原始位串/hex；分别保留16/18个hex字符及明确二补码/扩展规则。不得经double十进制中转低位后声称相同。M2已有数值容差和受限例外不适用于M3；任何新位差、错周期或反馈时序错误均独立失败。

生成TB不能替代原定点→gm检查；比较器必须另用最低位翻转和有效cycle错位负例证明会失败。启动无效区间由真实reset/pipeline规则定义，不任意跳过失败首N帧。CE额外诊断按真实支持协议执行，不伪造握手；必要的纯输出延迟补偿必须是已测相位，并与反馈状态证明分开。

新OOC约束只能绑定实际clock端口，禁止全局false_path或5000倍multicycle遮蔽每时钟路径；外部ADC/板级I/O没有合同则明确未签核。OOC完成、资源是否容纳、20ns综合估算是否满足分别报告；未布线结果不能被描述成最终时序或可上电结论。
