# FOC HDL 时序、状态与逐位验证合同

2026-10-25最终结果。唯一正式算法源是`simulink模型/PMLSM_FOC_FixedPoint.slx/FOC_DUT`；生成和验证使用最新本地源的受控副本。**完整C数值验证、D七组RTL验收及F重复构建通过；E综合完成且资源满足，但20ns综合时序失败，WNS=-58.833ns，M3整体接受仍为FAIL。** 没有用行为仿真的周期预算替代物理时序验收。

机器可读合同见[cycle_contract.json](reports/m3_foc_hdl/cycle_contract.json)，实际端口和状态分别见[hdl_ports.csv](reports/m3_foc_hdl/hdl_ports.csv)、[state_mapping.csv](reports/m3_foc_hdl/state_mapping.csv)。

## 来源和证据身份

- A的实际类型、状态和三相PWM事件见`docs/reports/m3_foc_hdl/source_ports.csv`、`source_states.csv`、`pwm_phase_events.csv`及`preflight_result.json`。A运行MATLAB R2026b，三相复核保留原始MAT，未覆盖初次U相记录。
- 最终B3构建由`.runtime/m3_20261024_001/final_build.json`指向`tp450e181c_3ee1_420b_ac2e_9af8577c939f_generate`。发布索引为[B_generated_manifest.json](reports/m3_foc_hdl/B_generated_manifest.json)；下述名称、状态和周期均核对这份最终`FOC_DUT.sv`、`FOC_DUT_tc.sv`、`Id.sv`、`Iq.sv`、`dq_voltage_limiter.sv`及gm归档。
- C完整结果见[model/model_result.json](reports/m3_foc_hdl/model/model_result.json)。原始运行目录为`.runtime/m3_20261024_001/tp25d5cc5c_3460_4440_9090_f32667add1af_model/`，保留source/gm/validation原始MAT、逐位CSV、分母和下一态结果。
- D完整聚合见[rtl/rtl_result.json](reports/m3_foc_hdl/rtl/rtl_result.json)，其中七组引用同一最终manifest：17帧normal、CE、reset、两个真实负例，以及1024帧边界和1536帧真实前缀。负例保留工具FAIL，wrapper仅在确实拒绝注入错误时给gate PASS。
- E聚合见[ooc/synth_stage_result.json](reports/m3_foc_hdl/ooc/synth_stage_result.json)，原始工具结论见[ooc/ooc_result.json](reports/m3_foc_hdl/ooc/ooc_result.json)及[分析](reports/m3_foc_hdl/ooc/analysis_zh.md)。F见[repro/repro_result.json](reports/m3_foc_hdl/repro/repro_result.json)。

器件`xc7a200tfbg484-2`、50MHz/20ns是沿用仓库资料的实现目标；gm/xsim采用理想20ns时基。**OOC的20ns setup WNS=-58.833ns，目标50MHz未满足；5.48µs和44.5µs均只是行为仿真/目标时钟换算，不能作为物理硬件deadline通过证据。** 未进行布局布线、板级I/O签核或硬件操作。静态资料与A的检查边界见[静态核查](reports/m3_foc_hdl/timing_static_audit.md)。

## 实际9→3算法接口和新增硬件端口

源模型实际编译数据周期为`[0.0001 0]`。B3的算法端口名称与源一致；全部位序、声明、初始驱动要求及reset/enable语义见端口CSV。

| 方向/源顺序 | 名称 | RTL表示 | 小数位 | 含义 |
|---|---|---|---:|---|
| 输入1—3 | ia / ib / ic | signed [31:0] | 24 | 同帧三相电流Apeak |
| 输入4 | theta_e | signed [39:0] | 32 | 控制电角度rad |
| 输入5 | omega_e | signed [39:0] | 24 | 控制电角速度rad/s |
| 输入6—7 | iq_ref / id_ref | signed [31:0] | 24 | 最终选择后的q/d轴参考Apeak |
| 输入8 | PI_Reset_EN | logic | 0 | 原控制采样上的PI复位数据 |
| 输入9 | Vdc_V | [31:0] unsigned | 24 | 同拍母线V，供限幅和SVPWM |
| 输出1—3 | duty_u_cmd / duty_v_cmd / duty_w_cmd | [31:0] unsigned | 30 | 应用更新和死区之前的归一化上管command duty |

