# PR53 — 关键路径定位与局部流水线修订 Implementation Plan

> **For agentic workers:** 使用本机适用的 `superpowers:executing-plans` 或 `superpowers:subagent-driven-development` 按检查点执行。`- [ ]` 取得实际证据后再勾选。用户已确认本方向；在 PR53 原分支连续完成本任务，不为正常检查点反复请求许可，不另开纯计划 PR。

**Goal:** 先证明当前 FOC 长组合路径的来源，再用保持数值语义的局部快时钟流水线解决 20 ns 核心综合时序阻塞，并保留可复现的生成和位级验证。

**Architecture:** 保持六扇区 SVPWM、现有正余弦查表和定点算法。以最新本地正式源的隔离副本为对象，由脚本应用 HDL 属性与必要的局部层次配置；由 Simulink/HDL Coder 重新生成 SV，不修改生成算法代码。原宽度失败构建为只读对照，候选分别记录配置、寄存器和时序，最终只发布一套经完整复验的候选。

**Tech Stack:** 原项目 MATLAB/Simulink R2026b、HDL Coder、Vivado 2026.1/xsim；执行时核对实际版本。工程 `D:/Project/FPGA_XC7A200T`，不新建 clone/worktree。

**Spec:** [M3 原任务](m3_foc_systemverilog_rtl_verification.md)、[时序合同](../../docs/FOC_HDL_TIMING_CONTRACT.md)、[PR53 Review](https://github.com/kazecode666/FPGA_XC7A200T_Study/pull/53#pullrequestreview-5639187930)，加上用户确认的“先查寄存器与运算分段，再局部流水线；论文标幺 SVPWM/CORDIC 为后续备选”。

日期：2026-10-25。远端核对起点为 PR53 `7f859f7d27195e51d90e6f1bcfa724b040e6b2f8`，PR 仍开放。本文是续办任务，不是实施或通过记录；提交任务书不改变当前 `NOT_ACCEPTED`。原任务中“已完成A—F/等待Review”是首轮历史状态，本轮按本文续办。

## 1. 已知事实与参考的用途

- 当前 50 MHz/20 ns OOC：WNS −58.833 ns，最差数据路径 78.788 ns（逻辑57.113 ns、估算连线21.675 ns），154层、770个setup失败端点。来源：`docs/reports/m3_foc_hdl/ooc/timing_summary.rpt`。容量满足不等于时序满足，综合估算不等于布线签核。
- 最差路径从 `u_dq_voltage_limiter/u_Divide/matching_delays_reg_reg[108]` 到 `u_SVPWMG/u_T1T2_Calculate/u_Fcn1/u_Defined_Quotient/dividend_in_reg_reg[63]`。这是寄存器间长组合链，不能只归结为除法的总计算拍数。
- 当前 `generated/m3_foc/InversePark.sv` 有正余弦165级匹配延迟，但电压与正余弦的乘加段仍存在连续组合赋值。它是检查线索，不是“只加一层寄存器就一定解决”的结论；必须映射到实际DCP及模型。
- 旧手写六扇区实现见 `motor_control_ip/foc/rtl/mc_sector_svpwm.sv`、`mc_svpwm_sector_xyz.sv`、`mc_udiv_u72_u41.sv`。`coordination/reports/step6c3_codex_report.md` 记录：Sector/XYZ单独寄存后，布线WNS从−2.944 ns改善到+1.935 ns，50 MHz、固定128拍、3893 LUT/1501 FF/25 DSP。只借鉴分段与逐拍除法组织；不替换正式模型，不把独立SVPWM资源与整个FOC直接相比，也不要求重跑旧工程。
- 王安鹏《永磁直线同步电机高性能电流控制及扰动抑制策略研究》（2021）第2.3节/正文16—17页：标幺六扇区SVPWM及投影/XYZ共用中间量；第2.4.2节/正文19—20页：非流水线迭代CORDIC用于正余弦；第2.4.3节：相关量采用32位Q24。论文仍列有过调制归一化，且输出表按上管低电平占比定义。不得解读为“SVPWM必须CORDIC/全链无除法”，不得把论文精度、位宽、CPU/FPGA任务划分或输出极性直接套入本项目。论文仅作方法参考，不是本轮替换算法的授权；无需重新上传或提交整本PDF。
- MathWorks官方参考（2026-10-25核对；具体支持以本机回读/报告为准）：[FOC Clock-Rate Pipelining示例](https://www.mathworks.com/help/hdlcoder/ug/clockratepipelining.html)，模型 `hdlcoderFocCurrentFixptHdl`；[Clock-Rate Pipelining](https://www.mathworks.com/help/hdlcoder/ug/clock-rate-pipelining.html)；[Distributed Pipelining](https://www.mathworks.com/help/hdlcoder/ug/distributed-pipelining.html)。前者是让其他优化在快时钟尺度引入延迟的框架；分布式流水线移动已有寄存器，必要时由InputPipeline/OutputPipeline提供寄存级。检查优化报告中的障碍，不机械复制示例40 MHz、20 us或批量关闭全部原子属性。

## 2. Global Constraints

- 原checkout及用户最新本地源优先；记录HEAD/status、加载路径、Dirty及原始文件身份。保留未提交/未保存修改、局部布局和旧报告；禁止自动stash/reset/clean、强制pull覆盖、关闭全部模型或保存用户窗口。
- 原数学、位宽、小数位、系数、舍入和饱和规则不改；Work64/40、DivideWide72/40保留。原old-state PI、前拍AW及PI_Reset_EN语义保持；同步global reset与PI复位分开。
- 本轮仍为 `xc7a200tfbg484-2`、50 MHz/20 ns、100 us/5000拍。PWM应用边界仍为采样后50 us/2500拍，输出提交预算1拍且至少再留1拍裕量。274拍只是失败基线的输出相位，不是新候选固定指标。
- 三相输出同帧；九路输入保持约定不变。`ce_out`不可自动当frame-valid；未实现的锁存/valid接口不能用文档代替。CE暂停属于诊断，不得自动重定义正常物理deadline。
- 正常主模型、电机对象、外环、Host/连续点位、原对齐、默认死区、初始化及日志保持；不改100 us算法Unit Delay来假装20 ns硬件流水线，不在日常init/Run里增加HDL依赖。
- 不直接手改生成SV、生成模型或验证模型的算法以凑相等。所有候选属性/局部层次调整来自显式脚本，可复现到生成副本。若工具要求改变正式算法或量化规则，停在该候选并说明，不静默改参考。
- 不增加Min/Max调制、不全链标幺化、不换CORDIC、不缩位、不调PI、不换器件；不将降低时钟作为本轮默认修复。上述可列后续方案，但本轮先完成路径诊断及有限等价流水线尝试。
- 不添加全局false path、5000倍multicycle或改时钟约束掩盖路径；不虚构板级I/O delay。不执行place/route、RTL电机闭环、bitstream或硬件操作。不得照搬旧手写版的布线步骤扩大范围。
- 旧 `7f859f7` 生成清单与失败报告按原字节保留；新候选新目录、单独manifest，不覆盖首轮失败数据。M2受限例外不适用于新RTL位差、状态或时序。
- 首轮最多3个有明确路径依据的新硬件候选；每个记录单一主要假设及必要配套平衡。通过者择一完整复验；无通过者交具体剩余阻塞，不无限扫参数。

## 3. Review Focus

1. 正余弦已有大量匹配寄存器、但电压乘加仍无分段：以实际路径/寄存器映射确认，不按总寄存器数推断；R1/R2验证。
2. 新流水线导致dq电压、角度、扇区或Vdc跨帧混用：R2短组及R3连续序列检查同帧输出与状态。
3. PI/AW反馈新增一拍控制延迟、复位或CE改变：R3在原采样事件比较递推，不平移状态消除差异。
4. 测试仍硬编码旧274拍/层级名称或用了旧manifest：R2先建立配置身份/相位负例，R3按新构建冻结映射；禁止从golden搜索最佳相位。
5. 流水线时序改善但超资源、超2500拍边界或不可复现：R3同构建OOC及R4独立重复生成一起验收，不能只报WNS。

## 4. 文件职责

优先复用现有M3入口、生成器、比较器、scoreboard和运行器，不建立第二套框架。

| 文件/目录 | 本轮责任 |
|---|---|
| `scripts/m3_foc_codegen_config.m`、`scripts/m3_generate_stage.m` | 显式保存候选的模型/块属性、回读有效值并仅应用到生成副本；保留基线可重复构建方式 |
| `scripts/m3_foc_hdl.m`、`m3_validate_build.m`、`m3_repeat_process.m`、`m3_repro_stage.m`等现有入口 | 仅按候选身份传播和复验所需最小修改；新子进程重复生成仍有效 |
| `scripts/m3_report_critical_paths.tcl`（确有需要时新增） | 从原DCP读取并导出路径/单元/寄存边界，不运行布局布线；可优先在现有综合Tcl中实现同等功能 |
| `scripts/m3_model_stage.m`、`m3_build_scoreboard.py`、`m3_verify_rtl.py`、`verification/m3_foc/m3_foc_scoreboard.sv` | 读取冻结的新候选相位和映射，保留严格位/状态/负例，不改golden算法 |
| `verification/m3_foc/tool_tests/` | 对候选/相位/清单失配补最小失败优先测试，不建设通用新测试平台 |
| `docs/reports/m3_foc_hdl/pr53_pipeline_revision/` | `critical_path_map.csv`、`register_boundaries.csv`、`candidate_results.csv`、候选结果与原报告索引；大MAT/DCP仍在.runtime |
| `coordination/reports/pr53_critical_path_pipeline_revision.md` | 根因、修改理由、寄存器前后位置、结果与未测边界 |
| `docs/FOC_HDL_TIMING_CONTRACT.md`、原M3报告/指南、HANDOFF | 仅在取得对应证据后更新当前状态与操作方法，保留旧基线数值及出处 |
| `generated/m3_foc/` | 只有最终保留候选完成复验后才更新发布；基线产物仍由Git提交及旧报告追溯 |

## R1 — 关键路径与寄存器映射（先分析，再改）

**Inputs:** 原最终manifest、源快照、生成追溯报告及同构建post_synth.dcp。**Outputs:** 路径表、寄存边界表、有限候选的依据。

- [x] 记录最新本地状态，确认原DCP/源码/配置/RTL的身份一致。可复用匹配SHA的原综合结果；DCP缺失时按原配置重新综合一次，不把新候选报告当原基线。
- [x] 从该DCP导出至少20条最差setup路径（不足20条则全部），按运算链/起止寄存器去重分类。每类至少留一条详细路径，另导出hold、无时钟、内部未约束项；若20条只是同一路径的不同位，补足不同失败类代表。
- [x] `critical_path_map.csv`至少记录：rank/group、startpoint、endpoint、slack_ns、logic_ns、net_ns、逻辑层数、生成SV位置、对应模型路径/SID、证据来源。无法追溯的项标明未解析，不能编造对应块。
- [x] 逐段检查限幅Divide之后、反Park电压乘加、XYZ/扇区/时间计算、下一除法输入，以及PI/AW反馈。`register_boundaries.csv`记录位宽、数据/时钟周期、寄存器在运算前后的位置、reset/CE、匹配延迟或计算流水线性质。静态assign线索必须和综合网表交叉核对。
- [x] 回读当前 `DistributedPipelining`、InputPipeline/OutputPipeline、相关局部层次/原子属性及优化报告的obstacles；结合DSP输入/MREG/PREG提示判断哪里未流水化。仅在隔离目录查看官方示例结构/属性，禁止调用它的全局初始化覆盖主工程。
- [x] 形成每个候选的因果假设：准备在哪个实际组合链加入/分配寄存级，哪些旁路需要平衡，预计影响哪些输出/状态。提交诊断后正常继续R2；不把“查完资料”当整轮完成。

## R2 — 局部流水线候选与短测试

**Inputs:** R1定位、冻结M2定点参考及原M3向量。**Outputs:** 最多3套独立候选、短数值/RTL结果和初筛OOC。

- [x] 先给现有工具补最小负例：候选ID/配置SHA不匹配、旧274拍合同误用于新候选、旧状态映射缺失应明确失败。将候选身份、有效输出相位和状态事件写入该构建的合同文件并绑定manifest，不仅修改scoreboard常量。
- [x] 第一候选优先在R1确定的局部范围配置分布式流水线及必要InputPipeline/OutputPipeline；根据实际障碍，仅解除确实妨碍该段优化且语义可保持的层次限制。每项属性记录对象、原值、新值、理由与回读结果，不批量flatten或删除PI状态。
- [x] 重新生成SV、gm/validation及普通TB，TB完成后锁定最终manifest。核查报告中实际插入/重分配寄存器的位置、位宽、CE及匹配关系；设置为on但无实际效果不能报修复。
- [x] 先从生成报告/调度导出候选输出相位、启动填充及PI/AW映射，再用定向向量实测校验。保持5000拍控制帧；允许快输出相位改变，但纯延迟对齐不可掩盖控制递推变化。不要从golden中扫描能匹配的任意偏移。
- [x] 先运行17帧定向组及受影响扇区/限幅/母线/复位边界的source→gm和xsim比较；失败则定位并保留。可对失败候选做明确标为诊断的OOC，但不能声称它是已验证构建。
- [x] 同一候选进行20 ns OOC，记录WNS/TNS/WHS/失败端点、最差路径、LUT/FF/DSP/BRAM和输出拍数。未满足时根据新关键路径决定是否做下一候选；不能只给整个DUT加输出寄存器，也不盲目同时开启所有优化。

## R3 — 最终候选完整复验

**Inputs:** R2保留候选及其独立合同。**Outputs:** 可审查的source→gm→RTL与核心OOC结果；没有通过候选时写BLOCKED并保留诊断。

- [x] 复用原17/1024/1536帧输入与零初态，完成source→gm逐位比较、原生短validation及关键下一态核查；原始64/72位数据不得经double损失低位。状态重映射必须说明等价消费/提交事件，不能删掉检查项。
- [x] xsim执行原normal、CE暂停、计算中global reset、单帧/持续PI复位、边界/随机及真实输入前缀。global reset与PI_Reset_EN分开，无X/Z、漏帧、重复或三相跨帧；硬件未自带valid时仍按明确外部协议判断。
- [x] 重做1bit和错周期负例。错周期使用实际发生数据变化的帧及该候选实际相位，不做只比较两份配置的假负例；若原提前一拍负例因新结构无效，必须重新设计能验证事件错误的独立负例并说明，不能宣称旧负例仍通过。
- [x] 数值有效输出0位差；PI/AW递推一致；核心延迟加实际输入/输出适配开销及至少1拍裕量不超过2500拍。若状态commit位置变动，证明下一100 us控制采样仍消费正确前态。
- [x] 最终同份RTL OOC必须综合完成、容量满足、setup/hold非负、TNS/THS=0、无未解释内部无时钟/未约束端点、latch/blackbox/组合环为0。外部I/O未签核继续声明。新结果不证明布线后时序，也不因理想xsim通过而称物理deadline通过。
- [x] 新manifest、相位或算子实现发生变化时，不直接引用旧构建的PASS。未变化的历史M2死区诊断、Step6/7、StudyL1和全套机械闭环不重跑。

## R4 — 重复构建、清单与交接

- [x] 沿用M3的独立新进程重复生成、原始文件SHA比对、发布/换目录smoke与失败退出规则。候选配置和块级回读必须被重复进程真实使用，不退回默认基线。
- [x] `candidate_results.csv`每行包含candidate_id、配置/manifest SHA、修改理由、输出/状态事件、位验证状态、WNS/TNS/WHS、资源、截止时间、保留/拒绝理由。基线单列，失败数据保留，未执行明确NOT_RUN。
- [x] 报告用一张表说明关键组合链优化前后在哪些运算之间新增/移动寄存器、最差路径是否迁移、资源及延迟代价。不要只写“优化后时序通过”。
- [x] 有通过候选时才更新当前发布RTL、时序合同、机器状态、中文指南及原M3报告；旧−58.833 ns、274拍及其manifest保留为历史，不伪装成同一构建。正常主模型与外部初始化仍保持原用法。
- [x] 若有限候选仍未满足，提交具体剩余路径和可选方向：继续局部结构处理、论文标幺六扇区改写、局部CORDIC或降低核心时钟。明确各方案的数值/时基影响，本轮不默认执行。不能把论文表格直接接到当前高电平duty接口，也不能用降频却保留5000拍而改变100 us控制周期。本项条件未触发：p3已满足，未执行备选改算法/降频。
- [ ] 核对用户文件/未保存模型保护和Git差异，更新PR53后停止，等待Review；不自动合并、不另建实现PR、不进入M4。没有实际运行的项目不得写PASS。

## 执行与停止约定

Codex读取本任务及PR53最新评论后，在原工程继续；先安全整合远端新增任务文档，不强制覆盖本地工作。正常完成R1后继续R2—R4，无需逐项询问。遇到权限/文件身份冲突先保留现场；遇到候选失败保留最小复现，继续不依赖的诊断。最后一次性交付实际配置/生成代码、路径映射和验证结果，不只交说明。

本轮首要目标是证明并修复寄存器间长组合链，不是指定必须采用某种SVPWM新算法。若流水线方案满足本合同，先收敛这项阻塞；后续标幺化、位宽/资源优化再单独评审。
