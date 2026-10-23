# M1A 纯 Simulink PI-FOC 浮点基线 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在原工程中另存独立纯 Simulink PI-FOC 浮点模型，采用外部 `.m` → Base Workspace 初始化，统一一个 plant、SVPWM 占空比语义与控制时基，并提供可复现的数学和闭环证据。

**Architecture:** 从已审计的本地 Simple 另存新 SLX，仅在新副本中拆除旧 XSI/手写 RTL 联合仿真支路；保持原三环算法、一个平均逆变器和一个自由运动 PMLSM plant。用一个显式外部脚本管理默认参数与场景；用少量独立 MATLAB 批处理检查变量解析、调制、时序和迁移等价性。

**Tech Stack:** MATLAB/Simulink R2026b、Motor Control Blockset；现有 `design_PMLSM_three_loop.m` 和 `pmlsm_scurve_profile.m`；Git/Codex。本阶段不调用 HDL Coder 或 Vivado 构建。

**Spec:** `coordination/specs/m1a_pure_simulink_float_baseline_design.md`（PR45 已合并）。

## Global Constraints

- 当前基线 `main@20003acb3e33c54bdc078fe051a8e6650b8fcaed`；M0 证据见 `coordination/reports/m0_simulink_model_asset_audit.md`。开工时另记实际本地 HEAD、branch、tracked/untracked 和打开的 MATLAB 会话。
- 在原目录 `D:/Project/FPGA_XC7A200T` 实施；外部 `D:/Project/PMSLM_Simulation` 只读。不创建 clone/worktree，不自动 stash、reset --hard、clean，不覆盖用户文件或删除历史模型与硬件资料。
- 原 `PMLSM_ThreeLoop_Simple.slx`（包括未提交本地版）、`PMLSM_MIL_ControlCore_Sim.slx`、`PMLSM_ControlCore_Block.slx`、`PMSLM_Close_Loop_MBDL4.slx` 和旧初始化/RTL/StudyL1 只读。复制/另存后，**仅**修改新副本与新脚本。
- 来源可能有未提交 SLX、MAT、初始化回调变更。优先用 M0 已审计的本地版，但必须先确认 as-found；存在不一致或目标同名文件时不覆盖，保留差异并报告。不能仅复制旧 MAT 作为新模型依赖。
- 浮点算法保留原 dq PI、前拍 AW、复位/限幅、外环、Reference Manager、S 曲线和平均 plant；不重整定 PI、不恢复完整故障/行程/对齐状态机、不加入实际测速滤波。
- 统一 `T_pwm=Ts_ACR=1e-4 s`，`Ts_ASR=1e-3 s`，`Ts_POS=1e-2 s`，`Ts_Plant=1e-6 s`，PWM 半周期延迟 `5e-5 s` 一次，平均死区默认 `1e-6 s`、理想工况 0。单位：Apeak、V、rad、rad/s、m/m/s（外环 mm/mm/s）。
- 单一 plant：`Rs=2.37 Ω`、`Ld=Lq=1.745e-3 H`、`psi_f=0.141 Wb`、`M=0.91 kg`、`Kf_peak=31.4/sqrt(2) N/Apeak`、`lambda_e=0.06 m`、`Vdc=48 V`。这些为来源参数，不是重新实测标定。
- 新模型必须可在新 MATLAB 进程显式执行 `init_PMLSM_PI_FOC_Float_Baseline` 后直接仿真；不得要求 `CONTROL_BACKEND`、`pmlsm_prepare_interactive_cosim`、XSI DLL、旧 `.mat` 或手写 RTL。
- 测试和源码快照均在独立 MATLAB 进程/隔离临时目录进行。源码等价与新模型验收是两种不同结果；MATLAB/Vivado 没有实际运行就不得标记 PASS。历史结果仅用于选择测试场景。
- 不进行定点化、HDL/C 生成、Vivado 实现、bitstream、硬件上电或电机操作。每一检查点产出可审查的日志与小范围提交；最后停在开放 PR，等待 ChatGPT Review。

## Review Focus