Duty类型编码0=`00000000`、0.5=`20000000`、1=`40000000`，有效物理范围[0,1]，不是旧counts。类型编码不能代替实际期望：短序列sample0三相实际均为`1ffffffa`，原样进入比较器。Vdc不能因算法状态零初始化而被设为零，受限输入范围仍为12—60V。

B3新增硬件端口如下；它们不存在于原模型/gm的九路数据接口中。

| 实际名称 | 方向 | 已核对语义 |
|---|---|---|
| clk | 输入 | 上升沿时钟，xsim周期20ns |
| reset | 输入 | 同步高有效global reset，优先于CE，清算法状态、pipeline及TC |
| reset_FOC_DUT_tc | 输入 | 额外TC复位，TC内部为`reset | reset_FOC_DUT_tc`；正常协议固定接0。单独脉冲此口未经验证，不作为本轮正常接口功能 |
| clk_enable | 输入 | 全局快时钟使能；正常连续1，不能当每5000拍一次的sample strobe |
| ce_out | 输出 | 等于快CE，速率20ns；**没有独立frame-valid含义，也不自带reset屏蔽** |

核心没有九路共用的输入捕获寄存器，也没有原生output-valid端口。首版以外部整帧稳定输入和经过验证的固定相位定义事务。外围若需要锁存/有效标志，只能作薄适配；本文中的1拍输出提交寄存器仍是预算，尚未声称已有该寄存器。

## 原环境的PWM应用边界

原共享模型的三相链路均为100µs ZeroOrderHold接50µs UnitDelay，delay初值0.5。`Control_Tick_10kHz`的Priority=100；结构和priority本身不足以证明同一时间点执行顺序，A因此记录了实际三相事件。

三相command与各自ZOH在0、100、…、1000µs一致；全部30个可配对点满足`applied(t+50µs)=command(t)`。例如100µs的U相command/ZOH为0.499999993999639，此时应用仍为0.5，到150µs才应用该command。证据是三相9通道CSV及原始MAT，没有改变原保持链、默认死区或调度。

据此冻结目标应用边界为控制采样后50µs，即2500个20ns时钟。不能改成5000拍，也不能将理想20ns时基下的5.48µs机械加在原50µs之后；计算和预留提交的目标仍须在原2500拍窗口内完成。当前物理实现因20ns时序FAIL尚未证明能按这一时基执行。

## 周期编号与每帧事件

使用两种明确的坐标：

- 源/gm：sample_id从0开始，原生数据时刻为`n*100µs`。gm三相内层DUT快输出在`n*100µs + 274*20ns`取样；sample0的时刻是5.48µs。四个映射旧态在`n*100µs`读取。
- RTL独立checker：每个数据帧的**已接受上升沿编号为1…5000**，输入在此前的negedge建立，并保持穿过该帧第5000个边沿。状态旧值在posedge之前读取，输出和提交寄存器在posedge及NBA更新之后读取。第274拍就是编号274，不再人为减1。

`capture_cycle=0`保留为外部setup/帧起点的逻辑参考，输入适配开销为0；它不是声称RTL存在一个名叫cycle0的九路捕获寄存器。各组合路径可持续看到稳定输入，原算法状态每5000个接受时钟只推进一次。输入在本帧第5000拍提交完成后的下一negedge才能换下一帧，避免PI提交混入新输入。

| 帧内事件 | 实际观察/更新点 | 解释 |
|---|---|---|
| 三相共同输出 | 第274拍post-edge | 三相固定相位均为274，完整17/1024/1536帧逐位比较和xsim已验证；不是使用ce_out当valid |
| PI旧态/前拍AW消费 | 第5000拍pre-edge | 比较`x_d_z_out1`、`x_q_z_out1`和顶层`dq_voltage_limiter_du_d_z/q`；此时TC pre-count=0且phase_0=1 |
| d/q PI下一态提交 | 第5000拍post-edge | `enb_1_5000_0`使能两个PI寄存器；下一帧读取新积分 |
| AW下一态进入旁路寄存器 | 下一帧第1拍post-edge | `enb_1_5000_1`使能AW bypass寄存器；同使能下consumer为producer旁路，不能在任意相位把bypass寄存器当作完整AW等价状态 |
| 下一数据帧 | 每5000个接受时钟 | 正常CE持续1；不能每快拍反复推进PI/AW |

