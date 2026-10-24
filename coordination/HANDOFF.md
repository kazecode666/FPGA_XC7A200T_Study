# ChatGPT ↔ Codex Project Handoff

**当前更新：2026-10-24。** 按已合并 PR50，在原 checkout 交付 M2 实际定点 SLX、配置、共享闭环和兼容性证据。连续点位的电流/速度差超冻结预算，为开放实现PR的Review阻塞项；没有宣称M2全部通过。入口：[M2整合验收](reports/m2_foc_fixed_point_implementation.md)、[操作指南](../docs/PMLSM_FOC_FIXED_POINT_GUIDE_ZH.md)、[结果索引](../docs/reports/m2_foc_fixed_point/README.md)。未生成 HDL/C，未执行 Vivado，不自动合并或开始 M3。

最新用户授权的[同录制符号诊断与受限例外](../docs/reports/m2_foc_fixed_point/common_sign_diagnostic/README.md)已完成：Float自回放逐值一致，共用符号后iq/速度峰值和RMSE差下降超过99.99%，命令/Ready仍一致。技术判断支持仅该冻结场景的`M2-E-REPEAT-001`，待PR51 Review确认；原严格FAIL及正常测试出口不改。不要再盲目加宽、调PI、改死区或移动命令，也不能把临时诊断模板作为生产模型。保持/短窗限制明确记录，不保证永久到位或实机精度。

## 当前执行入口

先读 [M2整合验收](reports/m2_foc_fixed_point_implementation.md)及[设计](../docs/FOC_FIXED_POINT_DESIGN.md)，按 Review 仅补受影响验证。完整合同仍见[M2任务书](tasks/m2_foc_fixed_point_implementation.md)；开放实现 PR 等待 Review，不自动合并或开始 M3。

- **做：** 独立FOC抽取/浮点适配、零分母等数值边界处理、首版范围和定点类型、实际定点FOC、共享闭环误差验证、独立固定类型checkhdl、用户操作与整合交付。
- **保持：** Host连续点位、原对齐、外环、plant、平均逆变器、默认PI/死区/时基和具名观测。只做必要实现选择及边界转换，不复制第二套电机环境。
- **不做：** 重新整定、死区补偿、运动中重规划、热切闭环、完整故障恢复、实际采集/速度滤波、JMAG/Maxwell、HDL/C生成、Vivado或硬件。

## M2实现关系

原 FOC 完整保留在 `Control_Task_10kHz/FOC_Implementation/Float/FOC_Algorithm`（原 SID546 不变）。新增 `PMLSM_FOC_FixedPoint.slx/FOC_DUT` 位于独立根层，经 `FOC_Implementation/Fixed/FOC_Model` Normal Model Reference 唯一引用。`FOC_Impl_Select=0`为原浮点默认，1为固定类型，停止后切换，不是运行中控制模式切换。

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

[M1A报告](reports/m1a_pure_simulink_float_baseline.md)、[PR47操作修订](reports/pr47_host_interface_revision.md)、[M1B报告](reports/m1b_repeat_moves_and_alignment.md)、[运行指南](../docs/PMLSM_FLOAT_BASELINE_GUIDE_ZH.md)及[M0审计](reports/m0_simulink_model_asset_audit.md)保留历史范围。M2 的失败、受限范围和未测项以新整合验收为准，不能回写成 M1B 已验证未知非零偏置。

[路线图](../docs/SIMULINK_MAINLINE_ROADMAP.md)同步为M2实现待Review。原“先完成整套运行管理再定点化”的范围不恢复，实际接口继续先查仓库，不要求用户重复提供。

[旧交接](HANDOFF_LEGACY_20261021.md)、[M0任务](tasks/m0_simulink_model_asset_audit.md)、[M1A任务](tasks/m1a_pure_simulink_float_baseline.md)、[M1B任务](tasks/m1b_repeat_moves_and_alignment.md)保留历史，不重写旧验收结论。