1. **未执行初始化或只剩其他模型旧变量：** 新模型拒绝编译/仿真，并提示正确的外部 `.m`；Task 2 实测。
2. **Model Workspace/mask 遮蔽 Base Workspace：** 外部脚本更改给定/负载，解析值和实际响应应改变；Task 2 实测。
3. **残留 XSI/旧 MAT/交互 prepare：** fresh MATLAB 下无需 DLL/prepare，所有源依赖可定位；Task 1/2 实测。
4. **占空比极性、计数分母和更新/死区责任：** 零矢量及六扇区电压重构正确，只有一套半周期更新和平均死区；Task 3 实测。
5. **状态与时序在停机/复位或步长变化时漂移：** 不误清前拍 AW、控制 tick 不随 plant 步长变更；Task 4 实测。

---

### Task 1: 冻结来源并另存无 XSI 的浮点模型骨架

**Files:**
- Create: `simulink模型/PMLSM_PI_FOC_Float_Baseline.slx`
- Create: `scripts/m1a_verify_float_baseline.m`
- Output evidence: `docs/reports/m1a_float_baseline/source_inventory.md`（先记录来源与改动清单）
- Read-only: `simulink模型/PMLSM_ThreeLoop_Simple.slx`、其原初始化脚本和本地 MAT、M0 证据

**Interfaces:**
- 验证入口：`function result = m1a_verify_float_baseline(stage)`，`stage` 只接受 `'structure'`、`'init'`、`'math'`、`'closedloop'`、`'all'`，返回含 `pass` / `details` 的 struct，失败须返回非零 batch 退出码（通过 assert/error）。
- 结构检查只读新 SLX；禁止在该函数内保存任何旧 SLX。

- [ ] **Step 1: 前检来源与工作区。** 记录 Git status、M0 对照的本地/远端 Simple、初始化 `.m`、七个 timeseries、callbacks、Model Workspace、厂商库和主要线束；确认旧模型及新文件名有无冲突。创建独立 `.runtime/m1a_...` 输出，不改用户已有路径。
- [ ] **Step 2: 先写 `m1a_verify_float_baseline('structure')` 失败检查。** 检查新模型必须存在、模型名一致、无 HDL Cosimulation/XSI/`FPGA_HDL_Cosim` 有效引用、恰有一个 plant 和一个平均逆变器，且保留三环 `FOC_Algorithm`、外环、scheduler 与必要监视接口。先运行，预期 `M1A_MODEL_MISSING` 或相应断言失败（不把缺失误写 PASS）。
- [ ] **Step 3: 在全新 MATLAB 进程从确认的源模型另存新 SLX。** 仅在新副本清理旧 co-sim/后端 selector 和旧交互数据入口，保留 legacy 纯 Simulink 计算路径、状态/限幅/复位及单 plant；不为了视觉整洁批量删端口或全局自动布局。静态观察可暂保留 counts，以 Task 3 再进行等价归一化。
- [ ] **Step 4: 运行独立结构验证。** 命令：`matlab -batch "addpath('D:/Project/FPGA_XC7A200T/scripts'); m1a_verify_float_baseline('structure')"`。预期打印 `M1A_STRUCTURE_PASS`，模型只读检查后 Dirty=off；逐项人工审视源/副本差异，原源字节及 Git 用户改动不变。
- [ ] **Step 5: 单独提交新 SLX、结构检查脚本及来源记录。** 不提交原 Simple、旧 MAT 或用户未提交的更改；若源码闭包不能解析，停此检查点报告具体依赖。

### Task 2: 外部 Base Workspace 初始化及独立启动

**Files:**
- Create: `simulink模型/init_PMLSM_PI_FOC_Float_Baseline.m`（MATLAB script，不是需要输出参数的函数）
- Modify: `simulink模型/PMLSM_PI_FOC_Float_Baseline.slx`
- Modify: `scripts/m1a_verify_float_baseline.m`

**Interfaces:**
- 人工入口：`addpath('.../simulink模型'); init_PMLSM_PI_FOC_Float_Baseline; open_system('PMLSM_PI_FOC_Float_Baseline'); sim('PMLSM_PI_FOC_Float_Baseline');`
- 初始化 marker：`PMLSM_M1A_InitVersion`（固定为 `20261023`）；新 `InitFcn` 如存在仅验证 marker、关键参数和时基关系，不装载脚本或写 Workspace。

