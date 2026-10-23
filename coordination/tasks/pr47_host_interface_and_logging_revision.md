# PR47 — 上位机指令、中文初始化与具名观测修订计划

> **For agentic workers:** 使用 superpowers:executing-plans 或适用的本机执行流程逐检查点实施；步骤使用 `- [ ]` 记录真实结果，不把本文件提交当作实现完成。

**Goal:** 在用户已手动清理的最新浮点模型上，恢复单一、易用的 Simple_Host 指令入口，整理有中文注释的外部初始化、轨迹显示、手动 Run 和具名观测，使用户不用阅读验收脚本也能独立操作。

**Architecture:** 外部 `.m` 是物理参数、控制参数、仿真配置及默认命令的唯一初始化来源；Simple_Host 把选定命令变成有明确单位、模式与时序的控制信号；控制器、逆变器和 plant 的数值逻辑不变。模型内的简易操作面板与轨迹显示复用同一组命令和轨迹函数，SDI/logsout 与 Motor_Control_Monitor 共用真实观测源。

**Tech Stack:** MATLAB/Simulink R2026b、现有 Motor Control Blockset；优先使用 Simulink Dashboard/Scope，不另建 App Designer 上位机或通信系统。

**Spec:** 已合并的 `coordination/specs/m1a_pure_simulink_float_baseline_design.md`、`coordination/tasks/m1a_pure_simulink_float_baseline.md`，以及用户本次四项补充要求。本文件补充并在以下方面取代旧交付的操作约定：不再保留零值 FPGA 遥测占位，不再让默认上位机指令被顶层 M1A_* 时间序列旁路。

日期：2026-10-23。远端核对版本：PR47 / `4606627131b694957103cefc0e91821660ef58bd`，当时仍 OPEN。ChatGPT 本次只读了用户上传的两个脚本、截图和远端文件；没有访问最新本地 SLX，也没有运行 MATLAB。以下为 Codex 修订要求，不是已完成结果。

**注释风格补充（2026-10-23）：** 用户希望简洁。初始化脚本保持分段清楚即可，中文注释只写必要参数及注意事项，不追求每行都有解释；与本条不一致的旧详注要求以本条为准。

## 1. 已知问题与范围

用户已经手动删除模型中的部分 FPGA 残留，必须以**最新本地已保存文件**为工作起点，不得拿远端旧 SLX 覆盖或重新生成回去。

远端 PR47 指南明确：实际速度、负载、PWM 和复位来自顶层 M1A_Speed_ts / Load_ts / PWM_ts / Reset_ts，Simple_Host 对应输出已闲置，部分 Host_* 变量修改无效。用户希望的是相反的日常操作体验：外部脚本定义配置，Simple_Host 统一发出指令。之前的数学/迁移验收不代表这项使用体验已经满足。

采用模型内小型控制面板：无需单独 GUI 程序，也不能仅给现有双入口再加说明而不修正接线。参数/命令默认值只维护一份；批处理测试可以有显式回放模式，但必须经过同一 Host 输出边界。

### Global Constraints

- 仅在 `D:/Project/FPGA_XC7A200T` 原工程实施。保留 tracked/untracked、未保存 MATLAB 模型和用户布局；不得 clone/worktree、自动 stash、reset --hard、clean、强制切分支或整体覆盖。
- `D:/Project/PMSLM_Simulation` 与旧 Simple/MIL/ControlCore/DSP 模型、旧 RTL/硬件资料不改。本次允许修改的是新 `PMLSM_PI_FOC_Float_Baseline.slx`、其配套初始化/检查、相关观测和验证脚本。
- 开始前记录本地新模型与 PR47 HEAD 的差异。若用户有未保存窗口，不关闭、不覆盖、不用磁盘旧副本冒充其最新修改；只处理不冲突部分并报告。
- 不重整定默认 PI，不改 old-state/前拍 AW/复位数学，不改 SVPWM 数学或机械自由运动；保留 100 us 电流/PWM、1 ms 速度、10 ms 位置、1 us plant、一次 50 us 更新、单一平均死区的默认基线。
- 不展开 M1B 的完整故障恢复/对齐/行程设计，不做定点化、HDL/C 生成、Vivado 构建、bitstream 或硬件操作。
- 优先在仍开放的 PR47 分支修订，不为本次操作完善再创建一串设计 PR。若实际执行时 PR47 已合并，则从真实最新基线创建小范围修订 PR，保留用户本地修改。

