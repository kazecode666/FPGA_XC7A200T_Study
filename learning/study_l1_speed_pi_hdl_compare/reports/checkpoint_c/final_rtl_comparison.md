# Checkpoint C：B1 等价手写 RTL、公平比较与单项 Coder 实验

本次只完成 C1–C5。从 PR39 合并后的 main `485439986feb39f45d2b018cae765d7f056833b5`
开始，使用原始工作树，冻结全部88项 A/B 文件以及288项用户本地内容/缺失状态。

**数值结果：三版全部 bit-exact。时序结果：Coder baseline 和 AW CSD 通过本次50 MHz OOC预算，
手写版 setup 未通过（WNS=-1.957 ns）。这是测得的比较结果，不能把手写版标为50 MHz timing PASS。**

## C1 / C2：相同算法、边界和诊断

唯一 numerical golden 是实际冻结的 [B1 SLX](../../models/speed_pi_fixed.slx)，不是重新写的
Python/MATLAB PI 公式。原始模型、B1、B2、B carrier 和 baseline 生成文件均未修改。
[完整 contract](rtl_contract.md) 固定单位、类型、系数 raw、逐级转换和事件语义。

手写实现：[speed_pi_sv.sv](../../handwritten/speed_pi_sv.sv)。它直接表达 B1 的图：
`error → P/inc`，`old_excess → AW`，`P+old_x → 内部限幅 → excess`，
`old_x+inc-AW → 积分限幅 → int_reset`。它没有提前用新积分值计算输出。
内部 ±1 A 限幅结果参与 excess，而外部25/15输出量化不参与AW反馈。

手写使用精确65/50、72/60乘积和 ties-to-even 函数；44位加法、45位减法及逐级饱和都明确。
Signum只有-1/0/+1，用34位精确选择/取负，再饱和到33位，与B1 int32×error的结果等价。
最小负输入的 Abs 饱和、严格0.5/-3比较、hard 与 int_reset 的区别均保留。
hard reset 清当前iq和下一积分，**不清除下一excess**；无事件时reset/disable命令保持待采样。

共用 [薄适配器](../../handwritten/speed_pi_compare.sv) 只生成 CE/valid，不含数值运算。
两版都保留1个输入寄存阶段和1个事件输出保持阶段，所有7项逻辑输入和**全部14项诊断输出**一致，
计数包含相同适配器。`ce_out`是global CE，不能当作result_valid。

Latency 为2个边界阶段（Coder native report也为2）：posedge后launch在k+1接受、k+2提交；
accept-to-output=1 clock。Fresh TB在negedge驱动，drive-to-output=30 ns，#1观察为31 ns。
这是驱动边沿定义不同，三版均按同一个已知valid序列检查，未任意平移波形。
正常源first tick=0.9 ms、period=1 ms（50000 clocks），KiTs不随压力测试加速而改变。

## C3：实际 B1 → 三版 XSim

[Oracle exporter](../../scripts/study_l1_c_golden.m) 在独立 MATLAB R2026b GA batch 中读取实际B1，
使用隔离Cache/CodeGen目录，不保存B1。普通2580行与Checkpoint B向量逐行一致。
新增5262行包含31×31边界组合、seed739的1600组全signed32随机输入、严格阈值邻点、
可达的P/inc/AW/输出舍入半值，以及reset/disable/angle/test事件。
所有21列中的14项期望输出都来自B1的`yout`，输入由实际fi量化。

| Fresh regression | 结果（每版） |
|---|---:|
| 总逻辑向量行 | 7842 |
| 有效上升沿事件 | 2886（normal258 + stress2628） |
| 每个有效事件比较字段 | 14 |
| raw mismatches | **0** |
| 最小2-clock间隔连续事件对 | 2626 |
| 空闲物理clock上的输出保持检查 | 12902403 |
| transaction在途global CE暂停 | 1次，保持5 clocks后准确提交一次 |
| sustained-high检查 | 1292376 clocks；没有重复更新 |
| 三版完整逐事件trace | **相同（含row/clock/time和全部14项raw）** |

