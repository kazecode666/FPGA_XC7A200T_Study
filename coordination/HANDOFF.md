# ChatGPT ↔ Codex Project Handoff

**当前更新：2026-10-24。** PR48任务已在 `codex/m1b-repeat-moves-alignment` 增量执行A—E，起点 `main@9b63e9a`。实际SLX/脚本、[整合验收](reports/m1b_repeat_moves_and_alignment.md)和[FOC只读准备](../docs/FOC_FIXED_POINT_READINESS.md)随[PR49](https://github.com/kazecode666/FPGA_XC7A200T_Study/pull/49)等待Review；不自动合并或启动M2。

## 当前执行入口

先读[实际验收](reports/m1b_repeat_moves_and_alignment.md)和[操作指南](../docs/PMLSM_FLOAT_BASELINE_GUIDE_ZH.md)，再对照 [M1B任务书](tasks/m1b_repeat_moves_and_alignment.md)。本文件和任务书合并后，或用户明确指定该任务分支后，由本机Codex连续完成A—E，不在正常检查点反复请求许可。最终交一个开放实现PR等待Review，不自动合并或开始M2。

本轮按用户最后澄清的范围，不执行此前讨论过的大范围运行管理重构：

- **做：** 同一次仿真到位后继续下发目标，先实测现状，再补最小分段S曲线；原MIL Angle_Init迁移且默认旁路；正常Run、UI、具名日志和必要回归；FOC定点/HDL只读准备。
- **不做：** 运动中重规划、热切闭环模式、完整故障锁存/驱动板恢复、死区补偿、实际采集/速度滤波、JMAG/Maxwell替换、定点实现、HDL/C生成、Vivado或硬件操作。
- 正常运动用三闭环；其他模式保留作停止后选择的调试。PWM禁止后机械/仿真继续是现有正常行为，不清零位置速度；PI复位不等同于清所有故障。

## 实施关系

以用户最新本地 `PMLSM_PI_FOC_Float_Baseline.slx` 为增量修改对象，PR47为历史对照；不要用远端旧SLX覆盖本地清理、布局或面板。

连续点位先检查现有命令是否真的收到，以及新目标是否误用旧计时。正式行为为绝对位置目标、显式提交、到位后接收、每段独立起点/计时；忙时明确拒绝，不新增运动中重规划或命令队列。详细握手、Ready和默认首段行为见任务。

对齐主来源为 `PMLSM_ControlCore_Block/PMLSM_ControlCore/Angle_Init`，来自原完整MIL；DSP对应路径只作对照。保留实际MIL已有电流渐降、偏置公式、采样和外围选择器，不写另一套算法、不新增未知偏置发生器。原文档的状态号方案与实际图可能不同，以实际源SLX和M0导出核对。

原三环增益、物理参数、100us电流/PWM、1ms速度、10ms位置、1us plant、一次50us更新及1us平均死区保持。对齐默认关闭时，原默认运行应保持；对齐启用后的首个点位不能复用过期全局时间。

## 文件与证据

外部 `init_PMLSM_PI_FOC_Float_Baseline.m` 仍为唯一人工初始化入口，Base Workspace为参数来源，中文注释保持简短。`m1a_require_float_init.m`只检查，用户不手动执行。原轨迹和整定函数复用。

Codex交付实际新浮点SLX的增量、必要脚本、更新操作指南、`coordination/reports/m1b_repeat_moves_and_alignment.md`、精简结果索引及 `docs/FOC_FIXED_POINT_READINESS.md`。这些文件已随实现提供；具体通过项、工具失败与未测范围以整合报告为准。

连续点位需一次Run中真实临时命令证据，不能以多个sim或预设阶跃代替。对齐需源/新chart逐拍对照及实际闭环，不能仅因DONE就判物理对齐成功。正常直接Run应有保存的具名日志。未自动点击UI或未能读取本地参考的项，按事实列限制。

FOC准备只导出接口、模块、参数、范围及当前版本支持情况，不生成代码、不改浮点DUT。观察到的min/max不能当作全部设计范围，不能提前套旧RTL的24bit或2500标度。

## 工作区保护

- 实际工程仅 `D:/Project/FPGA_XC7A200T`；`D:/Project/PMSLM_Simulation`只读。无额外clone/worktree、云端实现副本。
- 保留tracked/untracked、未保存MATLAB窗口、硬件资料移动、旧模型、RTL、历史结果。先记录状态与原文件快照，不自动清理或stash。
- 禁止reset --hard、clean -fd、强制切分支、整体覆盖。冲突保留现场，只暂停受影响子任务并报告。
- 旧Simple/MIL/ControlCore/DSP及其初始化只读；迁移仅复制必要内容到新主线，不能调用旧全局初始化覆盖新PI或清用户工作区。
- local From/Goto同层唯一匹配，跨层显式端口；局部布局，不全局自动布局，不加回伪FPGA监视。
- 版本用Git和内容差异定位，实际功能用工具输出/轨迹验证，不用文件哈希冒充功能验收。
- 每个检查点小步提交，正常完成后继续后续检查；真实语义冲突或失败留下证据，不调PI/放宽阈值掩盖。
- 不全量重跑Step6/7/StudyL1，不建设产品级基础设施，不自动合并、不操作硬件。

## 已有基线

[M1A报告](reports/m1a_pure_simulink_float_baseline.md)、[PR47操作修订](reports/pr47_host_interface_revision.md)、[当前运行指南](../docs/PMLSM_FLOAT_BASELINE_GUIDE_ZH.md)和[M0审计](reports/m0_simulink_model_asset_audit.md)保持历史证据作用。连续点位和本轮对齐功能不能引用这些旧结果冒充已通过。

[路线图](../docs/SIMULINK_MAINLINE_ROADMAP.md)已同步本轮范围；旧M1B“完整运行管理”不再是当前执行要求。已知接口继续从仓库与原资料查找，不要求用户重新描述。

[旧交接全文](HANDOFF_LEGACY_20261021.md)及[M0任务](tasks/m0_simulink_model_asset_audit.md)、[M1A任务](tasks/m1a_pure_simulink_float_baseline.md)保留，不重写旧验收结论。
