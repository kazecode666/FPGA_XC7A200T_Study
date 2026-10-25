# ChatGPT ↔ Codex Project Handoff

**当前更新：2026-10-25。PR53已Review接受并合并到 `4470e357cb91778072036475baa667c839dc12c6`。下一轮为完整三闭环HDL集成，不再先交付只含电流环的联合仿真。**

正式入口：[M4完整三闭环HDL控制核、时序适配与电机联合仿真](tasks/m4_full_three_loop_hdl_cosim.md)。这是待执行任务；本次仅更新任务/交接/路线图，没有修改SLX、生成RTL、运行MATLAB/Vivado或启动Codex。任务合并或用户明确指定执行后，在原工程连续完成A—F，最后一个开放实现PR等待Review，不自动合并或上板。

## 1. 本轮交付范围

- **一起做：** 现有位置P、速度PI、Reference_Manager、原MIL对齐及角度/电流选择、三环调度、FOC、命令快照、PWM实际许可及最小故障锁存/清除、输入保持与结果定时应用；实际生成整核SystemVerilog，接回共享plant/平均逆变器，并做完整模块级place/route。
- **继续外置：** 上位机界面、现有连续点位/S曲线参考生成、SDI/日志、plant及平均逆变器。三环和对齐实际在HDL中执行，不允许外部再跑一次位置/速度环。此版不宣称板内自主轨迹规划。
- **不展开：** 新位置积分、重新整定、运动中重规划、模式热切、未知偏置新算法、全控制器标幺化/CORDIC替换、FOC普遍缩位、死区补偿、预测控制、真实采集/测速滤波、驱动板协议、AXI/ARM软件、六路门极PWM/硬件死区、bitstream及硬件。

单FPGA当前先做确定性PL控制核；PC仍可承担界面和参考源。后续MPSoC 5EV可将轨迹、通信和任务管理放PS，三环保持PL，无需为有ARM而重写已验证内核。快速输出禁止不能依赖上位机或慢速外环；真实硬件保护还须结合驱动板，不由本轮仿真替代。

## 2. 必须复用的成果

**FOC：** PR53 p3保留原数学/位宽，原定点→gm→RTL位/状态通过；20ns核心OOC WNS+5.317ns/WHS+0.135ns，70983LUT/83278FF/439DSP/0BRAM，输出314拍。[报告](reports/pr53_critical_path_pipeline_revision.md)、[时序合同](../docs/FOC_HDL_TIMING_CONTRACT.md)、[机器记录](../docs/reports/m3_foc_hdl/acceptance_result.json)。这些只证明裸核心，未place/route；新整核须重测相位和容量，不能直接继承314拍或OOC结果。旧−58.833ns/274拍及失败候选保留为历史。

**速度PI：** 复用 [Study-L1 C](../learning/study_l1_speed_pi_hdl_compare/CHECKPOINT_C.md) 与其fixed模型/Coder carrier/向量，不从零重写或重跑整个学习实验。对照当前主线增益、积分/输出限幅、旧状态、上一excess和采样复位。旧signed25/15输出与当前FOC signed32/24接口必须显式转换和量化验证。

**位置/参考：** 以最新主线SLX为准；当前配置仅Kp_pos，不把用户口语“位置PI”变成增加积分器的授权。Reference_Manager的选择、斜率限制、限幅和保持全部纳入，不简化成一个Switch。

**对齐：** 复用PR49原MIL五态、计数、渐降和选择器，默认旁路；来源/证据见 [M1B报告](reports/m1b_repeat_moves_and_alignment.md)。允许为HDL支持做定点/显式端口/调度适配，不改算法、Start协议或真实角定义。

## 3. 关键集成合同

首版 `xc7a200tfbg484-2`、50MHz/20ns；电流100us、速度1ms、位置10ms，单时钟域内各自使能。原首tick及同拍旧/新值执行关系从最新SLX实测，不只保持平均周期。

旧p3要求九路输入整5000拍保持，314拍算完不代表可停止时钟或更新输入。外环新结果不能在裸核心正在计算时插入；优先统一Simulink生成顶层，模块组装备选必须证明相位与快照等价。新整核和全部适配在采样+50us应用边界前完成并至少留1拍余量，不增加一整拍控制延迟、不重复计算半周期更新。