[同一scoreboard](../../scripts/study_l1_c_tb.sv) 在每个clock检查已知valid和全部输出，
有效事件时检查B1期望值。相邻事件的old_x/old_excess等于上一事件的next状态；
空闲输出保持，并在下一事件继续验证状态。初始化reset在CE=0时清输出/valid，恢复后重新预热低tick。
normal按5000 clocks/行运行；stress按1 clock/行高低交替，验证无busy/FSM造成丢事件。

[Coverage ledger](coverage.json) 确认正负线性、零误差、双向饱和、AW、解除饱和、饱和反向、
reset、disable/re-enable、overspeed均有实际样本。四种有损转换的半值计数：
P=4、KiTs=4、AW=14、output=8，分别覆盖正负和保留位奇偶两种方向。
最小/最大signed32输入各出现61个有效事件。
这些是回归范围和逐级等价推导，未宣称穷举所有输入历史的形式化证明。
Coefficient量化警告是B1冻结的预期量化；极小负输入触发Abs存储饱和警告也已保留，未改算法消警告。

## C4：公平 Vivado 比较

四个现有XPR实际Part均为 `xc7a200tfbg484-2`，安装part database通过。
Vivado2026.1，单一20 ns clock，所有输入/输出各2 ns预算，BUFGCTRL_X0Y0 clock-source假设。
同一个 [Tcl flow](../../scripts/study_l1_c_vivado.tcl)：相同top、默认synth、opt/place/route；
无false/multicycle path，无删诊断、缩位宽或隐藏I/O约束。手写分支仅选择HAND_SV编译宏。

| Metric | Coder baseline C | Hand SV D |
|---|---:|---:|
| LUT（post-route） | 685 | 705 |
| Slice FF（post-route） | 555 | 555 |
| DSP48E1 | 10 | 10 |
| BRAM18 / BRAM36 | 0 / 0 | 0 / 0 |
| Latency（boundary stages） | 2 | 2 |
| 正常update interval | 1 ms / 50000 clocks | 1 ms / 50000 clocks（逻辑契约） |
| 最小事件间隔（RTL模拟） | 2 clocks | 2 clocks |
| WNS @50 MHz | **+0.331 ns** | **-1.957 ns** |
| WHS | +0.166 ns | +0.034 ns |
| Setup / hold timing | PASS / PASS | **FAIL** / PASS |
| RTL物理LOC（含注释/空行，不含共用adapter） | 718（2 files） | 152（1 file） |
| 共用adapter LOC | 45 | 45 |
| 最差data path delay / levels | 19.409 ns / 35 | 21.632 ns / 52 |
| 主要关键路径 | input ref寄存器 → previous-excess映射DSP D端 | input ref寄存器 → d状态D端 |

关键路径和完整约束报告：[Coder](verification/baseline/critical_paths.rpt)、
[Hand](verification/hand/critical_paths.rpt)。手写最差路径经过error/P乘法、round/cast、
unlimited、输出限幅、excess路径，52级中有40个CARRY4；Coder对应35级中有26个CARRY4。
这说明当前表达式和综合映射产生了不同的组合深度；没有增加内部pipeline来改变本次基线比较。
手写的2-clock功能模拟不等于物理电路能在50 MHz正确运行，后续若要使用必须先关闭setup violation。

三版clock、internal endpoints、input/output delay、loops/latch-loops缺项均0，routing errors=0。
DRC报告另保留CFGBVS/CONFIG_VOLTAGE缺省告警（本次是OOC IP），以及DSP的DPIP/DPOP内部
pipeline建议；baseline/hand各10个DSP，CSD为6个。没有为消除这些建议增加未授权的优化配置。
OOC端口未指定HD.PARTPIN_LOCS的告警已保留：内部关键路径是routed，外部package/board端口路由
不在签核范围。不是上板结果，也不是完整电机联合仿真结果。

Checkpoint B裸HDLCore的683 LUT/472 FF/+0.324 ns不直接用于这张表。
这里将其原生RTL放进共同adapter后重新综合和布线，得到685/555/+0.331；
top/hierarchy与额外valid扇出会影响综合/物理优化，不能只给旧结果机械加几个valid FF。
具体79/83个FF变化的逐单元成因尚未做受控网表归因，不能解释为算法新增状态。

## C5：仅AW Gain的ConstMultiplierOptimization