TC真实reset初态为`count5000=1, phase_0=0, phase_1=1`。两个phase本身经过寄存；因此不能只看count常量推测使能边沿。独立checker同时按counter/phase方程逐边沿检查TC及四个算法寄存器的更新/保持，完整1024/1536帧序列也执行这些断言。

短normal报告的`first_output_cycle=276`是**包含两个初始reset物理边沿**的绝对编号，即2+274，不表示core latency为276。后续物理cycle同样不能直接替代帧内相位；reset、CE暂停和epoch要单独计数。

## 旧态、下一态和复位映射

| 源状态SID | 源表示/初值 | 最终gm映射 | 最终RTL映射 |
|---|---|---|---|
| 47，Id/x_d_z | signed64/40，0 | SID384 Delay，100µs | `u_Id.x_d_z_out1` |
| 78，Iq/x_q_z | signed64/40，0 | SID297 Delay，100µs | `u_Iq.x_q_z_out1` |
| 213，AW d Unit Delay | signed64/40，0 | SID350 RateTransition，100µs输出 | `u_dq_voltage_limiter.Unit_Delay_bypass_reg`及consumer mux |
| 214，AW q Unit Delay1 | signed64/40，0 | SID349 RateTransition，100µs输出 | `u_dq_voltage_limiter.Unit_Delay1_bypass_reg`及consumer mux |
| 215，限幅观测Unit Delay2 | boolean，0 | 最终生成核心删去未使用观测态 | 未虚构同名RTL寄存器，也不计入四项PI/AW比较 |

源和gm的原生100µs状态日志是更新前旧态。C3完整比较三相输出和四个旧态：17帧119个stored words、1024帧7168个、1536帧10752个，合计18039个，位差和值差均0。探针另比较`source next(n) == gm old(n+1)`，包含末帧提交，共17次提交、68个状态值，位差为0。这同时证明下一控制帧的反馈可用性，不将100µs日志伪称为RTL第4999拍producer日志。

PI仍使用old-state输出和前拍AW。`PI_Reset_EN`选择当前raw输出0、下一积分0；AW没有直接PI复位线，仍按原raw-minus-limited递推。硬件global reset才同步清PI/AW及pipeline/TC；两者没有合并。

**gm只有原九路接口，没有硬件reset/CE端口。** C3的正常初始化数值oracle不能冒称测试了硬件global reset或CE。RTL定向reset试验是在两个完整帧后，将第3帧在phase100取消，再施加global reset并从已知零初态重放原前缀；取消发生在phase274之前，规则事先固定，不根据DUT错误自动改期望。该试验观察19/19个有效帧、取消1个在途帧，位/状态/XZ/协议/截止时间错误均0，并核对CE=0时reset仍优先清状态。

没有原生valid端口意味着reset期间和填充阶段的publication屏蔽是**外部checker/适配合同**。`ce_out`可以随CE保持高，不能据此宣布reset期间有有效帧。短重放证明在规定有效槽恢复正确结果；不把未观测的无效窗口描写成已证明存在RTL硬件valid掩码。

## 固定PWM预算与CE诊断

| 预算项 | 时钟数 | 状态 |
|---|---:|---|
| 原PWM应用边界 | 2500 | A实测关系冻结 |
| 输入适配开销 | 0 | 选定整帧输入保持协议，无额外输入寄存 |
| core三相输出相位 | 274 | 生成报告、完整C/D行为验证一致 |
| 输出提交寄存预算 | 1 | 预留，未声称已实现 |
| 预算提交cycle | 275 | 274+1 |
| 提交后剩余裕量 | **2225** | 2500−274−1，等于**44.5µs** |
| 最低要求裕量 | 1 | 因而允许的core最迟相位为2498 |

2225已扣除那1拍提交预算；仅作2500−274得到的2226不能作为交付裕量。完整C/D在理想20ns时基下满足该周期预算；**E的20ns STA失败，因此这不证明物理硬件能在50µs应用边界前完成**。若将来增加真实capture/adapter开销，仍须从同一2500拍边界扣除，不得移动应用边界。下游输出提交寄存器和外部valid/reset mask仍为协议预算，没有冒充为已经实现的适配器。

