# M3 实际执行结果

执行：2026-10-24 至 2026-10-25，原工程 `D:/Project/FPGA_XC7A200T`，PR52 基线 `476c5a36148ad0c54010240e4da25e37436ec600`。实现分支 `codex/m3-foc-systemverilog`。

**结论：已交付可重复生成的实际 SystemVerilog 和验证证据；M3 尚未接受。A/B/C/D/F 通过，E 的20 ns综合时序估算失败，WNS −58.833 ns。没有放宽指标、应用 M2 例外或自动进入 M4。** [机器结论](../../docs/reports/m3_foc_hdl/acceptance_result.json)区分功能、周期合同、综合完成、容量和物理时序。

## A—F 结果

| 检查点 | 实际结果 | 主要证据 |
|---|---|---|
| A 来源/合同 | PASS；34个原本地文件、31段用户dirty patch、8份快照保持 | [来源](../../docs/reports/m3_foc_hdl/source_identity.json)、[合同](../../docs/FOC_HDL_TIMING_CONTRACT.md) |
| B 真实SV生成 | PASS；29设计SV、1普通SV TB、1数据文件；gm/validation在runtime | [最终清单](../../generated/m3_foc/manifest.json)、[配置回读](../../docs/reports/m3_foc_hdl/B_config_readback.json) |
| C 原定点→gm | PASS；18039个主比较值、68个下一态值全部0 bit差；17帧原生validation通过 | [C结果](../../docs/reports/m3_foc_hdl/model/model_result.json) |
| D 实际xsim | PASS；7组正/负门禁，正例2613帧/52289123计数检查，两个真实负例被拒绝 | [D结果](../../docs/reports/m3_foc_hdl/rtl/rtl_result.json)、[原始索引](../../docs/reports/m3_foc_hdl/rtl/evidence_index.json) |
| E 原位宽OOC | **FAIL**；综合完成、容量满足，20ns setup失败；内部无时钟/未约束端点均0 | [E结果](../../docs/reports/m3_foc_hdl/ooc/ooc_result.json)、[热点与警告](../../docs/reports/m3_foc_hdl/ooc/analysis_zh.md) |
| F 重复/迁移 | PASS；31原始文件、配置、8源快照完全相同；重复包、换目录包和发布包实际smoke通过 | [F结果](../../docs/reports/m3_foc_hdl/repro/repro_result.json)、[身份比较](../../docs/reports/m3_foc_hdl/repro/repeat_identity.json) |

初始B构建与独立重复生成使用不同后台MATLAB进程/新输出、缓存和code目录。重复比较是原始文件SHA，不忽略任何功能token、常量或数据。发布包额外在 `.runtime/m3_20261024_001/published_smoke_001` 实际编译/展开/仿真，结果PASS；普通编译不依赖旧MAT或原生成路径。

## 功能与状态证据

| 同零初态、同量化输入 | 帧数 | C输出/状态比较值 | C位差 | D有效帧/计数检查 |
|---|---:|---:|---:|---:|
| directed_probe | 17 | 119 | 0 | 17 / 340183 |
| boundary_random | 1024 | 7168 | 0 | 1024 / 20491260 |
| actual_prefix | 1536 | 10752 | 0 | 1536 / 30736892 |

三相duty使用原始32位hex，四个PI/AW状态使用完整64位hex。传递与比较不经double。72位除法分母同样以fi观察；四路分母在全部记录点均非零。原定点到gm在固定274拍比较三相、在对应原生100us事件比较旧态；额外17次提交的68个source下一态与gm下一帧旧态全等。没有搜索“最合适平移”来消除差异。

原生validation仅运行17帧非零/限幅/复位定向组；两份长序列明确记录其validation为NOT_RUN，使用独立完整逐位比较。生成普通TB为64帧补充检查，`counted_scoreboard=false`，不冒充独立门禁。source→gm全等加上同相位source→RTL全等形成gm→RTL的独立位证据，另有工具普通TB检查。

