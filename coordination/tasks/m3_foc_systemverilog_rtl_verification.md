# M3 — FOC SystemVerilog 生成、时序合同与 RTL 验证任务书

> **For agentic workers:** 按本机适用的 superpowers:executing-plans 或 subagent-driven-development 逐检查点实施，`- [ ]` 只在取得真实证据后勾选。任务合并或用户明确指定执行后，连续完成 A—F；正常检查点不反复请求许可，最终提交一个开放实现 PR，等待 Review。

**Goal:** 从已接受的定点 FOC 生成可重复构建的 SystemVerilog，证明定点源→生成模型→RTL 的数值、状态及采样关系，并取得目标器件的核心级综合预检结果。

**Architecture:** `PMLSM_FOC_FixedPoint.slx/FOC_DUT` 是唯一正式定点算法源；生成工作在由最新本地源派生的隔离副本中进行。保留原共享闭环环境，M3 不接入新的电机 RTL 联合仿真后端。先用现有位宽和数值规则生成，再用明确的硬件时钟/采样相位比较模型与 RTL；综合同一份已验证 RTL，不另维护手写 FOC。

**Tech Stack:** 本机 MATLAB/Simulink、Fixed-Point Designer、HDL Coder；Vivado Simulator（xsim）及 Vivado synthesis。既有记录为 R2026b / Vivado 2026.1，开工读取实际版本/许可，不重装。正式工程 `D:/Project/FPGA_XC7A200T`。

**Spec / 依据:** 用户已确认上一轮提出的 M3 A—F 范围。本文第 1—4 节是执行合同，第 5 节是分步计划；与 [M2设计](../../docs/FOC_FIXED_POINT_DESIGN.md)、[M2报告](../reports/m2_foc_fixed_point_implementation.md)、[M2例外](../../docs/reports/m2_foc_fixed_point/common_sign_diagnostic/acceptance_exception.json)一并阅读。不再另开纯设计/纯计划的多轮前置任务。

日期：2026-10-24。远端起点为 PR51 合并提交 `aead404fce2c5a9142ffe08d96b03075603cefd5`。本文是待执行任务，不表示已生成 HDL、已运行 xsim 或已完成综合；ChatGPT 本次未执行用户本机工具。

## 1. 当前事实与授权边界

M2 已交付完整 fixed/integer/boolean FOC，根层 DUT 有 9 个数据/控制输入、3 个 duty 输出；当前 `checkhdl` 记录为 0 Error / 0 Warning / 7 Message，检查语言仍为 VHDL，尚无 HDL 文件或硬件时序结论。四处 ShiftAdd 除法/倒数有新增延迟提示，三处中文注解有下游工具提示。Work 为 64/40、DivideWide 为 72/40，是数值原型而非已证明资源最优。