- [ ] **Step 1: 先增加 `'init'` 失败检查。** 新进程未初始化时 `update/sim` 必须明确报错并包含脚本名称；故意在 Base 预置旧 `Kp_ACR` / `Udc` 或从其他模型留下的值时，不能绕过 marker；旧 Model Workspace 同名变量也不能遮蔽新参数。
- [ ] **Step 2: 执行负例测试，确认在当前未配置新入口时失败。** 保存失败信息为可追踪证据，不能因为上一次 MATLAB 会话的隐藏变量而虚假通过。
- [ ] **Step 3: 编写显式初始化脚本。** 分节设置电机/单位、时基、三环整定（优先复用纯计算 `design_PMLSM_three_loop` 并核对 M0 增益）、逆变器、默认 1 mm/1.2 s/零负载场景、另设 0.8 s 加 0.5 N 与 1.0 s 撤除场景、初态和观测量；每次重新执行完整覆盖本模型公开默认值。无 `clear/clc/close all`，不再引用旧 MAT；阶跃时序明确 ZOH/保持，不插值成斜坡。
- [ ] **Step 4: 清理新模型参数权威源。** 所有控制/plant 同名值由 Base Workspace 提供；不留 Model Workspace 或 mask 独立硬编码覆盖。删除新副本原 `reload(ModelWorkspace)`、`pmlsm_interactive_cosim_init`、co-sim `PreLoadFcn`；加入只读必要性检查。
- [ ] **Step 5: 正向验证 fresh MATLAB 独立运行。** `matlab -batch "addpath('D:/Project/FPGA_XC7A200T/simulink模型'); addpath('D:/Project/FPGA_XC7A200T/scripts'); m1a_verify_float_baseline('init')"`；验证两次运行初始化/短时仿真可复现、`slResolve` 与关键 mask 值归因正确，修改外部场景给定或负载后实际生效，恢复默认仍一致；输出 `M1A_INIT_PASS`。
- [ ] **Step 6: 提交新 `.m`、只属于新模型的参数/回调调整和测试。** 不修改历史初始化脚本。

### Task 3: 统一物理/时基与归一化 SVPWM → 平均逆变器接口

**Files:**
- Modify: `simulink模型/PMLSM_PI_FOC_Float_Baseline.slx`
- Modify: `simulink模型/init_PMLSM_PI_FOC_Float_Baseline.m`
- Modify: `scripts/m1a_verify_float_baseline.m`

**Interfaces:**
- 三路控制器命令输出：`duty_u_cmd` / `duty_v_cmd` / `duty_w_cmd`，表示 **死区前、PWM 更新前的理想上管高电平比例**，线性区 `[0,1]`；零矢量各为 `0.5`。
- PWM 事件：命令 duty → 一次半周期更新保持 → 一次平均死区 → 原饱和/电压重构 → 单 plant。
- 基线物理变换核查：`theta_e=2*pi*x_m/0.06+offset`，`omega_e=2*pi*v_mps/0.06`；控制器与 plant 只引用同一参数来源。

- [ ] **Step 1: 先写 `'math'` 检查并确认旧输出尚未满足新接口的负例。** 验证 `Ts` 比例与首个 tick、源 old counts 和新 normalized duty 的零矢量/六扇区及边界关系、物理电压独立重构、PI 复位和前拍 AW 状态。检查失败须标注具体电流/角度/占空比/时刻，不接受仅目测曲线。
- [ ] **Step 2: 只在新副本实施最小等价转换。** 保留现有扇区式 SVPWM 数学，移出依赖 `CPU_Clock` 或 `TBPRD` 的 raw-counts 主链；归一化 duty 不属于已装载的 active 比例，不额外增加预死区饱和；旧 counts 只保留在隔离测试对照，不保留另一套运行后端。
- [ ] **Step 3: 固定单 plant 和时基。** 外部脚本集中派生 100 us / 1 ms / 10 ms / 1 us、50 us 更新延迟、1 us 平均死区；检查所有控制触发器和 plant 实际积分块的有效 SampleTime。电机/负载继续自由运动；不引入实际速度差分/IIR。
- [ ] **Step 4: 运行 `'math'`。** 预期 `M1A_MATH_PASS`，至少覆盖零矢量、六扇区内部、扇区切换两侧、限幅附近、上下边界、enable=0 和 reset；由 `v_phase=Vdc*(duty-mean(duty))` 重构 alpha/beta，与 SVPWM 输入进行独立对照，且不得双计 PWM 更新或死区。
- [ ] **Step 5: 单独提交算法输出适配、时基/物理参数整理和对应证据。** 若出现真实极性/单位不一致，保留失败和来源证据，停止推进并提交需 Review 的差异，不通过改 PI 或交换相线让波形强行一致。