### Review Focus

1. 用户已删的遥测/端口不会被旧构建脚本或验收脚本重新加回；检查点 A 验证。
2. 改 Host 指令实际生效，不再被顶层 timeseries 或旧 workspace 遮蔽；检查点 B/C 验证。
3. 初始化只需手动运行一个文件，不清空工作区、不重置运行中的命令；检查点 B 验证。
4. 预览与实际轨迹用同一个函数、同一输入，目标值与轨迹参考不能混称；检查点 C 验证。
5. 用户直接点 Run 就有具名记录，不能只有验收脚本临时开启日志才有；检查点 D 验证。

## 2. 文件与职责

| 文件 | 职责与用户操作 |
|---|---|
| `simulink模型/PMLSM_PI_FOC_Float_Baseline.slx` | 正式仿真模型；用户打开、设置、Run |
| `simulink模型/init_PMLSM_PI_FOC_Float_Baseline.m` | 唯一手动初始化入口；可读、分节、中文注释 |
| `simulink模型/m1a_require_float_init.m` | InitFcn 自动调用的只读参数检查；用户不手动运行；不是第二份参数初始化 |
| `simulink模型/design_PMLSM_three_loop.m` | 初始化调用的三环增益计算函数；本轮不改其整定公式 |
| `simulink模型/pmlsm_scurve_profile.m` | 现有轨迹计算函数；Host 和预览共同使用；不得另写近似轨迹供显示 |
| `simulink模型/preview_PMLSM_reference.m`（新增） | 可选轨迹预览入口，不执行电机闭环、不修改参数、不成为正常 Run 的依赖 |
| `scripts/m1a_*.m` | 开发验收，不作为用户每次点击 Run 的必经步骤 |
| `docs/PMLSM_FLOAT_BASELINE_GUIDE_ZH.md` | 重写为用户操作手册，说明每种命令、按钮、观察数据和复现步骤 |

只对必要的新辅助文件作小范围增加。不要为每个参数或按钮再生成一套 helper。保留现有四个运行所需 `.m` 的名字；函数头只需一句话说明用途，调用方式主要放在用户指南，不在每个文件重复大段说明。

## 3. 检查点 A — 保留用户清理，检查剩余依赖

- [ ] 只读记录最新本地 SLX/初始化/检查函数及原 Git 状态；将用户已有清理作为来源差异记录，与本轮后续修改分开。不得把旧 PR47 图恢复为起点。
- [ ] 检查 active 模型层级、From/Goto、mask、workspace、回调、Monitor、日志及本模型运行脚本中的 FPGA/CMP/事务残留。重点包括 `Legacy_Telemetry_Disabled`、`cmp_*_active`、`accepted_sample_id`、`active_command_id`、`active_valid`、`fault_code`、`needs_reset`、旧 XSI/backend 配置。
- [ ] 删除或确认已删的只占位监测通道与依赖，不能通过接常数 0 假装保留真实硬件数据。只处理新浮点模型使用链，不全仓库搜索替换、不删历史 RTL/报告。真实 duty/PWM 使能和实际需要的复位不因关键词相似被误删。
- [ ] 检查悬空线、失配 From/Goto、已删 SID/端口的测试引用、Monitor 向量索引和日志配置。更新相应脚本，不为迁就旧 SID 重新加回无效模块。
- [ ] 用实际加载/update 和同工况对照证明观测清理不改变控制数值；保存来源差异及结果。无需重新运行全部旧 Step6/7/StudyL1。

## 4. 检查点 B — 外部初始化清楚且只有一个权威源

- [ ] 先检查现有失败/困惑场景：改 `Host_Speed_mmps` 却没有改变实际指令、未初始化时错误、重复初始化覆盖临时命令、调电机参数触发硬编码 PI 断言。把现状与本次目标区分记录。
- [ ] 重写初始化脚本，保留原有效变量名及默认数值，常用配置放前面。按功能用简短 `%%` 标题分段；**只为关键、常改或容易混淆的参数写简短中文注释**，点明含义或单位即可。变量名已经清楚的不用注释，相关赋值可以写在同一行；不要求每个变量独占一行，也不写冗长的作用模块、派生关系说明。

