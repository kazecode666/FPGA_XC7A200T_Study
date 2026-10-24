# ChatGPT ↔ Codex Project Handoff

**当前更新：2026-10-24。** PR49 已合并至 `main@aa46c711e2120563fe90611805348b343a568f0a`。M1B连续点位、原MIL对齐迁移和FOC只读准备已接受。下一任务为M2独立FOC定点实现；当前仅提交任务书，没有创建定点SLX、执行M2测试或生成HDL。

## 当前执行入口

读取 [M2完整任务书](tasks/m2_foc_fixed_point_implementation.md)，再读 [FOC准备报告](../docs/FOC_FIXED_POINT_READINESS.md)和 [M1B验收](reports/m1b_repeat_moves_and_alignment.md)。任务合并或用户明确指定执行后，本机Codex可连续执行A—F，正常检查点不逐项求确认；最终交一个开放实现PR，等待Review，不自动合并或开始M3。

- **做：** 独立FOC抽取/浮点适配、零分母等数值边界处理、首版范围和定点类型、实际定点FOC、共享闭环误差验证、独立固定类型checkhdl、用户操作与整合交付。
- **保持：** Host连续点位、原对齐、外环、plant、平均逆变器、默认PI/死区/时基和具名观测。只做必要实现选择及边界转换，不复制第二套电机环境。
- **不做：** 重新整定、死区补偿、运动中重规划、热切闭环、完整故障恢复、实际采集/速度滤波、JMAG/Maxwell、HDL/C生成、Vivado或硬件。

## M2实现关系

原 `PMLSM_PI_FOC_Float_Baseline/Control_Task_10kHz/FOC_Algorithm` 保留参考。拟新增 `PMLSM_FOC_FixedPoint.slx/FOC_DUT` 位于独立根层，不再处于触发/function-call父层；在共享主模型中通过单一实现源引用接入。`FOC_Impl_Select=0`为原浮点默认，1为固定类型，停止后切换，不是运行中控制模式切换。

新实现保留前8个输入顺序并新增第9个Vdc_V端口，三相输出仍是更新/死区前command duty。本轮每次100us调用代表同拍有效样本，不增加握手/ADC/全局enable协议。PWM禁止仍在外层；PI_Reset_EN保留原输出和积分语义，不能清掉所有AW记忆，更不是HDL上电reset。

M1B已查到DutInsideTrigger、扇区浮点控制及未选中SVPWM分支0/0；新实现必须分别处理。先证明独立浮点适配与原块一致，再量化；不能同时改算法、类型、PI和plant后只看一张曲线。

范围来自已有资料、当前限制、观察及明确工程假设的分栏记录。缺少额定最大值可先完成已声明范围内的原型，不伪称覆盖所有硬件工况。位宽/舍入/缩位/数值饱和规则单一配置；内部实际fixed/integer/boolean，不能外面加转换、里面仍double。初版预算见任务书，先冻结后测，不能调PI或放宽位置死区追求PASS。

## 已接受行为，不重新开任务

连续点位在同一次Run到位后接收新绝对目标，Busy拒绝、不排队、不运动中重规划；原S曲线复用。保留用户最新10mm/5s/V10/A100默认，1mm/1.2s/V5/A50只用于显式回归。

对齐继续采用原完整MIL的Angle_Init及已有选择器，默认旁路。用户正常操作Start=0，开始时置1，完成后置0；DONE不因Start保持1而自行重入。本轮不改变此流程或复位协议，也不因先前非阻塞文字评论追加启动改造。未知非零偏置识别仍未作为已验收能力。

原三环增益、物理参数、100us电流/PWM、1ms速度、10ms位置、1us plant、一次50us更新及1us平均死区保持。PWM关闭后机械/仿真继续是正常行为，PI复位不是全故障清除。实际/控制角分开，固定实现不能把plant真实角换成估计角制造自洽。

## 文件、使用与证据

唯一人工初始化仍是 `init_PMLSM_PI_FOC_Float_Baseline.m`，必要新增 `pmlsm_foc_fixed_config(p)` 自动派生类型/量化系数，中文注释简短。InitFcn只检查，不重设用户命令。正常用户不需执行一串开发脚本。

M2交付实际定点SLX、配置函数、主模型最小适配、`m2_verify_foc_fixed_point`、类型/范围/算子表、简明指南和 `coordination/reports/m2_foc_fixed_point_implementation.md`。源参考、结构等价、固定类型数值、共享闭环、溢出和兼容性分别报告；原始大MAT/缓存留独立.runtime，历史M1A/M1B证据不覆盖。

checkhdl目标为新独立固定DUT 0 Error、警告逐条说明；这不证明HDL生成成功或时序满足。M3才确定真实硬件时钟、valid/流水线和生成模型验证；100us控制周期不是FPGA时钟。不得在闭环中删掉真实延迟凑一致或叠加第二个PWM更新/死区。

## 工作区保护

- 实际工程仅 `D:/Project/FPGA_XC7A200T`；`D:/Project/PMSLM_Simulation`只读。无额外clone/worktree、云端实现副本。
- 保留tracked/untracked、未保存MATLAB窗口、硬件资料移动、旧模型、RTL、历史结果。先记录状态与原文件快照，不自动清理或stash。
- 禁止reset --hard、clean -fd、强制切分支、整体覆盖。冲突保留现场，只暂停受影响子任务并报告。
- 旧Simple/MIL/ControlCore/DSP及其初始化、原轨迹/整定函数只读；不调用旧全局初始化覆盖新PI或清用户工作区。
- local From/Goto同层唯一匹配，跨层显式端口；局部布局，不全局自动布局，不加回伪FPGA监视。
- 版本用Git和内容差异定位，实际功能用工具输出/轨迹验证，不用文件哈希冒充功能验收。
- 每个检查点小步提交，正常完成后继续后续检查；真实语义冲突或失败留下证据，不调PI/放宽阈值掩盖。
- 不全量重跑Step6/7/StudyL1，不建设产品级基础设施，不自动合并、不操作硬件。

## 历史与后续

[M1A报告](reports/m1a_pure_simulink_float_baseline.md)、[PR47操作修订](reports/pr47_host_interface_revision.md)、[M1B报告](reports/m1b_repeat_moves_and_alignment.md)、[运行指南](../docs/PMLSM_FLOAT_BASELINE_GUIDE_ZH.md)及[M0审计](reports/m0_simulink_model_asset_audit.md)保留其验收范围。M1B只读准备不等于M2实现；本次新任务也不能写成已完成。

[路线图](../docs/SIMULINK_MAINLINE_ROADMAP.md)同步为M2实施计划。原“先完成整套运行管理再定点化”的范围不恢复，实际接口继续先查仓库，不要求用户重复提供。

[旧交接](HANDOFF_LEGACY_20261021.md)、[M0任务](tasks/m0_simulink_model_asset_audit.md)、[M1A任务](tasks/m1a_pure_simulink_float_baseline.md)、[M1B任务](tasks/m1b_repeat_moves_and_alignment.md)保留历史，不重写旧验收结论。