PR51 以 **M2 带 `M2-E-REPEAT-001` 受限例外接受**合并，依据 [Review 5638508505](https://github.com/kazecode666/FPGA_XC7A200T_Study/pull/51#pullrequestreview-5638508505)。原连续点位三项严格 FAIL、原门槛和 `closedloop/all` 非零退出保留；不为 M3 重新追求该场景全绿。该例外不适用于定点源→生成模型→RTL 的错误，也不随位宽、算法、参数、对象或调度变化自动沿用。

**本轮实际做：** SystemVerilog DUT / testbench / 必要 ROM 数据、generated model / validation model、状态与时序映射、xsim 自检、核心 OOC 综合及资源/初步时序报告、可复现脚本和中文操作指南。

**本轮不做：** 位宽普遍缩减、PI 重整定、死区补偿、运动中重规划、模式热切、对齐改造、完整故障管理、ADC/编码器/通信/测速滤波、JMAG/Maxwell、外环定点化；不恢复旧手写 FOC/PWM 作为正式底座。完整布局布线时序、RTL 接回电机闭环、门极 PWM/板级引脚、bitstream 和硬件操作留后，不因 Workflow 默认选项顺带执行。

## 2. Global Constraints — 基线与工作区保护

- 只在原 checkout 开发；`D:/Project/PMSLM_Simulation` 只读。禁止额外 clone/worktree、自动 stash/reset/clean、强制切分支、远端 SLX 覆盖用户本地版本。保留 tracked/untracked、硬件资料移动、用户未保存窗口和局部布局，不使用 computer use。
- 开工记录本地 HEAD/status、模型/脚本差异、加载文件绝对路径和 Dirty；取最新本地源的快照，不默认等于远端。隔离构建是受控文件副本，不是另一套长期维护的工程。
- 旧 Simple/MIL/ControlCore/DSP、旧 RTL/XDC、原整定/轨迹函数、M2 浮点参考及数值配置默认只读。共享主模型的 Host/连续点位/对齐/外环/plant/逆变器和正常日志不改。
- 电流/PWM 100 us、速度 1 ms、位置 10 ms、plant 1 us、现有半周期更新/保持环节和一次 1 us 平均死区保持。用户日常默认 10 mm/5 s/V10/A100 不被测试默认覆盖。
- `Init_Start=0→1→完成→0`、PWM 禁止后机械/仿真继续、PI 复位不是清全部故障，均不重开任务。真实角与控制角继续分离。
- 唯一正常初始化入口仍为外部 `init_PMLSM_PI_FOC_Float_Baseline.m`，类型取 `pmlsm_foc_fixed_config`。日常 Run 不新增 HDL 工具依赖、不在 InitFcn 自动生成/综合。中文注释保持必要且简短。
- 新构建仅后台加载独立副本，主/引用模型实际 FileName 必须断言；缓存、输出、cwd/path 可恢复。清理只关闭本任务拥有的对象，用 onCleanup，不关闭用户窗口、不删除既有证据。
- DUT 默认不缩位、不改运算次序/舍入/饱和/系数，不把 old-state PI、前拍 AW 或 PI_Reset_EN 改成全局清零。不得为插入流水线而给算法额外加一个 100 us Unit Delay。
- 所有算法修改回到模型/生成配置；禁止编辑生成的 SV 来修正控制公式或状态。只允许少量独立测试/端口适配代码，不另写 PI/FOC 生产实现。
- 分检查点小步提交；复用未受影响的 M2/StudyL1 结果，不全量重跑 M0、Step6/7 或 60 s 闭环。来源校验和证明文件身份，不能代替功能测试。

## 3. 接口、时基与验收合同

### 3.1 固定数值边界

| 原端口 | 物理含义 | M3 要求 |
|---|---|---|
| ia/ib/ic，1—3 | 三相电流，Apeak | 同一采样帧，继承 M2 实际 signed/位宽/小数位 |
| theta_e，4；omega_e，5 | 控制角 rad、电角速度 rad/s | 不误换机械速度或真实电角度 |
| iq_ref，6；id_ref，7 | 最终选择/对齐后的参考 | 与电流/角度同拍，不接闲置测试给定 |
| PI_Reset_EN，8 | 控制采样上的有效复位请求 | 作为数据帧一部分，保持原积分/输出/AW语义 |
| Vdc_V，9 | 同拍母线电压，V | 限幅和SVPWM使用同一帧，不变成两套默认常量 |
| duty_u/v/w_cmd，输出1—3 | 死区和应用更新前的归一化上管占空比 | 同一帧一起有效，保留原类型与0/0.5/1编码；不输出旧counts |

数据端口逐项导出 HDL 名称、方向、位宽、signed、二进制小数位、初值和对应模型端口。新增 HDL clock/reset/clock-enable/输出相位信号单独列，不能冒称它们在 M2 九端口中原本存在。

### 3.2 首版硬件时钟与调度

首版目标为 **`xc7a200tfbg484-2`、单时钟 50 MHz / 20 ns、100 us 一帧 / 5000 时钟**。这是沿用仓库已有器件和 20 ns 约束的本轮目标，不是已实现 Fmax 或已确认板级时钟接线。A 核对现有资料与本地工具；若不符，记录差异，不偷偷换器件/时钟。

优先采用 Clock-Rate Pipelining，显式 `Oversampling=5000`，并确认 DUT 有效数据基准确为 100 us、硬件时钟为20 ns。采用手动倍率时不要同时启用自动 hardware-rate 推导覆盖它；配置并回读实际生效值。原源为继承采样/模型引用时，只在生成副本或最小 harness 中明确外部100 us调度；不能把 `-1` 继承值当真实周期，也不能把全部算法 delay 改成20 ns。

首轮优先保持结构可追踪，不立即大规模资源共享/flatten；工具固有多拍算子与必要流水线允许配置，数值必须符合3.4。若手动倍率不适合当前版本，用官方等价机制并记录实测5000:1关系，不能只有一个目标频率字段就声称达到该关系。

**每帧只接受一次九路快照，PI状态每个控制样本只推进一次。** 根据实际生成时序明确输入捕获相位、可改变输入的区间、内部寄存更新、输出相位、有效窗口、启动填充和帧间隔。正常工作内部时钟连续；不能把全局 `clk_enable` 未经核对当成每5000拍才脉冲一次的sample strobe，使多拍除法停住。首版允许输入整帧保持，不建设AXI/FIFO/乱序事务接口。

若工具没有独立 output-valid，允许用被验证的输出时钟使能/固定相位定义有效性；需要薄适配时只能锁存/标记/保持，不计算FOC。不得硬编码一个猜测延迟。全局CE暂停是额外诊断，不等同于正常PWM禁止；停顿造成墙钟延长须单列，不作为正常deadline证明。

### 3.3 PWM截止时间与复位

A 必须从实际现有模型导出：控制采样相位、PWM更新/保持块类型和有效采样时刻、首次事件及同一时间点执行顺序。现有50 us描述不能自动解释成“采样后总有完整50 us可用”。不在本轮修改这条链路。

以实测事件关系冻结一帧的目标应用边界、输入/输出寄存开销和至少1个硬件时钟的提交裕量。若目标边界在采样后50 us，则可用上界是2500拍减去实际开销/裕量，不能只检查小于5000拍。冻结后记录 `capture_cycle / output_valid_cycle / state_commit_cycle / apply_deadline_cycle / margin_cycles`；测得赶不上时如实FAIL，不移动应用边界或放宽控制周期。

硬件全局reset与`PI_Reset_EN`分开：本轮核心采用同一时钟域的同步高有效global reset作为初始目标，工具不支持时记录并明确替代协议；板级异步复位同步释放不在本轮。global reset恢复已定义初值及调度/流水线，复位中不得发布有效数据，复位后不能漏出旧帧。`PI_Reset_EN`只按原采样语义作用，不借它重置调度器或无条件清除AW。对插入寄存与原算法状态分别列reset/enable映射。

### 3.4 三层比较，零数值位差为首版目标

1. **已接受定点源→生成模型(gm_)：** 同一量化输入和初态，按已证明的采样/输出相位比较；三相有效输出 stored bits 必须一致，关键PI/AW状态在对应提交事件一致。不能只比较 gm_ 与 RTL 而跳过原算法。
2. **生成模型→RTL：** 有效帧逐位一致、周期映射一致；不得丢样、重复、三相不同帧，合法有效输出无X/Z。流水线启动无效区间应由真实reset/latency规则定义，不任意丢弃开头N个失败样本。
3. **实现时序→既有更新约定：** 输出及时提交、反馈状态在下一帧正确可用；M3验证事件合同，M4才在完整共享闭环中评价延迟影响。

Validation Model可补偿已经测定的纯输出延迟用于模块等价；不能补偿错误的反馈递推、任意平移比较，或把所有内部一拍都解释成同一种时间。任何 HDL 算子映射引入非零数值差，应定位到块/位/舍入；优先选择保持既定定点语义的架构。确需改变数值实现时单列候选和M2影响，不自动沿用旧例外或把舍入误差豁免为RTL正确。

测试期望值与输入用定点原始位串/hex及明确signed扩展传递，特别是64/72位状态/中间量，不能通过`double`十进制中转丢掉低位再宣称逐位一致。SV比较禁止用real容差代替位比较；零分母保护、饱和与前拍状态继续覆盖。

## 4. 文件与工具产物职责

| 路径 | 责任 |
|---|---|
| `simulink模型/PMLSM_FOC_FixedPoint.slx` | 已接受唯一算法源，优先不保存改动；必要生成适配由脚本从源派生 |
| `scripts/m3_foc_hdl.m` | 主入口：`result=m3_foc_hdl(stage,runDir)`；stage见第6节，runDir省略时建独立输出，不覆盖已有结果 |
| `scripts/m3_foc_codegen_config.m` | `cfg=m3_foc_codegen_config(root,runDir)`，集中语言/器件/频率/倍率/reset/算子/输出配置，不另设PI或类型 |
| `scripts/m3_foc_vectors.m` | 确定性场景、原始定点输入与独立期望；复用M2向量入口，不复制整套FOC参考程序 |
| `scripts/m3_run_xsim.ps1` | 从manifest编译/elaborate/run；有确定timeout、检查计数/失败状态，任何失败非零返回 |
| `scripts/m3_synth_foc_ooc.tcl` | 同份已验证RTL的OOC综合、时钟约束及资源/初步时序输出 |
| `verification/m3_foc/` | 必要自检scoreboard、协议适配、故障注入和紧凑测试配置；不含另一套控制算法 |
| `generated/m3_foc/` | 最终受审生成的RTL/TB/ROM依赖及manifest；原样从生成产物选入，不手改，禁止混入旧实验RTL |
| `docs/FOC_HDL_TIMING_CONTRACT.md` | 源→gm→RTL端口、状态、相位、latency、吞吐率、deadline和复位合同 |
| `docs/PMLSM_FOC_HDL_GUIDE_ZH.md` | 一条构建入口、正常查看方法、再生成/仿真/综合操作及阶段边界 |
| `coordination/reports/m3_foc_systemverilog_rtl_verification.md` | 实际A—F结果、失败/限制及M4交接 |
| `docs/reports/m3_foc_hdl/` | 小型JSON/CSV、精简工具日志/报告及索引；每项带源/配置/构建身份 |

允许按职责添加少量helper。临时源快照、gm_/validation模型、全量工具工程、DCP/WDB、长波形和缓存保留唯一 `.runtime/m3_<run_id>/`；manifest列相对路径和校验和。gm_/validation是可再生成的派生产物，不是第三套手工维护算法。最终RTL/必要ROM/TB和复现脚本应入库，不能只交截图。目录同名冲突不得覆盖；路径变化说明原因并同步全部入口。

生成时显式指定 `TargetLanguage='SystemVerilog'`、仿真器为本机支持的 `Xilinx Vivado Simulator`，DUT/TB语言一致；使用普通文件驱动自检TB，不默认开启DPI/C代码生成、整套IP工作流或自动bitstream。对中文注解优先关闭生成注释或在生成副本局部转换ASCII并留映射，不能删原中文学习说明。工具参数以本机help和官方文档为准，失败保留真实诊断，不能悄悄退成VHDL却继续声称SV已通过。

### Review Focus

1. 100us误当20ns、CE误接采样脉冲、PI/AW每时钟重复推进：A/C/D按帧和内部状态核对。
2. global reset与PI复位混用，旧流水线结果泄漏：C/D单拍、持续及计算中复位测试。
3. testbench只证明gm与RTL一致，遗漏原定点/反馈错误，或double抹低位：C/D两层独立位比较及故意翻转1位负例。
4. 输入混帧、三相输出相位不齐、赶不上PWM边界：A/C/D有效性/时序合同与deadline断言。
5. 生成/仿真/综合使用不同产物或旧ROM，临时模型污染正式源：A/B/E/F文件清单、绝对加载路径、独立重复构建及保护检查。

## 5. 执行计划 A—F

### A — 固定来源、调度合同与生成前负例

**使用：** M2正式源、配置、当前共享模型和旧20ns XDC（只读参考）。**产出：** source/config清单、预定timing合同及验证入口。

- [x] 前检并快照最新本地源和必要依赖，记录工具版本/路径/许可、HEAD/status/Dirty。旧Review的例外仅同步元数据，不改历史严格失败值。
- [x] 导出实际9→3接口、内部delay/初值/reset、原100us调用和PWM更新相位；基于3.2/3.3冻结时钟、5000:1、deadline及接口保持要求。时钟/器件冲突定位到已有资料，不要求用户重复填写接口。
- [x] 创建主入口与配置函数；每阶段返回`stage/status/run_dir/evidence/failures`，status为PASS/FAIL/BLOCKED/NOT_RUN。缺生成RTL、缺证据或跳过工具不得写PASS；先验证未生成时RTL/synth阶段明确拒绝。
- [x] 冻结原定点短序列和测试清单；先验证一个翻转期望输出最低位的负例确实被比较器拒绝。数值/事件合同先写后测，随机seed固定为20261024。
- [x] 单独提交来源/合同/测试入口，继续B；不会以执行M2 all的已知受限FAIL作为M3启动拦截，也不让新位差引用旧例外。

### B — 实际生成SystemVerilog及可重复产物

**使用：** A的配置与源身份。**产出：** .sv、ROM/数据依赖、gm_/validation、生成/映射报告和manifest。

- [x] 在独立会话从逐字节源副本配置单时钟、100us数据基准、50MHz目标及倍率、明确reset/clock-enable、必要clock-rate pipelining。生成前回读参数，校验路径，不保存到正式主SLX。
- [x] 先执行目标SV配置的`checkhdl`，然后实际`makehdl`，启用生成模型与validation。针对四处ShiftAdd和sqrt/LUT记录选定架构、宽度、舍入及延迟；错误不得用以前VHDL检查结果替代。
- [x] 处理必要工具适配：优先仅改配置/生成副本。每个会影响数值或状态的变化先做小向量对照；不直接修改生成SV、不缩位、不重写FOC。若必须修改正式源，单独说明并重跑受影响M2验证后提交，不混入已接受结果。
- [x] 使用实际输入刺激生成普通SystemVerilog testbench，配置20ns仿真时钟。`makehdltb`可能再次生成DUT，完成后锁定最终RTL/ROM/TB同一manifest，后续C/D/E只能使用这份一致构建。
- [x] 导出文件依赖/编译顺序、顶层模块与端口映射、配置及工具日志。禁止把未保存的偶然GUI配置作为唯一生成方法；若SV生成失败，保留失败点并继续独立可做的分析，不称整个B通过。

### C — 原定点到生成模型的数值和时序验证

**使用：** 原定点参考与B派生模型。**产出：** stored-bit比对、状态对应、实测latency和帧协议。

- [x] 运行validation及独立对照，按真实输入/输出有效事件匹配sample_id；sample_id可仅在测试中，不强加原算法新数据端口。验证0位差而非肉眼相似，记录比较数量、第一不一致的周期/信号/位。
- [x] 定位原PI积分、前拍AW到生成状态的提交事件，证明下一控制帧使用正确前态；状态被优化重编码时记录等价映射，并以独立递推/后续输出验证，不强行把不存在的RTL寄存器说成已检查。
- [x] 复位/启动：检查global reset期间无有效输出、首帧填充、计算中global reset后旧帧清除；再单独测试一采样帧PI复位、持续PI复位及解除。后者不应让旧AW语义被悄悄替换。
- [x] 正常数据帧保持、连续帧切换、三相同步输出及工具承诺的CE保持/恢复分别测试。硬件时钟持续时不得多算控制状态；不支持的脉冲/停顿行为明确写为协议禁止，不伪造握手能力。
- [x] 输出实测cycle表：首次输入、输出valid、各状态commit、帧间隔、最大latency、目标PWM边界和margin。若吞吐虽够但deadline不够，单列失败，不能把两者混成一个指标；此时仍可继续D/E取得诊断。
- [x] 位差/反馈差先定位算子或调度；纯输出延迟按合同对齐，反馈错误不可平移消除。最终未解决的非零数值差阻塞M3功能验收，不擅自接受近似算法。

### D — Vivado Simulator严格RTL自检

**使用：** B最终manifest、C的有效性/时序合同和独立参考位串。**产出：** 可运行TB、xsim日志、计数/位差/异常证据。

- [x] 通过xvlog/xelab/xsim或工具生成脚本实际编译、展开、仿真；明确编译SystemVerilog，ROM/LUT/依赖文件齐全，不能只检查编译退出码。禁止仅用本机其他仿真器替代xsim后宣称完成本项。
- [x] 复用M2向量生成器，建立紧凑覆盖组：零/极小电流、正负电流和速度前馈、角度0/2pi及两侧、六扇区边界、圆限幅内外及释放、母线12/24/60V、0.5A对齐参考、单拍/持续PI复位。所有向量在声明范围内，非物理组合单独标记。
- [x] 用不少于1024帧的确定性边界/随机连续序列，以及至少一段不少于256帧的真实FOC输入重放检查完整状态演进。实际录制从零初态保留完整所需前缀；无合法状态快照时不能只截峰值窗口。不要默认跑60s×50MHz，说明选取依据即可。
- [x] 检查生成TB和独立scoreboard：每份有效输出三相stored bits与期望相同、有效帧数量/顺序匹配、无X/Z/丢帧/重复，C的状态/复位/CE/首帧边界用定向测试补齐。计数为0或timeout不能PASS。
- [x] 给独立比较器喂一份故意翻转1 bit的期望，以及一份故意错位有效周期的期望，均应失败并非零退出；不改DUT造负例。全局reset后取消哪些在途帧事先定义，不能让记分器随实际错误自动重置期望。
- [x] 输出每测试的expected/observed帧数、首末cycle、bit_mismatch、X/Z、协议/截止时间错误与失败样本。测试级数值全部0错才通过；位宽>53的状态检查保留原始位串，不用double掩盖差异。

### E — 同份RTL的核心级OOC综合预检

**使用：** D验证过的manifest；功能失败时可作诊断综合，但不称已验证构建。**产出：** OOC综合报告和M4问题清单。

- [x] 新建独立临时non-project或可复现OOC工程，目标`xc7a200tfbg484-2`，只读manifest里的设计文件（不混TB）。时钟约束到实际HDL clock端口，20ns；生成文件校验和与D一致。
- [x] 实际`synth_design -mode out_of_context`，不运行place/route/bitstream。数据端口保持变量，不能全部接常量造成DUT被综合删除；OOC不绑定板级pin，不恢复旧PWM门极模块。
- [x] 导出层级utilization、总LUT/FF/DSP/BRAM及目标容量、timing summary、check_timing/时钟与未约束路径分类、推断latch/blackbox/关键警告。检查FOC主体仍存在，不用零资源或被裁剪结果冒充成功。
- [x] 所有寄存器路径必须有合理时钟；OOC没有外部时序合同的端口路径明确声明未签核，不虚构ADC I/O delay。不能用全局false_path或5000倍multicycle掩盖核心每时钟路径；确需工具生成例外必须逐条解释并保存。
- [x] 首轮保持M2宽度获得真实成本。允许有限、保持数值的HDL配置/流水线/共享候选，每次单独记录并重跑受影响C/D后再综合；不做无限自动扫参、不改算法位宽或PI。保留首轮失败数据。
- [x] 报告综合完成与资源/20ns估算是否满足分别列结论。负WNS、超资源或缺时钟不许总PASS；无需因预检不达标擅自进入布局布线，保留阻塞交Review。即使估算满足，也不得称最终布线时序已通过或硬件可上电。

### F — 重复构建、使用说明和交付

**使用：** A—E最终配置/产物。**产出：** 可复现生成快照、中文指南、报告与开放实现PR。

- [x] 在新进程/新输出目录，从相同受控源和外部配置重复生成。对比RTL、ROM及配置；优先关闭时间戳注释，路径/时间戳差异可显式列允许项，功能token/常量/接口差异不可随意忽略。复生成后至少跑RTL smoke，不能直接借用旧manifest的PASS。
- [x] 从复制到另一输出目录的发布文件清单运行一次编译/展开/smoke，确认没有依赖旧实验路径或未列ROM；开发`.runtime`的大MAT不能成为普通RTL编译或日常主模型Run的前提。
- [x] 发布`generated/m3_foc/`中的最终原样生成文件及必要数据，排除大缓存、工具二进制、厂商安装库和许可内容。记录模型路径/版本、参数类型配置、生成语言、目标器件/时钟、算子配置、工具版本、文件校验和和每项结果归属。
- [x] 中文指南说明：日常主模型仍一个init→Run；开发一条M3入口完成生成/验证/综合，也能逐阶段复验；从哪里看gm_/validation、有效输出、FPGA周期数和资源。不得宣称有尚未接入的RTL电机联合仿真后端。
- [x] M4交接列实际接口、reset/CE/输出相位、样本到PWM应用链及预算，不把计算延迟与原50us机械相加，也不删真实延迟。列资源热点、布局布线待办及受限例外不能扩展的范围。
- [ ] 更新README/HANDOFF/路线图和整合报告，核对原模型/脚本/用户未提交差异保护、git diff --check与新增依赖；小结果归档，不覆盖M2报告。完成一个开放实现PR后停止，不自动合并或进入M4。

## 6. 执行入口、通过标准与失败处理

拟由Codex实现的入口（本文提交时尚不存在）：

```matlab
addpath('D:/Project/FPGA_XC7A200T/scripts');
r = m3_foc_hdl('all');
% 逐阶段复验使用同一run目录；重生成应建立新目录并保留旧证据。
% stages: preflight / generate / model / rtl / synth / repro / all
```

`m3_foc_hdl(stage,runDir)`无runDir时创建新唯一目录；提供已有runDir只能消费相符来源/配置的依赖，不默默覆盖已存在证据。`all`按依赖运行，独立可执行检查继续；有FAIL/BLOCKED或关键NOT_RUN则最终非零。报告区分“功能等价”“协议与deadline”“综合完成”“资源及综合时序估算”“可复现”，不能合并成一句通过。

完整M3接受至少要求：

- [x] 已交付真实SystemVerilog和完整依赖，原模型/类型到生成产物可追溯；不是只有checkhdl或任务文档。
- [x] 原定点→gm及gm→RTL有效输出0 bit mismatch，关键状态/复位对应有证据，正例及1 bit/错周期负例有效。
- [ ] 50MHz硬件时钟、5000拍控制周期、实际首帧/输出相位/状态提交和PWM deadline清楚且满足选定合同；不靠修改控制周期达标。
- [x] xsim真正运行且帧数非零，数值、协议与异常检查通过；数据未经过有损浮点位串转换。
- [ ] 同份RTL实际OOC综合完成、资源不超过目标容量、内部关键路径20ns估算满足，未约束项解释完整；不宣称布线后已签核。
- [x] 独立再生成与发布文件依赖检查通过；旧工程和用户本地修改保持。
- [ ] 报告保留失败/未测/例外，开放实现PR等待Review；完整RTL电机闭环、实现时序签核、bitstream和实机尚未执行。

生成器/算子/许可障碍、非零位差、反馈时序改变、输出超deadline、超资源或负时序余量都保留最小复现。先定位、只做合同内等价适配；确需缩位、近似算子、改周期或应用边界，作为新设计建议报告，不静默执行。允许交付部分成果与明确阻塞，但不能用已有M2通过冒充M3完成，也不能把所有工作退回纯文档。

## 7. 工具依据（实施时以本机版本再次核对）

- [makehdltb](https://www.mathworks.com/help/hdlcoder/ref/makehdltb.html)：SystemVerilog、Vivado Simulator、DUT/TB语言及生成配置保持。普通TB优先，不默认DPI。
- [Oversampling](https://www.mathworks.com/help/hdlcoder/ref/oversamplingfactor.html)及[Clock-Rate Pipelining](https://www.mathworks.com/help/hdlcoder/ug/clock-rate-pipelining.html)：硬件时钟与算法速率的关系；倍率不等于已满足时序。
- [Generated/Validation Model](https://www.mathworks.com/help/hdlcoder/ug/generated-model-and-validation-model.html)：gm反映生成行为，生成TB参考gm；仍须单独证明原定点与gm。
- [反馈流水线](https://www.mathworks.com/help/hdlcoder/ug/resolve-simulation-mismatch-when-pipelining-with-feedback-loops-example.html)：反馈delay不能用随意输出平移补救。
- [AMD OOC synthesis](https://docs.amd.com/r/en-US/ug901-vivado-synthesis/Setting-a-Bottom-Up-Out-of-Context-Flow)：独立核心综合，不等于板级布局布线验收。

以上工具参考用于落实用户已确认的M3范围，不引入新控制需求。任务执行后生成真实报告，不把本文中的目标、初始选择或预计文件名写成已完成结果。