建议章节：使用方法/四文件依赖；常用仿真与Host命令；轨迹规划；电机物理参数；控制/PWM/plant时基；PI与运行限幅；平均逆变器和负载工况；派生量及初始化完成标识。

**注意事项集中简写**：在相关小节用少量注释提醒相电阻≠线间电阻、Apeak≠Arms、60 mm 电气周期≠30 mm 极距、Ki 与 Ki*Ts 的区别、速度PI积分/输出限幅的区别、控制周期/plant步长/PWM更新延迟/死区的区别。其他常识性或从变量名可直接理解的内容不重复写。`Host_Enable_Schedule` 如保留，一行说明各列即可；更直观的 Host 模式仍是主要操作入口。

- [ ] 普通初始化中的 `assert(abs(Kp_ACR-8.725)...Ki_ACR-11850...)` 移至默认基线回归检查；运行检查保留物理合理性、有限值、必要字段、周期整倍数和派生一致性。保持默认增益原值，不以此授权改变默认整定。
- [ ] 初始化开始使旧完成标识失效，仅全部成功后设为当前版本；不 `clear all`/`clc`/清空用户会话。脚本失败时不能沿用旧成功标识掩盖半初始化状态。
- [ ] 给 `m1a_require_float_init(model)` 保留**一两句简短中文用途说明**，必要错误提示清楚即可；不逐行添加中文注释。它只检查初始化/参数，不负责加载或发送指令。保留 Model Workspace 遮蔽检测，并检查新公开命令/仿真时间必要条件；不声称版本标识能证明参数从未改过。
- [ ] 绑定模型 StopTime 为 `M1A_StopTime_s`，而不是另一处固定1.2。改变停止时间时不存在旧 timeseries 末尾无序、错误外推或中途丢数据；覆盖短于1s和长于1.2s的用例。默认仍为1.2s。
- [ ] 用新进程执行一次初始化、修改代表性参数/命令、update/sim、再显式恢复默认；确认来源正确且回调不暗中覆盖。测试结果与用户手动操作入口一致。

## 5. 检查点 C — Simple_Host 成为唯一命令出口

### 5.1 责任边界

外部 `.m` 定义固定/可调参数和**初始**命令值；Simple_Host 读取这些配置并产生位置/速度/电流参考、闭环开关、PWM和PI复位。它不再重复定义一套电机参数，也不是只给位置而其他命令绕过它。

默认手动模式建议公开 `Host_Position_Loop_EN`、`Host_Close_Loop_EN`、`Host_PWM_EN`、`Host_PI_Reset_EN`，沿用 `Host_Target_mm`、`Host_Speed_mmps`、`Host_Id_A`、`Host_Iq_Test_Mode`、`Host_Iq_A`。这些是**本轮拟新增/整理的输入约定**，实施前不存在的变量不能在指南中声称已可用。Simple_Host 输出沿用用户熟悉的 `Position_Loop_EN`、`Close_Loop_EN`、`PWM_EN`、`PI_Reset_EN`、`iq_test_mode`、`iq_test_ref` 等名字。

| 研究模式 | Position_Loop_EN | Close_Loop_EN | iq_test_mode | 有效参考 |
|---|---:|---:|---:|---|
| 三闭环 | 1 | 1 | 0 | 目标位置，经轨迹输出 x_ref，再由外环产生 iq_ref |
| 速度+电流 | 0 | 1 | 0 | 速度给定；位置环旁路 |
| 单独电流环 | 0 | 0 | 1 | id_ref 与 iq_test_ref；关闭外环不等于电流开环 |

运行时 PWM_EN=1、PI_Reset_EN=0；PWM_EN=0 的禁止电压和有效PI复位路径保留。PI_Reset_EN 是请求，不等同于清全部故障；逐状态记录 x_d/x_q、速度积分和AW延迟的真实复位/保持语义，不能为统一按钮把所有状态强制清零。