### Task 4: 纯 Simulink 闭环迁移验收与交付

**Files:**
- Modify: `scripts/m1a_verify_float_baseline.m`
- Create: `coordination/reports/m1a_pure_simulink_float_baseline.md`
- Create: `docs/PMLSM_FLOAT_BASELINE_GUIDE_ZH.md`
- Create: `docs/reports/m1a_float_baseline/README.md`（精简日志/误差/测试索引）
- Modify: `README.md`、`coordination/HANDOFF.md`（验收后按事实更新）

**Interfaces:**
- `m1a_verify_float_baseline('closedloop')` 在隔离进程运行有限的浮点工况并写指标；`'all'` 包含前面三项。最终命令与实际结果写在报告中，不以旧 RTL 比较阈值代替新浮点等价性。
- 源对照使用 M0 对应的本地 Simple backend0 纯 Simulink 路径，在另一个隔离进程作只读运行；允许使用原本专用的准备过程获取源结果，但新模型不得依赖它，且源 SLX 不保存。

- [ ] **Step 1: 在最终闭环比对前记录来源、初态、场景、仿真步长、信号对齐和误差阈值。** 写入验证配置或报告草稿并提交/留痕，之后不根据测试误差回调阈值。
- [ ] **Step 2: 增加 `'closedloop'` 测试并先验证失败。** 场景含正负电流（机械自由运动）、代表性速度、正负 1 mm 位置、理想与 1 us 平均死区、独立 0.5 N 负载、stop/PI reset；必须含状态/事件比较，不只记录末值。
- [ ] **Step 3: 用新模型和所选源的纯 Simulink 后端执行同工况对照。** 单一 plant、控制参数、采样与 PWM 延迟口径一致；比较 `id/iq`、`vd/vq`、三相 duty、`v`、`x`、关键 PI/AW 状态，逐信号记录最大绝对误差、RMSE、单位和事件一致性。若需等价之外的物理修复，标为独立差异并等待 Review。
- [ ] **Step 4: 重复运行与步长检查。** 用独立 fresh MATLAB 进程两次初始化/运行；对一个代表性工况比较 1 us vs 0.5 us plant 步长收敛，确认电流/速度/位置环 tick 不变。输出 `M1A_CLOSEDLOOP_PASS`（不满足任一预定门槛不得输出 PASS）。
- [ ] **Step 5: 编写用户可直接复现的中文指南。** 从新 MATLAB 窗口执行外部初始化、加载 SLX、运行默认/负载场景、修改参数重载；注明不依赖 XSI/MAT、不代表实机安全与 HDL 已生成。
- [ ] **Step 6: 复核文件与 Git 差异、提交开放实施 PR。** 检查 `git diff --check`、源模型/脚本字节未改变、原 tracked/untracked 保留；仅提交新 SLX/新 `.m`、少量测试、精简结果及文档。报告写清未执行的 HDL/Vivado/板级工作，停在开放 PR，不进入 M1B/M2。

## Exit Criteria

- [ ] 新模型和外部脚本在仓库中，脱离本地旧 MAT/交互 XSI 后独立可运行。
- [ ] 模型使用单 plant、明确物理单位、一个调制占空比边界、一处更新延迟和一处平均死区。
- [ ] 外部脚本变量无 Model Workspace/mask 遮蔽；未初始化/改值生效/两次 fresh run 已有证据。
- [ ] 有新源数学/闭环/时序/步长对照，区分 PASS、已知差异与未测项；只改变组织方式的部分符合预定数值容差。
- [ ] 原三模型及用户未提交版本保持；实现 PR 仅涉及授权文件、开放等待 Review。

**Execution handoff:** 依照本仓库已约定方式，由用户本机 Codex 在原项目逐 Task 实施，每个检查点复核并小步提交；本计划 PR 合并前不实施。本计划不授权自动合并、上板、HDL 生成或下一阶段。
