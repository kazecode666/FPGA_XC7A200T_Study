# PR53 局部流水线续办

**当前结论：R1—R4技术门禁PASS，p3已更新当前发布包；PR53保持开放等待Review。** 20ns核心OOC通过，外部I/O、外围适配及布线后时序未签核，不进入M4。机器结果见[acceptance_result.json](../../docs/reports/m3_foc_hdl/pr53_pipeline_revision/acceptance_result.json)。

R1 实测原 DCP `fa572493...`，其 OOC manifest 与 B3 `cfd8b1d...` 相同。导出100条最差setup、5类各20条、PI反馈20条和AW数据20条，共240条/7类，以及20条hold、check_timing、439个DSP的寄存属性。见 `docs/reports/m3_foc_hdl/pr53_pipeline_revision/`。完整报告/DCP保留在 `.runtime/pr53_20261025/`。

| 路径类 | 原WNS ns | 逻辑/估算连线 ns | 级数 |
|---|---:|---:|---:|
| 限幅Divide→反Park→XYZ/扇区→T1除法输入 | -58.833 |57.113/21.675|154|
| 反Park内部DSP→T1除法输入 | -39.979 |44.742/15.191|120|
| XYZ内部DSP→T2除法输入 | -14.241 |25.501/8.695|72|
| PI d旧态→限幅sqrt | -7.122 |19.660/7.280|84|
| PI q旧态→限幅sqrt | -6.581 |19.674/6.725|84|

原配置 DistributedPipelining=off；相关InputPipeline/OutputPipeline=0。439个DSP均MREG/PREG=0，其中327个连AREG/BREG也为0。InversePark的165级sin/cos匹配链没有切分dcos/qsin乘加。单给输出延时不会切开这条路径。

最新本地定点SLX SHA `ec14e246...` 与首轮不同；逐成员检查表明模型XML差异是Position/Points，算法内部成员未变。候选复制最新本地布局；旧DCP只作原算法基线。用户文件不保存、不替换。Float参考字节相同。

候选p1假设：为限幅后半段、反Park以及XYZ/扇区局部提供寄存预算并启用对应分布式流水线；局部乘加链被重新分段，旁路由HDL Coder自动平衡。不会修改算法UnitDelay。后续候选只依据实际新路径决定，最多3个。配置on不等于网表生效，必须查实际报告。

