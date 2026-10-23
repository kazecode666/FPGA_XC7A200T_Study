# M1A — 纯 Simulink PI-FOC 浮点基线：Codex 实施任务

**状态：待实施计划 Review。** PR44（M0 审计）和 PR45（M1A 设计）已合并。当前只交付执行计划，不表示新模型已建立或通过仿真。

**批准设计：** [M1A 设计](../specs/m1a_pure_simulink_float_baseline_design.md)  
**逐项执行计划：** [M1A Implementation Plan](../../docs/superpowers/plans/2026-10-23-m1a-pi-foc-float-baseline.md)  
**起点：** `main@20003acb3e33c54bdc078fe051a8e6650b8fcaed`（PR45 合并点；执行时记录实际 main 与本地状态）。

## 目标

从 M0 核查过的本地 `PMLSM_ThreeLoop_Simple.slx` 另存一套**纯 Simulink 浮点三闭环 PI-FOC 基线**，参数由外部 `.m` 明确写入 Base Workspace，统一电机对象、物理参数、原 SVPWM→占空比定义、PWM 更新/平均死区和电流/速度/位置采样周期。新模型可在新 MATLAB R2026b 进程独立初始化和运行，不再依赖旧 FPGA 联合仿真或本地 MAT。

## Codex 必须按顺序完成

1. **来源保护与复制：** 检查本地 Simple 未提交版本、初始化回调、旧 MAT/time series 与 M0 实查证据；保留原件并另存新 SLX。只改新模型，保留已经修正过的 dq PI、速度/位置环、自由运动 plant、必要使能/复位和限幅。
2. **外部 `.m`：** 新脚本显式加载 Base Workspace，禁止 model/mask workspace 同名遮蔽及旧回调暗中重新加载；无 `clear/clc`；默认值和工况能从文本找到，未初始化须明确报错。
3. **调制与时基：** 原 SVPWM 算法输出改为死区/应用更新前的上管 normalized duty；数值检查零矢量、六扇区、极性、电压重构及旧 counts 对照。统一 10 kHz PWM/电流环、1 ms 速度环、10 ms 位置环、1 us plant、50 us 一次更新延迟、1 us 一次平均死区。
4. **有限场景回归：** fresh MATLAB 两次启动、变量生效/遮蔽、正负电流/速度/位置、理想/死区、负载阶跃、停机/PI 复位、一个 1 us vs 0.5 us 步长对照。记录关键状态及每路 max-abs/RMSE，与源 `backend0` 在同条件下对照。容差先定后测，不通过放宽阈值追求 PASS。
5. **交付：** 新 SLX、新初始化脚本、少量 MATLAB 验证脚本、用户运行指南、`coordination/reports/m1a_pure_simulink_float_baseline.md`、精简结果索引，提交开放 PR 后停止。

详细文件名、检查命令、各阶段接口和失败处理，以链接的 Implementation Plan 为准。

## 范围和保护

- **允许：** 新模型中清理旧 XSI/手写 RTL backend 支路，整理外部脚本、归一化调制接口、共享 plant/时基，针对受影响项验证。
- **禁止：** 修改旧 Simple/MIL/ControlCore/DSP 原模型与初始化；重整定 PI、改变 FOC 数学以凑一致、全局自动布局、恢复全部运行保护、加入实际反馈滤波、定点化、HDL/C 生成、Vivado 构建、bitstream、硬件操作。
- 实际工作仅在 `D:/Project/FPGA_XC7A200T`；原始 `D:/Project/PMSLM_Simulation` 只读。不得清理、覆盖、stash/reset 用户 tracked/untracked；不增 clone/worktree。若目标文件已存在或当前源与 M0 有影响结果的变化，保留现场并报告。
- 任务仅限 M1A；后续 M1B（启动/保护与恢复）和 M2（定点 HDL）不随本 PR 自动启动。旧 StudyL1 / Step6/7 成果留作参考，不全量重跑。

## 验收边界

需要真实 MATLAB R2026b 的执行输出，不能以文件已提交、model loaded、文档齐全作为动态通过。新模型没有外部 `.m` 初始化时应失败；完全不用 XSI/旧 MAT 即可模拟；同工况对照和物理调制重构必须有可追溯证据。未证明项目的部分如实标记“未验收”，重要物理矛盾不能默默修正。

**完成时停在开放实现 PR，等待 Review；不要自动合并或开始 M1B/M2。**