CE定向诊断插入21个物理停顿边沿：row0的phase100前7拍、row1的phase4999前3拍、row2的phase1前11拍。17/17个结果和状态仍一致，接受时钟输出相位仍为274；最大墙钟latency为285拍，首次物理输出283。停顿延长墙钟时间，因此它是保持/恢复诊断，不能拿来代替正常实时deadline证明，也不支持任意CE停顿仍保持50µs应用保证的说法。

## 启动、测试尾帧和负例

首帧sample0也在phase274逐位检查，没有任意舍弃开头N帧。最低位翻转负例把U相期望`1ffffffa`变成`1ffffffb`，实际xsim报告1个bit mismatch并失败；错周期负例在sample1提前一拍、phase273观察，读到上一结果，真实比较失败。它们没有修改DUT，也不是只比较两个配置数字。

C的前两次失败原样保留。Probe002显示唯一分母零点为绝对cycle85000、sample17的phase0：有限Dataset终止后，Inport的尾部行为把Vdc补0。它不在启动0…273区间。C3只给Dataset追加两个重复的**已量化末尾输入帧**，输入/期望CSV仍只有原N帧；没有改算法或放宽门槛。

C3保持source/gm/validation的`IntegerOverflowMsg=error`。四个实际除法分母在17帧每路85001点、1024帧每路5115276点、1536帧每路7675276点的日志中零计数均0，**没有启动除零豁免**。原生validation运行包含非零、限幅及PI复位的17帧并通过；完整1024/1536序列则由独立源→gm逐位路径验证，没有把原生validation写成长序列已跑。

64位PI/AW从fi直接导出16位hex，72位DivideWide的表示保留18位hex规则；不能通过double十进制中转状态/宽中间量。输入不超过40位的明确二进制解码可精确表示，随后按同一接受类型量化。M2受限例外不适用于任何M3位差或错周期。

## 最终验收边界

| 项目 | 实际结果 | 结论 |
|---|---|---|
| C，原定点→gm | 17/1024/1536帧合计18039个主stored words，0位差；另68个下一态值全等；17帧validation通过；四路分母全程无零 | **PASS** |
| D，独立xsim七组 | normal17/17、CE17/17、reset19/19且取消1帧；1024/1024边界、1536/1536真实前缀全等；两个负例真实拒绝 | **PASS**，正例位/状态/XZ/协议/行为deadline错误均0 |
| 输出→原PWM周期预算 | 理想20ns时基下phase274，预留1拍提交后2225拍/44.5µs | 行为周期预算满足；**物理deadline未证明**；下游提交寄存仍为预留 |
| E，OOC综合 | 综合完成；LUT69673/134600、FF73840/269200、DSP439/740、BRAM36等效0/365 | 容量满足 |
| E，20ns综合时序 | setup WNS **-58.833ns**，hold WNS+0.144ns；内部无时钟/未约束端点均0 | **FAIL**，M3整体接受被阻塞 |
| F，重复构建/异目录smoke | 31份RTL/TB/数据原始字节SHA256完全相同；配置与8份冻结来源一致；重复构建和异目录均实际xvlog/xelab/xsim完成 | **PASS** |
| 布线时序、RTL电机联合仿真、bitstream、硬件 | 本轮未执行 | 范围外 |

D的两个负例保留底层工具非零/FAIL：最低位翻转产生真实位差，提前一拍观察sample1读到上一结果。聚合gate PASS的意思是比较器确实拒绝了这两项错误，未把负例的FAIL改写成正常数值通过。完整长序列同样逐帧检查三相和PI/AW；边界组检查20491260项，真实前缀组检查30736892项。

F是独立新进程、新目录的实际重复生成。31份文件按原始字节SHA256比较，没有忽略路径/时间戳/token差异；配置和8份冻结来源也相同。重复构建及发布文件异目录的smoke使用普通生成TB的完成标记，计数为null，没有将这两次smoke冒称为D的计数型独立scoreboard。

OOC最差setup路径数据延迟78.788ns、154层逻辑，跨限幅器输出到SVPWM除法器输入；5000拍控制帧不允许放宽这条每时钟寄存器路径。本轮未缩位、改PI、改生成算法或使用全局false_path/5000倍multicycle隐藏失败。资源、数值、复现通过都不能抵消负WNS；外部I/O和布线时序亦未签核，当前交付是保留明确时序阻塞的开放Review，不是硬件就绪结论。