- [ ] 将当前外部 M1A_Speed/PWM/Reset 来源移入明确的 Host 输入/选择层，或以单一手动来源替代。不得保留 Host 输出来后被顶层另一组 From Workspace 静默旁路的结构。
- [ ] 为保留自动回归，可设置 Host 内部显式手动/回放选择，默认手动；两种来源都从同一 Host 出口发出。没有测试需求则不必强建第二套来源。输出/面板显示**实际生效**模式和参考，来源可追溯。
- [ ] 默认配置放在外部脚本，模型内以变量引用的可调参数/Constant输入绑定，不再把常改命令仅作为不易实时调节的 MATLAB Function 隐含参数。新增按钮/输入框直接绑定唯一有效值。
- [ ] 负载和母线场景归仿真环境。可以在同一操作区设置，但在模型中标为“仿真负载/母线”，不是冒充真实上位机能直接命令物理负载；只送 plant/逆变器所需边界。只保留一个有效负载来源。

### 5.2 操作面板及轨迹

- [ ] 在 Simple_Host 旁增加紧凑的“仿真上位机”区域：模式指示/设置、位置/速度/电流给定、PWM使能、PI复位以及参考曲线。优先 Dashboard 的编辑框/开关/指示灯，不引入新 App。
- [ ] 本轮默认模式、位置目标、轨迹参数在**停止仿真后**修改再Run；PWM/复位可调的Dashboard绑定需实际验证。支持暂停/继续，长仿真可说明pacing；不将普通Base变量改值当作保证在线调参的方法。
- [ ] 不默认支持无扰热切环或运动中重新规划目标。现有轨迹函数按起点及时间计算，中途直接改变 target 可能产生跳变；如果没有实现新指令锁存/轨迹重规划，就在UI和指南写明运行前设置，不声称已经是完整实机上位机。
- [ ] 旁边的轨迹图显示 `x_ref_mm`，可叠加 `x_mm`；目标位置与规划参考分别标注。显示不得只画最终目标的水平线冒充规划轨迹。可选另显示规划速度，注明与控制器实际 v_ref 的区别。
- [ ] 新增 `preview_PMLSM_reference`（无输入、读取当前已初始化Base参数，或明确返回带time/x_ref的数据结构），仅绘制整段参考，不运行电机、不重新初始化。内部复用 `pmlsm_scurve_profile`，用标量时间调用生成采样序列，不另写轨迹公式。初始化不强制弹图；手动预览或面板按钮调用。
- [ ] 对正/负目标与默认轨迹检查预览与Host实际输出在相同采样时刻一致；用三种模式验证给定来源正确。拒绝或明确处理矛盾的开关组合，不能让界面显示三闭环而实际仍采用测试iq。

## 6. 检查点 D — 具名信号、Monitor与用户操作验收

### 6.1 统一观测约定

`Motor_Control_Monitor` 保留为分组查看/Scope入口，不参与控制计算；**具名 signal logging → SDI 与 out.logsout 为默认数据记录入口**。两者接相同真实源，不各自重算一份电流参考。删除FPGA列后同步列索引/脚本，不能剩一串没解释的(1..N)。

- [ ] 直接检查保存的SLX日志配置和运行后的实际名称；不能只运行会临时重命名日志的 m1a_verify_* 来证明用户Run有名字。无回归脚本介入的新MATLAB窗口直接运行必须可见具名记录。
- [ ] 采用清楚稳定的名字/单位并提交“名称—源block/端口—含义—单位—采样/抽取—推荐组合”表。保留合理现有名字；若改名，更新引用并给旧/新对应，避免重名。
- [ ] 最少覆盖位置目标/规划参考/实际位置，速度参考/反馈，选中后的id_ref/iq_ref与id/iq反馈，ia/ib/ic，vd/vq命令与实际施加电压，三相command/applied duty，位置/速度闭环、PWM、PI请求与有效复位。默认观测不包括伪造FPGA事务状态。
- [ ] 强调 `iq_test_ref` 是测试入口；三闭环观测应看 Reference_Manager 选中的实际 `iq_ref` 对 `iq`，不是把闲置的测试给定当成速度PI输出。
- [ ] 日志名字、必要数据记录和用户Scope配置保存进模型，不依赖验收脚本。总线/向量需命名叶子或单独记录所需标量；避免同名多副本和无名Signal N。抽取采样不能漏掉PWM/PI开关事件。
- [ ] 推荐SDI分组：位置（参考/实际）、速度（参考/实际）、电流（dq参考/反馈）、执行量（电压/占空比/使能）。不自动清空用户已有SDI记录。