边界组含原M2确定性向量、六扇区两侧、角度边界、零/极小量化电流、速度前馈、饱和/释放、母线12/24/60V、单拍及持续PI复位；不平衡组合明确标为非物理算法向量。真实输入来自已录制的九端口，保留0–0.1535s全部1536帧，首次非零参考sample1199、首次非零电流sample1200，从零初态开始，没有截峰值窗口后跳过前态。

D另有CE暂停17帧及计算中global reset重启19帧正例。CE暂停21个物理时钟，按有效时钟推进，输出/关键状态/调度恢复正确；不声称检查了每一个算子内部寄存器。reset提前声明取消第3帧phase100的在途事务，然后重放零初态，检查reset优先于CE0。配置与生成RTL为同步高有效；没有把这项测试扩展成板级异步复位签核。gm只有原九端口，硬件reset/CE是在RTL执行，不声称直接给gm驱动不存在的端口。

1bit负例将实际期望U `1ffffffa` 翻为 `1ffffffb`；错周期负例在发生真实变化的sample1提前至273拍，实测仍为前帧值，到274拍才正确。两者严格运行器实际返回2，原始FAIL保留。Vivado 2026.1原生xsim在 `$fatal` 后返回0，因此必须同时检查日志、非零计数和严格wrapper返回。D的 `bit_mismatch` 是三相位差事件数；错周期的一条事件可以含多个不同位，不冒称仅一位不同。

## 时钟、应用边界与物理限制

目标器件 `xc7a200tfbg484-2`，单时钟20ns/50MHz，显式手动倍率5000、100us控制帧。正常全局CE连续高，九输入整帧保持；不存在额外公共输入快照寄存器。硬件端口和四个状态的对应见[端口表](../../docs/reports/m3_foc_hdl/hdl_ports.csv)、[状态表](../../docs/reports/m3_foc_hdl/state_mapping.csv)。

`ce_out=clk_enable` 是快时钟CE，不是frame-valid。有效性由固定274拍和reset epoch在外部测试合同中定义；未交付AXI/FIFO或实际输出提交适配器。PI在第5000拍边沿前消费旧态、边沿后提交，AW在下一帧第1拍提交，旁路选择另列，不强行把所有延迟当同一拍。

现有模型三相PWM链的30个可用事件实测：command(t)到applied(t+50us)完全相同。冻结应用边界2500拍；核心274拍，预留1拍输出提交寄存器及至少1拍裕量，剩余2225拍。**5.48us核心时间和44.50us余量仅按理想20ns行为仿真/目标换算；因STA失败，不能证明物理硬件满足50us截止时间。** 没有把计算延迟机械加到原50us之后，也没有将边界移到100us。

首轮OOC LUT69673/134600、FF73840/269200、DSP439/740、BRAM0/365，保持Work64/40、DivideWide72/40等原类型。最差路径78.788ns、154层逻辑，从电压限幅Divide跨至SVPWM T1T2 Divide，WNS−58.833ns、WHS+0.144ns。没有用5000倍multicycle或false path掩盖每时钟路径。

外部I/O尚无delay合同，上层HD.CLK_SRC/clock skew、配置电压及布线时序未签核。没有place/route、RTL电机联合仿真、bitstream或硬件操作。后续可评审细粒度流水线候选，必须重新跑受影响C/D/F及OOC；本轮保留首轮阻塞，没有扩大成自动扫参或缩位任务。

## 兼容性、失败历史与来源保护

实际工具MATLAB R2026b 26.2.0.3386108、HDL Coder/Fixed-Point许可有效；Vivado2026.1 SW6511674，目标part可用。MathWorks集成Vivado支持列表与本机版本有差异，本轮证明的是实际独立CLI编译/xsim/OOC，没有冒称Workflow Advisor全部支持。Python3.14.6标准库、PowerShell7运行脚本；本机MATLAB无Java，最终SHA和路径桥接改用已有Python，不安装JRE、不增加正常init依赖。