拟新增 `PMLSM_ThreeLoop_FixedPoint.slx/Control_DUT` 与 `Controller_Impl_Select=0/1/2`（原参考/完整定点/完整RTL），均为待实现接口。原FOC来源通过引用/受控构建复用，不长期维护手工分叉。只允许薄SV锁存/有效/提交/禁止适配，控制数学与状态机仍从模型生成。

故障输入当前契约为已同步信号，最小锁存/实际许可在50MHz域响应，不能等待慢速外环或50us应用点。故障仍有效时不可清除；故障消失且PWM请求关闭后独立Fault_Clear才生效，之后新使能请求和有效帧/对齐条件才放行。global reset、PI_Reset、Init_Reset、fault clear、未来driver reset职责分开。真实异步引脚、硬件保护和门极输出留板级集成。

## 4. 已接受行为保持

正常三闭环，其他闭环模式停止后选择；连续点位在同一次Run到位后接受新绝对目标，Busy拒绝不排队，轨迹仍复用原算法。10mm/5s/V10/A100日常默认保持；回归的1mm/1.2s显式设置，不覆盖默认。

对齐Start=0→1→完成→0，DONE不因Start保持1自行重入。原100us和10000/30000/2000拍、0.5A不缩短，偏置计算不替换。真实角与控制角分离，未知非零偏置物理识别不是既有已证能力。

PWM关闭后仿真/机械继续，平均逆变器按原禁止输出电压语义；不声称是真实续流/制动或硬件安全关断模型。原电机、PI、外部init、1us plant、50us应用和一次1us平均死区保持。

## 5. 验证与效率

一轮连续做A来源合同→B完整定点→C整核生成/时序→D真实RTL电机闭环→E模块routed时序和有限场景→F可复现交付。自动短检查负责定位问题，不要求逐项交互批准/独立PR，不重新跑全部M0/StudyL1/Step6/7。

新外环量化误差预算先冻结；原定点→gm→RTL有效位/状态仍零差、事件一致。保留正常点位、正反连续点位、对齐完成后运动、PWM/PI复位、故障抢占/恢复的代表集。实际RTL反馈必须驱动plant再回到控制器，离线回放不能替代闭环。

M2的 `M2-E-REPEAT-001` 只覆盖原冻结连续点位场景；原FAIL数值保留。新整核外环类型/反馈改变不自动继承；任何RTL错位、状态错误或deadline失败均不能豁免。因非连续模型产生差异时按第一次分叉定位，不盲目调PI或关闭死区。

真实联合仿真和布线后STA是两项独立结果，必须绑定同一最终代码/参数。行为cosim不冒充门级SDF；模块routed通过不冒充板级IO/CDC/驱动安全验收。未测项明确NOT_RUN，不以工具fixture代替真实FOC结果。

## 6. 入口、交付和工作区保护

日常仍只手动执行 `init_PMLSM_PI_FOC_Float_Baseline.m`；必要类型自动加载，中文注释紧凑。开发入口拟为 `scripts/m4_three_loop.m`，在独立batch进程构建/测试，不加入普通init/Run。Float/Fixed不要求XSI。

交实际整核SLX、生成SV/必要数据及manifest、端口/类型/全链时序表、精简事件与误差CSV、routed报告、中文使用指南及整合报告。大MAT/DCP/波形留.runtime，避免重复提交几百万行可再生成载荷。M3历史不覆盖，旧273/5000辅助文案可顺手修正但不重跑无关项目。

- 正式工程仅 `D:/Project/FPGA_XC7A200T`；`D:/Project/PMSLM_Simulation`只读；不新建clone/worktree、不computer use、不自动stash/reset/clean。
- 保留tracked/untracked、用户未保存窗口、硬件资料移动、局部布局和旧模型。先快照，验证真实加载路径，不远端覆盖源文件。
- 测试使用本任务拥有的隔离副本，恢复cwd/path/缓存；onCleanup只关闭自有对象，不close all。
- 旧Simple/MIL/ControlCore/DSP和StudyL1只读来源。新正式源只作授权增量，主模型仅增整核分支和观测，不全局重排。
- 每检查点小步提交，故障证据保留；最后一个开放实现PR等待Review，不自动合并、不部署硬件。

历史任务见 [M3](tasks/m3_foc_systemverilog_rtl_verification.md)、[PR53修订](tasks/pr53_critical_path_pipeline_revision.md)、[M2](tasks/m2_foc_fixed_point_implementation.md)、[M1B](tasks/m1b_repeat_moves_and_alignment.md)。历史报告中“等待Review/只电流环”按当时范围理解；当前执行以本交接与M4新任务为准。