官方方法依据：[Clock-rate FOC示例](https://www.mathworks.com/help/hdlcoder/ug/clockratepipelining.html)、[Distributed pipelining](https://www.mathworks.com/help/hdlcoder/ug/distributed-pipelining.html)。本机示例模型不在默认路径，未执行示例初始化。旧手写六扇区只借鉴寄存分段；没有替换六扇区算法、查表、位宽或输出极性。

原−58.833ns、274拍和首轮全部生成/失败报告保留；它们属于B3历史构建，当前p3使用独立冻结清单和完整复验结果。

## R2 已取得的候选证据

| 候选 | 修改假设 | 数值/短RTL | OOC/结论 |
|---|---|---|---|
| p1 | 限幅、反Park、XYZ、Sector、T1T2局部分配寄存级，PI子区域暂不分布 | 17帧119值+68下一态0位差，原生validation；normal/CE/global reset/1bit/真实292拍提前负例全部门禁PASS | 293拍；70216 LUT/78938 FF/439 DSP；WNS−71.348、TNS−21229.736、447失败端点，WHS+0.135；拒绝 |
| p2 | 针对p1迁移的Park/PI→sqrt路径增加预算；尝试锁定5个算法状态的分配边界 | makehdl以`hdlcoder:engine:pathbalancing`拒绝；无法吸收反馈环额外10000延迟周期 | 未生成完成SV/TB；数值、RTL、OOC明确NOT_RUN；拒绝 |
| p3 | 保留p2的Park/Clark/PI局部分段，恢复原AllowDelayDistribution继承规则 | 输出314拍；17/1024/1536帧18039值及68下一态0位差；完整7组RTL门禁PASS | 最终同清单OOC WNS+5.317/TNS0/WHS+0.135/THS0；70983 LUT/83278 FF/439 DSP/0BRAM；保留 |

p1最差路径从TC的phase_1，经Park输入选择/角度计算、PI，到限幅sqrt输入；数据91.166ns。说明后级链的分段并不自动解决前级，且新增快时钟路径暴露原先无板级输入约束的组合段。本轮仍不虚构I/O delay。生成SV可见反Park104位乘积后、64位加减后分别有寄存器，布局/数学位宽未改；原宽乘法/舍入/饱和仍须满足每拍20ns。

候选/配置/合同绑定的负例先失败后修复，包含真实stager拒绝候选ID、旧274拍及缺失AW映射；MATLAB验证入口拒绝同ID属性漂移。候选合同由生成的三相延迟报告冻结，非从golden扫描相位。p1的实际状态消费/提交仍由每拍checker与源下一态共同验证，未删除检查项。

## p3 状态边界资格修订

初次p3 RTL三相位差0，但沿用原post5000提交映射得到27个状态错误/31个协议错误，原始FAIL完整保留。实际SV中Id/Iq在原旁路状态之后增加了一个快时钟寄存器：`x_d/q_z_out1 <= x_d/q_z_out1_1`。因此源递推值不变，硬件观察点的提交位置是**下一帧第1拍post-edge**；本帧第5000拍pre-edge的原旧态消费检查仍保持。D端和每拍保持/CE/reset检查保留，提交比较移到结构证明的事件，对照同一源的当前行old值，不搜索平移或删掉检查项。

`p3q`仅是状态合同资格复验目录，仍是同一个p3硬件候选。其29设计SV、普通TB、4数据文件、配置、8源快照与初次p3完全相同；差异仅为冻结合同/清单。最终新清单必须独立重做所需数值/RTL/OOC门禁，不能引用初次清单的PASS充当最终验收。源和gm四个状态的实际fi日志仍以100us为周期，类型均64/40；gm实际映射为RateTransition SID 546/406/480/479，不能沿用旧B3的SID。

## R4 已取得的证据

独立进程：初次38664，父调用16396，重复子进程37928，exit0。34个原始生成文件、配置回读、8源文件SHA全等；重复普通TB和换目录普通TB smoke通过。已另做真实发布包的再次发布、SHA比较和17帧状态checker smoke，验证相对合同路径；这与运行器小fixture测试分开。工具回归包含8个Python测试、4项候选入口、5项实测PWM合同、6项运行器及真实失败子进程拒绝。

最新本地源与配置副本的21个系统逐项核对：模块位置、连线端点和折点完全相同。`source_snapshot/`交付实际8份冻结构建输入副本，便于精确复现本次身份；原路径的用户修改依旧保持未暂存，未保存任何用户模型。普通初始化/Run不增加HDL依赖。

## 最终R3结果与清单身份

最终原始构建manifest SHA256为`6078480099e3eee765e4e84c2cb27b943018393e7401c9986f1c58e8cff84953`。C、D、E均属于这份清单；独立重复构建逐项比对全部34原始SV/TB/data、配置及8源文件，不作路径/时间token排除。可搬移发布清单仅将root及合同路径改为相对路径并保留原清单SHA，原始载荷全部不变。

- C：17/1024/1536帧分别比较119/7168/10752个存储字，共18039，0位差；定向下一态68值0位差，短原生validation17帧PASS。两个长组的原生validation为NOT_RUN，已经实际完成独立逐位比较。四个分母在全部记录点均无0，IntegerOverflowMsg仍为error，没有启动豁免或任意丢帧。
- D：5个正例组共2613有效帧/52289123检查，位/状态/XZ/协议/deadline错误均0。实际1bit负例与发生变化帧的第313拍提前观察负例分别被严格运行器exit2拒绝；原生xsim可能exit0，不能替代门禁结论。CE暂停21物理边沿只是额外诊断，最大墙钟输出325拍；不重定义正常deadline。
- E：同最终清单OOC完成，WNS+5.317ns/WHS+0.135ns、TNS/THS0、setup/hold失败端点0。内部无时钟/未约束端点、latch、blackbox、组合环和latch环均0。原20ns约束、器件及位宽保持，没有false-path/multicycle放行。
- 正常314拍核心输出，加预留提交1拍后为315，距2500拍边界余2185拍；至少1拍裕量满足。共同输入捕获、frame-valid与实际输出提交适配仍未实现，外部I/O及布线后物理deadline不在本轮证明范围。

## 寄存边界前后对照

|运算链/边界|B3实际结构|p3实际结构与证据|
|---|---|---|
|限幅后→反Park→XYZ/扇区→下一除法|Divide匹配延迟后跨越长乘加/扇区组合链；154层、数据78.788ns|HDL Coder分配局部寄存预算，反Park104位乘积后及64位加减后出现快寄存，旁路自动平衡；最差已迁移为rd_11→XYZ DSP，26层、数据14.235ns（逻辑10.036+估算连线4.199）|
|Clark/Park/PI→sqrt|p1后显露TC phase_1→Park/PI→sqrt长链91.166ns|Clark3/Park12、Id/Iq各6级局部预算，生成Clark乘加/投影、PI乘积及next/state旁路的快寄存；不修改算法Unit Delay|
|PI旧态消费/提交|pre5000消费、post5000观察|pre5000消费不变；原旁路之后快rd_3使观察提交成为下一帧post1。每拍D输入和保持检查及独立源态比较证明事件；首个错误映射FAIL保留|
|AW、角度、母线和三相匹配|原AW下帧1提交，原三相274拍|AW事件保留，角度/母线/扇区匹配由生成器平衡；三相均314拍，17/1024/1536连续序列验证同帧|
|实际DSP寄存器|439个DSP的MREG/PREG均0|439个DSP中92个PREG启用，MREG仍0；不是仅把配置写on|
|资源/延迟代价|69673LUT/73840FF/439DSP/0BRAM；274拍|70983LUT/83278FF/439DSP/0BRAM；314拍，即+1310LUT/+9438FF/+40拍|

逐寄存记录见`register_boundaries_p3.csv`（162条），原边界见`register_boundaries.csv`；实际生成报告、DSP属性、路径和21系统布局/连线审计均入库。没有全局重排或移动用户模块。

## 交付、保护和未测范围

实际配置SLX在`candidates/p3/model/`，实际gm/validation在`generated_models/`；当前原始代码在`generated/m3_foc/`。冻结来源8文件在`source_snapshot/`，配置JSON/回读、候选合同和全部测试结果都入库。按[中文复验说明](../../docs/reports/m3_foc_hdl/pr53_pipeline_revision/REPRODUCE_ZH.md)把p3 candidate.json置于新run目录；裸默认入口仍刻意保留B3，不会暗中改变基线复现方式。

首轮原始B_generated_manifest.json、model/rtl/ooc/repro目录保持原字节；更新前的当前文档另存`baseline_B3_current_documents/`。p1时序FAIL、p2生成FAIL、第一次p3状态映射FAIL及首次Tcl不支持属性查询错误均保留。最多3个硬件候选，p3q不是第四个。M2例外未用于本轮。

用户原路径的未提交模型、无关修改和未保存窗口未保存/替换，未调用close all或全局初始化。独立测试只操作本任务副本，布局21系统位置/连线端点/折点完全保持。已知两处辅助文字仍沿用基线273或5000提交，已在指南和工作记录列为deferred Minor；结构化合同和实际checker使用314/313与PI提交1/消费5000，测试未放宽。

OOC为布线前核心预检；276输入/96输出缺少板级delay以及HD.CLK_SRC未设置警告保留。未运行完整place/route、RTL电机联合仿真、bitstream、硬件或M4。开放PR53等待Review，不自动合并。