只改变一个block的一个选项：`HDLCore/PI/AW: none → csd`。
P/KiTs仍为none；全部global HDL配置、InputPipeline=1、OutputPipeline=1未变。
数值block参数/连线fingerprint与冻结B1相同。生成RTL完全未经人工编辑；
去掉注释后，HDLCore完全相同，PI仅AW_mul_temp一条赋值变化，见
[functional diff](codegen/single_option_rtl.diff) 和 [native manifest](../../generated_hdl/aw_csd/MANIFEST.md)。

Kaw raw 85899346被写成常数移位加减（8 adders）：
`2^26 + 2^24 + 2^21 - 2^16 - 2^14 - 2^11 + 2^6 + 2^4 + 2^1`。
转换点仍是原来的72/60 → 40/30，不提前舍入移位项。

| Metric | Coder baseline | AW CSD（唯一实验） | 差值 |
|---|---:|---:|---:|
| 全14项raw bit-true | PASS | PASS | 0 mismatches |
| LUT | 685 | 1049 | +364 |
| Slice FF | 555 | 476 | -79 |
| DSP48E1 | 10 | 6 | -4 |
| BRAM18 / BRAM36 | 0 / 0 | 0 / 0 | 0 |
| Latency | 2 | 2 | 0 |
| WNS | +0.331 ns | +0.862 ns | +0.531 ns |
| WHS | +0.166 ns | +0.140 ns | -0.026 ns |
| RTL LOC | 718 | 719 | +1注释行 |

CSD关键路径移到input-ref → iq输出保持寄存器，18.885 ns、37级。
这次单项设置可明确归因于“AW multiplier mapping变化及其引发的重新综合/布局布线”。
DSP减少和LUT增加符合移位加法映射；FF减少及WNS增量不能逐项归结为某一adder的局部收益，
因为其他配置相同但整个网表优化和route重新执行。没有试第二个优化选项。

## 可读性、优势、不足与归因

- 自动生成的优势：保留原模型block/SID traceability、完整fixed cast和CE/reset结构；
  本次baseline在较少LUT下通过50 MHz，单项AW配置即可生成另一个bit-true映射。
- 自动生成的不足：718行生成代码、冗长cast/临时信号和hold寄存器，需要先理解模型和latency；
  不能把ce_out误作valid，也不能直接使用默认EDA sample template替代真实part/完整约束。
- 手写的优势：152行将运算顺序、舍入函数和状态更新集中表达，方便解释和局部审阅；
  thin adapter与数学核分开，接口含全部诊断而非只验证iq_ref。
- 手写的不足：位宽、signed语义、半值舍入和old-state优先级都需要作者负责；
  此版本LUT略多、DSP/FF未减少，且50 MHz setup失败，当前不能作为已收敛实现使用。
- 架构差异：显式数据边界和事件周期相同；Signum选择表达式、round/sat临时宽度及源码组织不同。
  CSD实验改变AW乘法结构；没有改变数值、valid或更新周期。
- 工具差异：Vivado将这些表达式映射到不同carry/DSP/寄存器组合并重新布线；HDL Coder能按模型
  自动生成类型转换、trace和CSD表达。资源数据来自实际报告，不从RTL LOC推算面积。
- 暂不能归因：LUT逐单元增减、旧B裸核与共同adapter的FF变化、各版本局部route收益，
  尚未逐cell控制变量拆解；不推广为“自动永远更快”或“手写必定更小”。

## Fresh verification与停止点

Fresh B1再次导出向量，三版重新编译/elaborate/XSim；全部trace相同。
当前源码的真实synthesis + placement + routing和coverage gates完成；baseline重复fresh运行得到相同资源/WNS。
报告与源码/native RTL字节哈希见 [summary](summary.json)，复现步骤见 [CHECKPOINT_C](../../CHECKPOINT_C.md)。
初始化路径、semantic reset、闲置CE和continuous tick都有证据。实现脚本将**timing failure作为测量结果保留**，
不会用“工具进程成功”冒充时序通过。

**STOP：提交本Checkpoint C PR，等待ChatGPT Review。没有Checkpoint D、完整电机联合仿真、bitstream或硬件操作。**
