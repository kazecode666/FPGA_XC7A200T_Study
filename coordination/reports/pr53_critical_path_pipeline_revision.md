# PR53 局部流水线续办

R1 实测原 DCP `fa572493...`，其 OOC manifest 与 B3 `cfd8b1d...` 相同。导出100条最差setup和5类各20条路径，共200条，以及20条hold、check_timing、439个DSP的寄存属性。见 `docs/reports/m3_foc_hdl/pr53_pipeline_revision/`。完整报告/DCP保留在 `.runtime/pr53_20261025/`。

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

当前仍 NOT_ACCEPTED，R2—R4待实测。原−58.833ns、274拍和首轮全部生成/失败报告保留。

## R2 已取得的候选证据

| 候选 | 修改假设 | 数值/短RTL | OOC/结论 |
|---|---|---|---|
| p1 | 限幅、反Park、XYZ、Sector、T1T2局部分配寄存级，PI子区域暂不分布 | 17帧119值+68下一态0位差，原生validation；normal/CE/global reset/1bit/真实292拍提前负例全部门禁PASS | 293拍；70216 LUT/78938 FF/439 DSP；WNS−71.348、TNS−21229.736、447失败端点，WHS+0.135；拒绝 |
| p2 | 针对p1迁移的Park/PI→sqrt路径增加预算；尝试锁定5个算法状态的分配边界 | makehdl以`hdlcoder:engine:pathbalancing`拒绝；无法吸收反馈环额外10000延迟周期 | 未生成完成SV/TB；数值、RTL、OOC明确NOT_RUN；拒绝 |
| p3 | 保留p2的Park/Clark/PI局部分段，恢复原AllowDelayDistribution继承规则 | 输出314拍；17/1024帧source→gm PASS，1536帧在执行；修订状态映射后短5组RTL PASS | 初筛WNS+5.317/TNS0/WHS+0.135；70983 LUT/83278 FF/439 DSP；最终清单OOC正在复验 |

p1最差路径从TC的phase_1，经Park输入选择/角度计算、PI，到限幅sqrt输入；数据91.166ns。说明后级链的分段并不自动解决前级，且新增快时钟路径暴露原先无板级输入约束的组合段。本轮仍不虚构I/O delay。生成SV可见反Park104位乘积后、64位加减后分别有寄存器，布局/数学位宽未改；原宽乘法/舍入/饱和仍须满足每拍20ns。

候选/配置/合同绑定的负例先失败后修复，包含真实stager拒绝候选ID、旧274拍及缺失AW映射；MATLAB验证入口拒绝同ID属性漂移。候选合同由生成的三相延迟报告冻结，非从golden扫描相位。p1的实际状态消费/提交仍由每拍checker与源下一态共同验证，未删除检查项。

## p3 状态边界资格修订

初次p3 RTL三相位差0，但沿用原post5000提交映射得到27个状态错误/31个协议错误，原始FAIL完整保留。实际SV中Id/Iq在原旁路状态之后增加了一个快时钟寄存器：`x_d/q_z_out1 <= x_d/q_z_out1_1`。因此源递推值不变，硬件观察点的提交位置是**下一帧第1拍post-edge**；本帧第5000拍pre-edge的原旧态消费检查仍保持。D端和每拍保持/CE/reset检查保留，提交比较移到结构证明的事件，对照同一源的当前行old值，不搜索平移或删掉检查项。

`p3q`仅是状态合同资格复验目录，仍是同一个p3硬件候选。其29设计SV、普通TB、4数据文件、配置、8源快照与初次p3完全相同；差异仅为冻结合同/清单。最终新清单必须独立重做所需数值/RTL/OOC门禁，不能引用初次清单的PASS充当最终验收。源和gm四个状态的实际fi日志仍以100us为周期，类型均64/40；gm实际映射为RateTransition SID 546/406/480/479，不能沿用旧B3的SID。

## R4 已取得的证据

独立进程：初次38664，父调用16396，重复子进程37928，exit0。34个原始生成文件、配置回读、8源文件SHA全等；重复普通TB和换目录普通TB smoke通过。已另做真实发布包的再次发布、SHA比较和17帧状态checker smoke，验证相对合同路径；这与运行器小fixture测试分开。工具回归包含8个Python测试、4项候选入口、5项实测PWM合同、6项运行器及真实失败子进程拒绝。

最新本地源与配置副本的21个系统逐项核对：模块位置、连线端点和折点完全相同。`source_snapshot/`交付实际8份冻结构建输入副本，便于精确复现本次身份；原路径的用户修改依旧保持未暂存，未保存任何用户模型。普通初始化/Run不增加HDL依赖。

当前完整1536帧和最终清单OOC/长RTL尚未结束，因此整体接受状态暂不更新。
