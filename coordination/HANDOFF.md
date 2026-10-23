# ChatGPT ↔ Codex Project Handoff

**当前更新：2026-10-23。** PR44 已合并，M0 审计交付已接受；用户明确另存纯 Simulink PI-FOC 浮点基线，并使用外部 `.m` 初始化。PR45 设计现已合并，当前交接转到 M1A Codex 实施计划；旧报告中的历史暂停和“部分完成”不表示要重做 M0，也不表示 M1A 已通过。

## 当前决定

正式算法路线：纯 Simulink 浮点基线 → 独立定点控制器实现模型 → HDL Coder → RTL/Vivado/闭环验证 → 完整控制器及板级接口 → 另行批准的实机验证。

旧手写 PWM、FOC、电流环 RTL 和 StudyL1 保留为学习与验证资产，不作为正式实现必须继续扩展的底座。原 Simple、完整 MIL、ControlCore、DSP 模型均保留，不原地改写。

## 当前阶段：M1A 独立纯 Simulink 浮点基线

阅读已合并的 [M1A 设计](specs/m1a_pure_simulink_float_baseline_design.md)，以及 [Codex 实施任务](tasks/m1a_pure_simulink_float_baseline.md)、[分步执行计划](../docs/superpowers/plans/2026-10-23-m1a-pi-foc-float-baseline.md)。当前 Review 对象为**实施计划**，尚无新模型/脚本或运行结果；计划合并后由 Codex 在原本地主项目逐检查点实施，交付独立开放 PR。不因文档更新直接跨入 HDL 生成或上板。

新交付目标：`simulink模型/PMLSM_PI_FOC_Float_Baseline.slx` 与 `simulink模型/init_PMLSM_PI_FOC_Float_Baseline.m`。算法来源为 Simple 的 `Control_Task_10kHz/FOC_Algorithm`；保留必要外环、轨迹、使能/PI复位、限幅和唯一自由运动 plant。

外部 `.m` 加载 MATLAB 基础工作区；新模型不依赖旧 MAT、交互 prepare、XSI 和 Model Workspace 隐藏副本。不用仅设置 backend0 来冒充独立纯 Simulink 模型。统一物理参数、上管理想 command duty、控制周期、PWM 更新延迟和平均死区责任。

先做来源/参数/纯浮点入口及迁移对照；对齐渐降、故障恢复和行程管理放到后续 M1B 单独处理，真实测速滤波和板级采集不混入本轮。新模型不是完整实机安全控制器。

M1A 的数值与验收合同以已合并设计为准；实施拆解、脚本名称、检查命令及每步停止条件以新任务和计划为准。实施只修改新增模型及其配套文件，不重整定 PI、不改原 SLX/RTL，不完整重跑历史阶段，不生成 HDL/C/bitstream、不操作硬件。

## 已有基线与未决项归属

PR44 合并提交：`2e10c2dc576648165f541ad5b1530ef90c1e3791`。M0 证据见 [实查报告](reports/m0_simulink_model_asset_audit.md)、[差异表](../docs/MODEL_DIFFERENCE_AND_ASSET_AUDIT.md) 和 [证据索引](../docs/reports/m0_simulink_audit/README.md)。四模型已做加载/查询/参数审计；本地 Simple 与远端存在已记录差异，不能把其未提交 SLX/MAT 与 Git 版本混称同一源。

本地 Simple 独立启动、参数遮蔽和调制尺度由 M1A 用真实模型测试解决；M0 的工具加载不替代这项验收。故障恢复协议在 M1B 处理；真实 ADC/编码器/线缆映射等板级事项仍留后，不阻塞物理单位浮点基线。

接口已经给过，优先从已有材料恢复，不泛问用户重填清单。缺少的具体信息须写明已查来源和影响范围。

## 工作约定

- 实际工程核查与实现仅在 `D:/Project/FPGA_XC7A200T`，不新建 linked worktree、额外 clone 或云端实施副本。GitHub 文档分支不替代本地工程。
- 外部 `D:/Project/PMSLM_Simulation` 只读；不回写源模型。
- 保留用户 tracked/untracked 内容、未保存 MATLAB 模型、硬件资料移动、旧 worktree、PWM/FOC 工程及已有结果。
- 不使用 `reset --hard`、`clean -fd`、强制切分支、自动 stash、整体覆盖或自动清理。冲突先保留并报告。
- 版本用 Git 提交和源差异定位；不以文件哈希代替功能验收。运行证据必须来自真实 MATLAB 工具输出。
- 新副本只做必要局部布局；不全局自动布局，不以消除警告为理由静默改变行为。
- 不建设产品级测试基础设施；复用未受影响的历史证据，只补本阶段必要验证。
- 实施结束停在开放 PR，不自动合并、不自行进入 M1B/M2、不操作硬件。

## 文档与实施交接

用户合并本次设计文档后，以更新 main 非破坏性同步并准备实施；如设计未合并，不擅自合并或强制切换用户工作区。新模型与 `.m`、必要辅助文件、验证脚本和报告需一起交付，不得只有本地模型或缺依赖的远端说明。

历史全文见 [HANDOFF_LEGACY_20261021.md](HANDOFF_LEGACY_20261021.md)。[M0任务](tasks/m0_simulink_model_asset_audit.md)保留为已完成审计的历史任务，不要求因本阶段更新而重跑。