生成器最终报告仍有4个warning：三处原中文学习注解（保留原文、关闭生成注释，发布30份SV均ASCII），以及多速率数据传输诊断建议。实际gm更新、原生validation、完整位验证和TB均已执行通过，没有将warning声称为0。普通TB报告另提示SimulationTool从默认ModelSim切换Vivado并触发DUT重生成，最终manifest在其后才锁定；不混用第一次makehdl文件。现存MCB CopyAngleInput回调及既定系数量化提示保留在原始日志，未修改LUT/变换算法来消除提示。[生成器消息摘录](../../docs/reports/m3_foc_hdl/B_generation_messages.txt)。

保留并修正了以下真实执行失败：A首次function-call信号不支持直接记录；B误用MATLAB-design专用TB配置；B2 timescale缺反引号（改配置重生成，未改SV）；C有限输入结束后母线变0（补量化尾帧保持，恢复严格除零error、全时域分母非零）；Windows xsim plusarg反斜杠被Tcl吞掉（路径规范化）；聚合器误要求原生xsim非零（改验真实wrapper2及位差）；最后兼容门禁发现无Java（换Python字节哈希）。原失败日志和独立目录保留。E负WNS未解决、未放宽。

源、配置、生成及工具产物清单均有SHA。[原本地定点SLX解包成员与基线完全相同](../../docs/reports/m3_foc_hdl/local_vs_base_source.json)，压缩容器字节差异仍原样保留；六份M脚本仅换行差异或相同。Float主模型的本地差异未提交。未保存原模型、未清理用户dirty/untracked、未创建额外worktree/clone、未删除文件、未改PI/默认死区/外环/Host/对齐/局部布局。

最终MATLAB MCP核对仍为原交互PID21972、无加载模型；在该会话实际调用保护门得到预期拒绝，Base变量元数据、path、cwd及模型列表不变。[交互保护证据](../../docs/reports/m3_foc_hdl/interactive_guard_result.json)。本轮只有后台独立副本，未用computer use。

## 交接

最终一次独立整分支审查提出2项Important，均在一次修订中完成RED→GREEN：自动PWM合同判定，以及 `all` 的新进程重复生成。PWM当前33/30配对和四类故障共5门禁通过；旧同PID行为39528→39528被测试拒绝，修订后的真实首次/重复生成PID为20404→42416，配置/8源/31文件相同、两次smoke通过。真实失败子进程41988退出1，父F正确拒绝。编排测试仅C/D/E为显式替身，不能冒充FOC验收；原完整C/D/E结果以同文件SHA复用。工具回归5+6、PWM5、真实进程编排1、失败子进程1，共18/18。[审查修订证据](../../docs/reports/m3_foc_hdl/review_fixes/evidence_index.json)。没有延期Minor、没有第二次审查。

操作见[中文指南](../../docs/PMLSM_FOC_HDL_GUIDE_ZH.md)，小证据见[索引](../../docs/reports/m3_foc_hdl/README.md)。执行原任务A—F，复用未变更M2历史结果；M2-E-REPEAT-001、原严格FAIL和非零退出保持，不适用于M3。

本轮开放实现PR等待Review，不自动合并。唯一M3验收阻塞为原宽度构建20ns综合时序失败；实际物理deadline、上层I/O/时钟、布局布线、完整RTL电机闭环与硬件均未签核。后续不得仅凭理想xsim和资源可容纳进入硬件阶段。

原始已修正失败小记录见[failures](../../docs/reports/m3_foc_hdl/failures/index.json)。Git以本轮限定属性保留原始SV/CSV/报告换行和厂商尾空格；手写脚本仍做完整whitespace检查。发布包另从Git blob恢复后执行smoke，确保检出不会改变已验收字节。