### 6.2 用户手册必须实际走通

重写 `docs/PMLSM_FLOAT_BASELINE_GUIDE_ZH.md`，并更新 README/HANDOFF 入口。说明正常用户只手动执行一个初始化，不需要运行整套验收；列表区分4个核心 `.m` 与可选预览、开发测试。

- [ ] 从新MATLAB窗口展示准确路径、初始化、打开模型、工具栏Run/Pause/Continue/Stop；另给 `out=sim(model)` 等效命令。说明Stop停止整次仿真，PWM_EN=0只是让仿真中的逆变器停止施加平均电压，两者不是同一开关。
- [ ] 演示三闭环目标位置、速度+电流模式、单电流模式、负载场景、PWM禁止及PI复位；明确哪些参数在.m里改后重跑脚本、哪些初始化后改Base/面板即可，哪些只能停止后改。
- [ ] 演示改变 `M1A_StopTime_s`，核对顶栏/模型配置实际生效。解释该值是仿真时间，不保证等于墙钟时间；重新初始化会恢复脚本默认命令，运行中不要执行完整初始化。
- [ ] 展示轨迹预览与仿真后的实际参考；展示SDI中具体具名信号和默认Monitor。命令行给 `getElementNames(out.logsout)`、`Simulink.sdi.view` 以及从实际已存在名称取一条曲线的示例。
- [ ] 如保留 `motor_control_monitor` 向量/To Workspace输出，说明是否在 `out` 内、各列变化和用途；推荐用户以具名日志为主，不要求手记列号。不得假定截图中端口名称就等于最终SDI叶子名。
- [ ] 提交真实截图：更新后的顶层/上位机区域、轨迹曲线、直接Run的SDI名称列表；用户操作说明不得只有batch测试命令。

## 7. 验证、提交与结束

三种模式各跑代表性工况，保持旧默认物理参数；对已受影响的命令/复位和日志做回归。相同实际输入下，观测清理与指令重接不应改变FOC/plant数值。原回归中直接修改顶层时间序列或依赖已删SID的部分只做必要适配，不能以旧脚本通过代替新Host验证，也不全量重跑历史RTL阶段。

- [ ] 记录用户本地改动保护、实际变更、有效参数、命令来源、UI测试、轨迹一致性、具名日志和数值对照；所有失败与未测项如实说明。
- [ ] 在PR47补充提交：最新用户清理后的SLX及必要修订、中文初始化与检查函数、可选预览、更新指南、简明验收报告 `coordination/reports/pr47_host_interface_revision.md` 和相关测试。不要只提交新文档而遗漏模型/脚本。
- [ ] 同步明确旧source_inventory中的历史进度，链接最终报告。提交范围不混入其他硬件资料移动、缓存或旧工程修改。
- [ ] 保持PR开放，完成后停止并交Review，不自动合并、不进入M1B/M2。

## 8. 官方行为参考（不替代本机验证）

- Dashboard / Dashboard Scope：https://www.mathworks.com/help/simulink/dashboard.html 和 https://www.mathworks.com/help/simulink/slref/dashboardscope.html 。可调控制连接参数，显示连接信号；运行前后调整和可调性需在本模型验证。
- Signal logging / Signal Properties：https://www.mathworks.com/help/simulink/gui/signallogging.html 和 https://www.mathworks.com/help/simulink/slref/signalproperties.html 。日志同时用于SDI/工作区；线名与自定义Logging Name需实际核对。
- Stop time / SDI：https://www.mathworks.com/help/simulink/gui/stoptime.html 和 https://www.mathworks.com/help/simulink/slref/simulink.sdi.view.html 。停止时间是仿真秒；SDI可从界面或命令打开。
