# Step 7D：恢复 Simulink 外环，完成 FPGA 电流内环三环联合仿真

> **For agentic workers:** REQUIRED SUB-SKILL: 使用 `superpowers:executing-plans`，按 Task 1–8 顺序执行；步骤使用 `- [ ]` 跟踪。执行位置只能是用户原始主工作树，不创建 worktree 或额外 clone。

**Goal：** 复用原有 Simulink 速度环、位置环与 FPGA HDL 电流环，在自由运动 PMLSM 平均模型中完成速度跟踪、位置到位、负载扰动和关闭输出验证。

**Architecture：** 外环继续在 Simulink 中执行，通过现有 `id_cmd/iq_cmd` 和 Input Adapter 向 FPGA 提供电流参考。FPGA 继续输出 `CMP_active/2500`，驱动唯一一套平均逆变器与电机模型；不改变电流环 RTL、PWM 事务、定点接口或死区职责。

**Tech Stack：** 当前项目已有 MATLAB/Simulink、HDL Verifier、Fixed-Point Designer、Vivado/XSim/XSI、SystemVerilog。沿用本地已验证工具安装；先核对实际版本，不为本任务升级工具链。

**Spec：** 本文件第 1–7 节是本任务的设计与验收依据，第 8 节是实施计划；两者共同构成一份完整任务书。

**文档日期：** 2026-09-22。  
**已核实代码基线：** PR #31，merge commit `8b31b988bfe3d935898ca5960df2051c70836f5e`。  
**拟放置路径：** `coordination/tasks/step7d_outer_loops_cosim.md`。  
**状态：** 任务定义，不是实施报告。本文件中的 Step 7D 性能门槛尚未经 MATLAB/Vivado 实测；不得把任务书写成已经通过的结果。文档合并并交给 Codex 后，才执行实现。

---

## 1. 本阶段要完成什么

当前 Step 7C 已闭合 FPGA 电流环，但电流参考来自测试脚本。Step 7D 改用原有外环的实时输出，依次完成：

```text
速度模式：
速度请求 -> 原有速度参考管理/速度 PI -> iq_cmd
                                            |
位置模式：                                  v
位置轨迹 -> 原有位置环 -> 原有速度环 -> FPGA Input Adapter
                                            |
                                            v
                                    FPGA HDL 电流环
                                            |
                                      CMP_active/2500
                                            |
                              共享平均逆变器/平均死区
                                            |
                                   自由运动 PMLSM

位置、速度反馈 -> 原有 Simulink 外环
ia/ib/ic/theta_e/omega_e -> FPGA 电流环
```

先速度，后位置。保留 `id_ref=0`，不增加弱磁、观测器、速度/位置 RTL 或运行时后端切换。

最终应当能够从项目根目录调用一个明确的运行入口，选择速度或位置场景，运行真实 HDL 联合仿真，生成可追溯的数据、判据和报告。保存模型的默认状态继续是 legacy，不要求把保存默认改成 FPGA。

## 2. Global Constraints：不可破坏的边界

### 2.1 工作区、权限与职责

- 实施仅在 `D:/Project/FPGA_XC7A200T`；不创建 linked worktree、额外 clone 或云端实施副本。
- 保留用户全部 tracked/untracked 内容、本地硬件资料、旧工程和仿真结果。外部 `D:/Project/PMSLM_Simulation` 只读。
- 禁止 `reset --hard`、`clean -fd`、强制切分支、自动 stash、整体覆盖和自动清理。
- Git SHA 只标识版本，不用文件哈希代替功能验收。
- 不生成 bitstream，不连接板卡，不驱动真实功率级，不引入 Vitis/Linux/SoC 迁移。
- 实现完成后创建开放 PR，等待 ChatGPT Review；不自动合并、不开始下一阶段。
- `HANDOFF.md` 中“Step 7C 不得开始 Step 7D”是旧阶段的范围限制。本任务正式授权执行后，以本文件定义的 Step 7D 范围为准；其他工作区保护约定继续生效。

### 2.2 控制链与模型

必须保留：

```text
CONTROL_BACKEND=0：原 legacy Simulink 后端
CONTROL_BACKEND=1：FPGA HDL 后端

FPGA ideal duty = CMP_active / 2500
共享路径 = deadtime correction -> d_sum -> d_sat[0,1] -> v0_eff_calc
```

FPGA 路径不得重新经过 `PWM_Update_HalfTs`、旧计数缩放或旧极性反转。不得给 legacy 新增 pre-deadtime saturation。只有一套 plant、一套公共平均逆变器/死区；不把 Step 6E 的门极死区再叠加到平均模型上。

保留自由运动：不锁定位置或速度，不增加软/硬行程限制，不通过修改 plant 状态或强制速度归零来制造通过结果。小位移参考不是行程钳位。

所有 `motor_control_ip/**/rtl/*`、ROM、PI profile 和 HDL 端口契约在本阶段只读。`PI_PROFILE=0` 不变。外环原有增益、限幅、抗饱和算法也先冻结；性能异常先诊断，调参需要另行授权。

### 2.3 时间与参数

| 项目 | 固定值/规则 |
|---|---|
| HDL fabric clock | 20 ns，50 MHz |
| PWM/current transaction | 100 μs，10 kHz |
| `Ts`、`Ts_ACR` | 100 μs |
| `Ts_ASR` | 1 ms |
| `Ts_POS` | 10 ms |
| FPGA reference exchange、plant 积分 | 1 μs |
| 收敛对照 exchange、plant 积分 | 0.5 μs，仅对照场景 |
| XSI 初始化 reset | 200 ns |
| PreRunTime | 0 |
| 物理时间映射 | 1:1，不做时间压缩 |
| `Udc` | 48 V |
| `Host_Id_A` | 0 A |
| `Host_Iq_Test_Mode` | 0：外环场景禁止走直给 iq 测试 |
| 速度环输出限幅 | 保留当前 `Speed_loop_Iq_Limit=1 A` |
| 速度积分限幅 | 保留当前 `Iq_int_limit=0.5`，先核对其实际状态/单位 |
| 位置死区 | 保留 `Pos_deadband=0.02 mm` |

1 μs 是通信/积分步长，不是把速度、位置控制器加速到 1 MHz。四个 plant 离散积分器、模型 solver、HDL 输出 PortTimes 必须一致。速度/位置环的真实执行节拍要用调度证据验证，不能只打印 `Ts_ASR/Ts_POS`。

## 3. 已有实现事实与必须先核对的事项

### 3.1 已有入口，不要重复建设

现有顶层有 `Simple_Host`、`Control_Task_10kHz`、`Inverter_DeadTime`、`PMLSM_Plant_Model`、`FPGA_HDL_Cosim`。Step 7B 已将 `PWM_EN/ia/ib/ic/theta/we/id_cmd/iq_cmd/vdc/PI_Reset` 标签接入 FPGA 分支；Step 7C 已在 Input Adapter 增加参考选择。

Step 7D FPGA 场景的有效配置应为：

```matlab
CONTROL_BACKEND       = 1;
FPGA_Cosim_Enable     = 1;
FPGA_Cosim_Input_Mode = 1;  % live plant feedback，不是 smoke
FPGA_Reference_Mode   = 1;  % live id_cmd/iq_cmd，不是 Step 7C scripted refs
```

当前 `FPGA_Reference_Mode=0` 选择脚本，非零选择 live。Step 7D 将其约束为上述明确的 0/1 值，不接受任意非零值。

`STEP7C_run_gate_ts` 仍参与 live run gate 的 AND。正常外环场景必须把它配置为覆盖完整仿真时长的常 1；保留脚本 id/iq 变量供模型编译，但不得让它们成为控制源。

### 3.2 不直接复用 Step 7C 场景检查器

现有 `step7c_run_scenario.m` 固定 scripted reference，并在 InitFcn 参数重载后追加覆盖。`step7c_check_scenario_start.m` 明确断言 reference mode 为 0、负载为 0、位置环关闭。

因此：复用其中通用的 timing/工具环境处理，不直接调用这个场景检查器验收 Step 7D，也不删除其断言来让新场景“通过”。新增 Step 7D 的有效配置检查。

### 3.3 外环结构以本地 SLX 实际内容为准

在任何保存模型的修改前，导出并核对：

| 必须查清的对象 | 需要记录的证据 |
|---|---|
| 位置/速度控制器及参考管理器 | 完整 block/chart 路径、代码或参数、实际输入输出 |
| `id_cmd/iq_cmd` | 唯一生产者、作用域、单位、更新时间、到 Adapter 的完整路径 |
| 调度 | 100 μs 控制任务、1 ms 速度任务、10 ms 位置任务的触发机制与相位 |
| 单位 | x 为 mm、v 为 mm/s、角度为 electrical rad、we 为 electrical rad/s、电流为 A |
| 重置与使能 | `Close_Loop_EN/Position_Loop_EN/PWM_EN/PI_Reset` 的生产者和状态规则 |
| 饱和与积分 | iq 限幅点、积分状态实际单位、抗饱和与 reset/freeze 行为 |
| Host 轨迹 | 小位移配置后的真实参考、完成时间及速度前馈 |
| 所有初始化回调 | PreLoadFcn、InitFcn、StartFcn 及 model/base workspace 覆盖关系 |

不能只根据变量名推断控制器已经按对应周期执行。如果需要拆控制器、改调度算法或改变公共标签语义才能接入，先停止并提交差异报告，不擅自重构。

## 4. 接入设计与运行配置

### 4.1 优先不改 SLX

首选复用现成 live reference 通道，仅增加 Step 7D 运行、检查与报告脚本。旧 Simulink 电流 PI/SVPWM 可以保留计算或监视，但必须与 FPGA plant 驱动路径隔离，不能再次参与执行链。

若必须增加观测口或局部接线，只做可解释的最小修改，并证明 legacy 行为不变。禁止复制第二套外环控制器形成两个会更新状态的实例，也不整模型重建。

### 4.2 初始化后的真实配置才算数

从干净会话启动时，加载模型可能执行 PreLoadFcn；运行时 InitFcn 会重新初始化参数。配置脚本必须在这些初始化之后施加正确覆盖，并在 StartFcn 使用实际解析值检查：

```matlab
assert(isequal(effective_modes, [1 1 1 1]));
assert(abs(Ts_ACR - 1e-4) < 1e-15);
assert(abs(Ts_ASR - 1e-3) < 1e-15);
assert(abs(Ts_POS - 1e-2) < 1e-15);
assert(abs(PMLSM_Ts_s - commTs) < 1e-15);
assert(abs(PMLSM_deadtime_ratio - deadtime_s/1e-4) < 1e-15);
```

`effective_modes` 必须由 `slResolve` 等从实际运行模型读取，不能直接取 cfg 里“希望设置的值”。检查有效 `Host_Iq_Test_Mode`、使能模式、Vdc、限幅、四个 plant 积分器及所有 HDL 输出 PortTimes。

保存默认继续是 legacy。运行时配置、临时探针和测试信号不自动保存到 SLX；报错也必须恢复本次脚本改变的 cwd、MATLAB path 和进程环境。不关闭或覆盖用户已经打开且未保存的模型，遇到这种情况应停止并提示保存/关闭。

### 4.3 测试激励只进入高层请求与负载边界

速度请求进入现有速度参考管理器之前；位置请求使用现有 Simple_Host 轨迹生成器与位置入口。禁止直接把期望 iq 或期望速度写到电流参考/plant 反馈来替代外环。

现有 Host 若仅接受常数速度/负载，允许在内存中对其高层输出边界增加测试源；必须记录被替换的实际 wire，并对 backend 0/1 使用同一个测试源。不得绕过原速度参考管理、限幅、速度 PI 或位置环。

正、负位置测试分别从初始静止状态启动，复用原有轨迹生成器；不宣称这验证了同一次运行中的位置模式切换或往返切换。运行时后端/模式无扰切换不在范围内。

### 4.4 时序与数值观察

同步记录外环输出、Adapter 选中值和量化后值。外环输出按其原有更新规则保持；不额外加一个电流周期、速度周期或“保险用”的 Unit Delay。

在 accepted 时刻检查“本次被接收的参考/反馈”，在 active 时刻检查该 command ID 对应的生效命令。不能拿 active 时刻的新参考与上一 accepted 命令错误配对。

`iq_ref` 量化使用既有 Q15 规则，量化误差上限为半 LSB 加浮点数值余量。没有新增 Rate Transition 时，量化前 live 引用误差应不超过 `1e-12`；若确需跨速率保持，必须给出保持源、相位与逐命令对应关系。

## 5. 固定测试场景

所有正常场景从零电气/机械状态、48 V 开始。指标、激励、窗口在观察 FPGA 性能结果之前提交冻结；禁止失败后自动放宽指标或缩短到“好看”的区间。

### 5.1 速度轨迹：`speed_ideal` / `speed_deadtime`

两者使用相同速度、负载、外环参数，仅平均死区分别为 0 和 1 μs。StopTime 为 1.20 s。

```text
time(s)       0    .05   .15   .30   .40   .50   .60   .75   .85   1.20
v_request     0     0     5     5     0     0    -5    -5     0      0  mm/s
```

相邻节点线性连接，速度请求斜率不超过 50 mm/s²；后续仍经过原速度参考管理器。记录 request、管理后的实际 `v_ref` 和反馈三条曲线，性能以实际送进速度 PI 的参考为准。

负载是沿既有 plant 正负号约定的 +0.5 N 阶跃：

```text
0–0.20 s     0 N
0.20–0.25 s  +0.5 N
0.25–0.90 s  0 N
0.90–1.05 s  +0.5 N
1.05–1.20 s  0 N
```

负载与使能使用零阶保持，不进行线性插值。正负号由 Task 1 核对，不能靠给反馈加负号修正。

稳态统计窗口：`[0.27,0.30)`、`[0.44,0.49)`、`[0.65,0.74)`、`[1.00,1.04)`、`[1.12,1.20)` s。每个窗口至少包含 20 个速度任务样本，否则报错。若原参考管理器导致这些窗口不是恒值，必须在 Task 1 baseline 中停止并报告，而不是跑完 FPGA 后移动窗口。

### 5.2 位置轨迹：`position_ideal` / `position_deadtime`

使用原有 Simple_Host 小位移轨迹，配置：

```matlab
Host_Enable_Schedule = [0 1 1 1];
Host_Start_s         = 0.05;
Host_Target_mm       = 1.0;
Host_Traj_Vmax       = 5;       % mm/s
Host_Traj_Amax       = 50;      % mm/s^2
Host_Traj_Jmax       = 1000;    % mm/s^3
Host_Speed_Ramp_s    = 0.1;     % 仅测试轨迹配置，不修改控制器增益
Host_Iq_Test_Mode    = 0;
Host_Id_A           = 0;
```

两者平均死区分别为 0 / 1 μs；StopTime 为 1.20 s。轨迹必须在 0.70 s 之前结束，之后为目标位置保持。施加 `+0.5 N` 负载于 `[0.80,1.00)` s，其他时间 0 N。

Task 1 必须从实际 Host 输出确认轨迹持续时间；若上述条件不成立，先报告轨迹和参数解释差异，不改写轨迹发生器凑时长。到位统计窗口是 `[0.72,0.79)`、`[0.92,0.99)` 和 `[1.10,1.20)` s。

### 5.3 负向位置：`position_negative_deadtime`

与 `position_deadtime` 相同，但 `Host_Target_mm=-1.0`，负载为 0。它验证负向位置控制方向与到位，不模拟同一次运行的动态换模式。StopTime 仍为 1.20 s，到位统计采用最后 0.10 s。

### 5.4 关闭输出与禁止自行重启：`stop_restart_inhibit`

速度模式，0–0.05 s 请求为 0，0.05–0.15 s 线性升至 +5 mm/s，之后保持 +5 mm/s；1 μs 平均死区、负载 0、StopTime 0.40 s。

通过现有 PWM_EN 高层控制入口实施：

```text
0–0.25 s    PWM_EN=1
0.25–0.30 s PWM_EN=0
0.30–0.40 s PWM_EN=1
```

另在 `[0.35,0.352)` s 施加一次现有 `PI_Reset` 请求，记录它在 Adapter 端实际呈现的脉冲。不改变 `reset_n` 的端口类型或 XSI 复位配置。

预期：运动中关闭后输出失效且 `needs_reset=1`；重新拉高 PWM_EN、再发 PI_Reset 都不能恢复桥输出。当前 `pi_reset` 只属于控制计算侧，不能冒充 top-level `reset_n`。

结束后从新的 simulation/XSI 初始化运行一个独立的 20 ms 零参考启动测试，验证默认复位能重新进入正常命令事务。必须明确：这是“重新开始一次仿真”，不是验证运动中保留 plant 状态的热重启。后者留到单独阶段。

### 5.5 饱和/复位组件测试

从审计确认的原速度 PI/限幅块建立仅用于测试的内存 harness，不另写一个替代 PI。施加足以触发正负限幅的合成速度误差，验证 ±1 A 输出限制、积分状态上限、既有抗饱和行为与显式 reset。

此 harness 可使用合成误差，但必须标为组件测试，不能计作真实 plant 闭环证据。正常集成场景不故意制造超大负载或超大速度请求来触发饱和。

特别禁止“速度参考为零就清积分”：零速负载保持可能需要非零 iq 与积分状态。零误差本身也不意味着积分状态应自动回零。

## 6. 验收判据

以下是本任务新规定的验证门槛，不是已测性能。如果 untouched legacy 的相同场景达不到性能门槛，在 Task 1 报告并停止性能接入工作；可以继续只读诊断，不能自行调增益、换模型或放宽门槛。

### 6.1 结构、配置、协议：硬性门槛

| 类别 | 必须满足 |
|---|---|
| live reference | `FPGA_Reference_Mode=1`，Adapter 来源逐样本/逐命令可证明 |
| live feedback | ia/ib/ic/theta_e/we 来自正在运动的唯一 plant |
| 静态 backend | backend 0 不初始化 HDL/XSI，backend 1 才启用 HDL |
| 电压执行边界 | 选中 duty 对应 active CMP/2500；无额外旧 PWM delay 或极性处理 |
| 调度 | current=100 μs、speed=1 ms、position=10 ms；相位固定且有执行证据 |
| normal transaction | accepted/active ID 单调、对应正确、不丢失、不重复执行 |
| accepted 到 active | 保留约 50 μs 的既有关系；观测误差不超过一个 commTs 加数值余量 |
| 正常状态 | fault=0、needs_reset=0；初始化结束后桥有效 |
| 数据质量 | 无 NaN/Inf、定点 range flag、非预期 overflow 或隐式单位转换 |
| 旧功能 | legacy before/after 等价、Step 7C 与必要 7B/6D/6E 回归通过 |

调度证据优先使用原任务 trigger、使能计数器或执行记录；不能把“输出数值没变化”当成任务没执行，也不能把信号日志采样率当成控制器执行率。

命令 ID 的最终计数按实际复位相位和完整观察区间计算，不照抄 Step 7C 的 120/119。比较收敛时统一排除不完整的末尾事务。

### 6.2 性能门槛

所有误差必须注明参考来源、单位、统计区间和有效样本数。速度性能在速度任务网格上计算；位置在位置任务网格及 plant 峰值记录上交叉检查；电流在电流事务网格上计算，并额外保留全速峰值。

| 指标 | 门槛 |
|---|---|
| 速度各稳态窗口 mean(abs(v_ref-v)) | ≤0.5 mm/s |
| 速度各稳态窗口 RMSE | ≤0.5 mm/s |
| 速度各稳态窗口最大绝对误差 | ≤2.0 mm/s |
| 正/负速度方向 | 对应稳态段平均速度分别 >+2.5 / <-2.5 mm/s |
| 零速带载窗口 `[1.00,1.04)` | 满足相同速度门槛；记录平均 iq、积分状态，不强行清零 |
| 位置规定到位窗口最大绝对误差 | ≤0.05 mm |
| 位置运行全过程相对最终目标的越界超调 | 正向 x≤1.10 mm；负向 x≥-1.10 mm |
| 到位窗口最大绝对速度 | ≤1.0 mm/s |
| 正常场景全程 `abs(iq_ref)` | ≤1 A 加数值余量 |
| 电流跟踪 RMSE，去除前 2 ms 初始化 | ideal≤0.05 A；deadtime≤0.10 A |
| 正常场景全程 `abs(id)` | ideal≤0.10 A；deadtime≤0.50 A |
| 正常场景全程 `abs(iq)` | ≤1.50 A |

同时报告速度暂态峰值、恢复时间、位置轨迹误差峰值/RMSE、相电流峰值和 iq 限幅占比，不把未设门槛的指标虚构成 PASS。不要用低通滤波、裁掉异常点或降采样漏峰来满足门槛。

当前 plant 参数给出的静态推力平衡预期为 `iq≈F_load/(31.4/sqrt(2))`，0.5 N 时约 0.0225 A；这是量纲和方向检查参考，不另设一个未经验证的强制精度门槛。必须以真实 plant 方程确认符号。

### 6.3 关闭与重新初始化

在 PWM_EN 关闭后的第一个完整 commTs 观察点起：`active_valid=0`、`bridge_enable=0`、所选平均逆变器 `vd/vq=0`、`needs_reset=1`、`fault_code=0`。允许具体观测相位遵循已有 XSI 记录，不宣称检测到了纳秒级硬件响应。

重新拉高 PWM_EN、发 PI_Reset 后仍应保持禁止输出。记录外环积分的 freeze/reset/继续计算行为，证明其有界且不绕开禁止状态。不要求无授权的外环重构。

禁止把 plant 速度或位置清零。当前关闭逆变器的数学行为不等同于真实功率级自由续流模型，不以此声称实机停车性能。

### 6.4 基线与两种后端的区别

**同一 legacy 运行条件、修改前后：** 相同时间网格和初值，原 17 路信号及新增外环参考/状态的最大绝对差异 ≤`1e-10`；离散模式/使能序列完全一致。未覆盖全长轨迹的 5 ms 基线不能代替外环等价验证。

**legacy 对 FPGA：** 使用相同高层场景、plant 参数与 1 μs 积分步长，分别报告上表性能和差异；不要求波形逐位一致。legacy 保留自身 PWM/count 语义，不能为了让两者相同而偷偷修改 legacy。

### 6.5 数值收敛

采用 `position_ideal` 的原始配置，从 0 至 0.20 s 做 1 μs / 0.5 μs 对照，覆盖多次位置、速度与电流更新。只缩短观察终点，不改变轨迹、控制周期或增益；本项不替代 1.20 s 位置性能测试。

共同时间网格最大差异：`Δiq≤0.01 A`、`Δid≤0.01 A`、`Δv≤0.25 mm/s`、`Δx≤0.005 mm`。完整 accepted/active 命令数一致、外环执行节拍一致、fault/range flag 均为 0。离散命令按保持/事件对齐，不进行线性插值。

## 7. Review Focus：容易出现的假通过

1. **参数被初始化覆盖。** Task 2 用错误 backend、reference mode、control period 注入测试，证明启动检查拒绝它们。
2. **看似 live，实际仍是 scripted/smoke。** Task 3 验证完整来源，并用未选中分支的 canary 值证明不会影响选中数据。
3. **日志采样率冒充控制执行率，或重复半周期延迟。** Task 3/7 同时检查调度事件、accepted/active ID 和 selected duty。
4. **PI_Reset 被当作全局重启，或零速参考错误清积分。** Task 4/6 验证零速带载保持、关闭后的重启禁止和全新 simulation 复位。
5. **错误评估器或旧日志造成 PASS。** Task 2/8 验证 NaN、缺失列、空窗口、丢命令、缺失报告均导致失败；全部最终证据来自同一 run ID。

## 8. 实施计划

### Task 1：只读审计、原有外环基线与门槛冻结

**涉及文件：** 读取本文件、`coordination/HANDOFF.md`、Step 7C 任务/报告、现有 SLX 和初始化文件；新增 `step7d_scenarios.m`、`step7d_capture_baseline.m`，仅做测试配置与观测，不保存模型功能修改。

- [ ] 核对工作目录、Git 分支/状态、origin/main、用户本地改动和 PR31 的祖先关系，写 `preflight.txt`。不要求工作树绝对干净，但必须区分并保护用户改动；必要文件冲突即停止。
- [ ] 读取实际 SLX，完成第 3.3 节审计，写 `outer_loop_inventory.txt`，列出真正的路径/端口/调度/单位。
- [ ] 固化第 5 节场景和第 6 节评估窗口到 `step7d_scenarios.m`，输出可读 `scenario_manifest.txt`。这是新增任务标准，不记录伪造测量值。
- [ ] 在没有调用 HDL setup 的干净 MATLAB 会话，从项目根目录跑 backend 0。保留原 5 ms legacy current baseline；另外抓取 speed_deadtime、position_deadtime 的完整 1.20 s legacy/native-50μs 基线，用于修改前后等价。
- [ ] 对第 5 节正常外环场景，以 backend 0、1 μs plant step 做性能基线；保持控制器周期不变。确认位置轨迹按时完成、速度窗口确实稳态、单位和门槛可解释。
- [ ] 将 baseline 概要、实际配置、外环参数与全程数据位置写入 `baseline_before.txt`，提交这个基线后才能保存功能性 SLX/初始化改动。

**Gate：** legacy 无 XSI 依赖；真实外环路径清楚；原有性能门槛通过。异常写 `coordination/reports/step7d_preflight_blocker.md` 并停止，不猜测接线。

### Task 2：统一场景配置和能够失败的验收器

**新增文件：** `scripts/step7d_configure_model.m`、`scripts/step7d_check_start.m`、`scripts/step7d_assert_result.m`、`scripts/step7d_test_contracts.m`。

- [ ] 先建立错误配置/结果夹具测试，证明尚无检查时测试会失败；不得以“脚本能跑完”代替测试。
- [ ] 实现第 4 节的初始化后覆盖与 StartFcn 检查，legacy 分支不调用 HDL setup，不访问 runtime cwd。
- [ ] `step7d_assert_result(r,cfg)` 检查字段、时间网格、有限值、窗口样本数，再计算指标与断言；异常向上传递。
- [ ] 加入以下至少六项负向自测：reference mode=0、Ts_ASR=1μs、缺少 iq 字段、速度 NaN、空稳态窗口、accepted ID 跳号。每项必须触发对应错误，不是只打印 WARNING。
- [ ] 加入 backend0 可运行、合格人工夹具可通过、负载/使能零阶保持的正向测试。
- [ ] 所有自测通过后打印 `STEP7D_CONTRACT_TESTS_PASS`，提交此任务。

可使用以下断言测试形式；人工数据只测试评估器，不作为 HDL 实验：

```matlab
function must_reject_nan(r,cfg)
% r/cfg 是先通过检查的场景结果和对应配置；不得用坏夹具制造假成功。
step7d_assert_result(r,cfg);
bad = r;
bad.v_mmps(10) = NaN;
failed = false;
try
    step7d_assert_result(bad,cfg);
catch ME
    failed = strcmp(ME.identifier,'Step7D:NonFinite');
end
assert(failed,'NaN must be rejected before performance evaluation');
end
```

### Task 3：接入 live 外环参考，证明时序和真实来源

**新增文件：** `scripts/step7d_run_scenario.m`；复用/调用前述配置检查函数。SLX 只在现有 live 入口确实不够时最小修改。

- [ ] 在需要 HDL 前，按现有方法生成本地 Step 7C runtime；不得重新执行一次性的 refactor/add_references/add_monitor 构造脚本。
- [ ] 设置有效 mode `[1 1 1 1]`、`Host_Iq_Test_Mode=0`、常 1 run gate；速度模式用 `[0 1 0 1]`，位置模式用 `[0 1 1 1]`。
- [ ] 捕获 `id_cmd/iq_cmd`、Adapter live/selected/quantized 数据及 plant feedback，证明外环是唯一参考源，正在运动的 plant 是反馈源。
- [ ] 检查未选中 scripted/smoke 分支改为可区分的合法 canary 值时，选中的 live 数据不变。错误 mode 测试应在启动前拒绝，不运行可能异常的闭环。
- [ ] 用短速度场景记录真实控制调度、accepted/active IDs、selected duty，证明没有新增一个控制周期的延迟。
- [ ] 运行 Task 1 legacy/native 基线的 after 对照，17 路和外环状态满足等价门槛。提交配置/接入及其证据。

**Gate：** `STEP7D_LIVE_INTERFACE_PASS`、`STEP7D_TIMING_PASS`、`STEP7D_LEGACY_EQUIVALENCE_PASS`。任何一个缺失不得进入性能调参或位置接入。

### Task 4：速度闭环、方向反转与零速带载

- [ ] 运行完整 `speed_ideal`，输出 request/实际 v_ref/v、id/iq/iq_ref、负载、积分状态、限幅和命令状态。
- [ ] 运行完整 `speed_deadtime`，保持其余条件不变。
- [ ] 按规定窗口计算正/负速度和零速误差；核对两次负载扰动响应，特别是零速带载时非零推力电流与积分保持。
- [ ] 与相同场景 backend 0 的性能基线并列表述，不声称波形等价。
- [ ] 任何失败依次检查参考模式、单位、方向、更新节拍、量化/延迟、限幅/积分和死区；不先改 PI。

**Gate：** `STEP7D_SPEED_IDEAL_PASS`、`STEP7D_SPEED_DEADTIME_PASS`。图只是辅助，数值断言是通过依据。

### Task 5：位置闭环、负载保持与负向到位

- [ ] 在速度门槛通过后，运行 `position_ideal`。
- [ ] 运行 `position_deadtime`，验证到位前后以及保持期间 0.5 N 扰动；保留真实轨迹及速度前馈，不把 x_ref 直接接到 plant。
- [ ] 运行 `position_negative_deadtime`，从新仿真零初值开始。
- [ ] 统计完整轨迹误差、超调与规定到位窗口；报告相对位置死区的余量。
- [ ] 再核对自由运动、唯一 plant 和原有控制增益未改变，提交结果。

**Gate：** `STEP7D_POSITION_IDEAL_PASS`、`STEP7D_POSITION_DEADTIME_PASS`、`STEP7D_POSITION_NEGATIVE_PASS`。

### Task 6：限幅、关闭输出、禁止误重启和全新启动

- [ ] 完成第 5.5 节的原速度 PI 组件 harness，记录实际饱和/积分/reset 行为。
- [ ] 运行 `stop_restart_inhibit`，确认关闭前电机确实在运动，关闭后桥输出失效而 plant 状态未被重置。
- [ ] 验证重新拉高 PWM_EN 和 PI_Reset 不能清除 needs_reset；检查 blocked 期间输出无有效命令恢复。
- [ ] 检查全新 simulation/XSI 初始化的独立启动测试，证明无残留状态污染；不得把此结果标成热重启。
- [ ] 写清 legacy 外环 stop 管理和 FPGA reset latch 的配合范围，不扩展 `reset_n` 数据接口。

**Gate：** `STEP7D_OUTER_LIMIT_RESET_PASS`、`STEP7D_STOP_INHIBIT_PASS`、`STEP7D_FRESH_RESTART_PASS`。

### Task 7：收敛与旧功能回归

- [ ] 完成第 6.5 节的 0.20 s 共同前缀收敛对照，记录误差和真实执行/事务计数。
- [ ] 重新运行 Step 7C structure、legacy、timing、ideal/deadtime/stop、convergence。
- [ ] 重新运行 Step 7B minimal real Simulink/XSI exchange、FOC wrapper、Step 6D profile0 DEMO=0、Step 6E profile0 DEMO=0。
- [ ] 所有新回归证据写到 Step 7D 本次 run 目录。旧脚本如硬编码历史报告目录，只允许增加向后兼容的可选 `reportDir` 参数，并测试默认行为不变；不覆盖用户或历史报告再假装没有修改。
- [ ] 不扩展 profile1、门极 plant、硬件或综合优化范围。若修改了 runtime/接口执行脚本，重跑所有受影响测试。

**Gate：** `STEP7D_CONVERGENCE_PASS` 及每个被调用旧测试的真实 PASS/零退出码，不能只搜索旧文件中的字符串。

### Task 8：新鲜完整验收、报告与开放 PR

**新增文件：** `scripts/step7d_acceptance.m`、`coordination/reports/step7d_codex_report.md`、`docs/reports/step7d/README.md`。

- [ ] 建立本次独立 run ID；未成功的执行保留 FAIL/异常上下文，不能沿用之前 PASS。
- [ ] 在最后一次 SLX/RTL相关脚本/配置修改后，运行完整验收。报告文字或排版修改不要求重新仿真，但要记录最后被测代码版本与之后文档-only差异。
- [ ] 汇总每个场景的实际配置、判据、数值、样本数、通过/失败和原始数据路径。任务未通过、工具不可用或中断时，不写 FULL PASS。
- [ ] 补充从项目根目录运行的 README、legacy 默认的说明及 runtime 构建前提。
- [ ] 更新 HANDOFF 的 Step 7C 为 PR31 已合并，Step 7D 为“实现完成待 Review”或真实失败/阻塞状态；保留旧阶段历史。
- [ ] 用显式文件清单暂存，检查未夹带用户文件和缓存，推送实现分支并创建开放 PR。

只有全部必要门槛通过，才能输出：

```text
STEP7D_FULL_ACCEPTANCE_PASS
```

**建议实现分支：** `step7d-outer-loops-cosim`。  
**建议实现 PR 标题：** `Step 7D: Restore Simulink outer loops around FPGA current loop`。

## 9. 文件职责与统一接口

优先使用下面的少量脚本和本地 helper，不建设通用测试平台。下列 `step7d_*` 是本任务需要创建的入口，不能把它们写成当前 main 已经存在的功能。

| 文件 | 职责 |
|---|---|
| `scripts/step7d_scenarios.m` | 返回场景配置、输入轨迹、统计窗口和判据 |
| `scripts/step7d_capture_baseline.m` | 修改前 native legacy 数值基线及 1μs matched 性能基线 |
| `scripts/step7d_configure_model.m` | 内存配置、有效 override、观测点与 test source；不自动保存模型 |
| `scripts/step7d_check_start.m` | 真实生效值、结构、时钟/积分器/模式检查 |
| `scripts/step7d_run_scenario.m` | 一次独立仿真、环境恢复、日志归一化 |
| `scripts/step7d_assert_result.m` | 数据完整性、时序、状态、窗口与性能判据 |
| `scripts/step7d_test_contracts.m` | 检查器正向/负向自测与必要组件测试 |
| `scripts/step7d_acceptance.m` | 有序最终验收、收敛/回归调度和唯一最终汇总 |

统一公共调用约定：

```matlab
cfg = step7d_scenarios(name);
[si,cfg,cleanup] = step7d_configure_model(cfg);
step7d_check_start(mdl,cfg);
step7d_capture_baseline(reportDir);
r = step7d_run_scenario(name,backend,commTs,reportDir);
metrics = step7d_assert_result(r,cfg);
step7d_test_contracts;
step7d_acceptance;
```

`name` 为第 5 节六个集成场景之一。另定义两个明确的辅助名称：`convergence_prefix` 复用 position_ideal，但 StopTime=0.20 s；`fresh_start` 为 20 ms 零速度/零电流参考、速度模式、1μs 平均死区、PWM_EN 常 1 的全新仿真。辅助场景仅做各自指定的状态/时序检查，不能生成全长速度/位置性能 PASS。

`cfg` 固定包含 `name`、`purpose`、`backend`、`commTs`、`stopTime`、`deadtime_s`、`host`、`signals`、`windows`、`thresholds`。purpose 只允许 `performance`、`convergence`、`fresh_start`；只有后两种可以没有全长稳态窗口。默认 backend=1、commTs=1e-6；run 的显式参数覆盖后仍需重新校验，实际 cfg 写入 r。native legacy baseline 的 50μs 是 capture_baseline 的专用路径。

`step7d_configure_model` 返回 SimulationInput、实际配置和本次拥有资源的 onCleanup 句柄；调用者必须持有 cleanup 直到仿真/采集结束。它不复用用户已加载的模型。StartFcn 必须传递同一份 cfg，并从运行模型核对真实值，而不是只检查 cfg。

`r` 的固定字段至少如下；数值轨迹使用同一公共 `time_s`，事件另存各自时间，不混淆采样网格：

| 字段 | 含义/单位 |
|---|---|
| `cfg, effective_config, version, run_id` | 请求配置、启动时实际配置、代码/工具版本、本次运行标识 |
| `time_s` | 公共性能数据时间向量，s |
| `x_ref_mm, x_mm` | 位置参考/反馈，mm |
| `v_request_mmps, v_ref_mmps, v_mmps` | 原请求、实际进入 PI 的速度参考、速度反馈，mm/s |
| `id_ref_A, iq_ref_A, id_A, iq_A, ia_A, ib_A, ic_A` | 电流参考与实际电流，A |
| `theta_rad, we_radps, load_N` | 电角度、电角速度、负载 |
| `pwm_en, pi_reset, bridge_enable` | 实际使能、PI reset、选中桥使能 |
| `cmp_active, duty_selected` | N×3 三相 active CMP 与选中 duty |
| `accepted_id, active_id, active_valid, needs_reset, fault_code` | HDL 状态，backend0 标记为不适用而非伪造 HDL 事务 |
| `range_flags, adapter_inputs, quantized_inputs` | 溢出标志、带字段名/单位的选中输入、实际量化结果 |
| `control_events, command_events, state_events` | 原任务执行、HDL 命令、状态变化的独立时间戳与值 |
| `outer_integrator, outer_limit_flags` | 已审计的积分状态/单位、限幅标志 |
| `peaks` | 降采样前从全速数据计算的电流/速度/位置/状态峰值及发生时间 |

字段单位、Adapter 子字段和积分状态单位在 README 固定。backend0 的不适用字段由评估器显式分支跳过，不能以 NaN 填进通用数值轨迹再偷偷忽略。调用 `step7d_assert_result(r,r.cfg)` 可避免显式 backend/commTs 覆盖后仍使用旧 cfg。

公共 100 μs 日志用于全长性能，事件日志用于事务/状态，全速数据用于峰值检查；需要时只保留有限时长的 1 μs 调试窗口。不得因降采样丢失峰值或调度证据，也不强制提交数百万行日志。

## 10. 交付内容与可复现命令

提交：实现脚本、必要最小 SLX/初始化改动、任务报告、README、数值汇总 CSV/TXT、必要曲线。Raw MAT 等大体积诊断留在本地忽略目录，在报告注明准确路径和生成命令。

不要提交 `.Xil`、`xsim.dir`、runtime DLL、SLXC、slprj、生成的临时模型、bitstream 或硬件缓存。历史报告不得当作本轮证据复制后改名。

实施完成后，下列入口应真实可用：

```matlab
cd('D:/Project/FPGA_XC7A200T');
addpath(fullfile(pwd,'scripts'));

% 纯检查器测试，不作为 HDL 运行证据。
step7d_test_contracts;

% 本地 runtime 准备，保留已提交模型和用户 minimal SLX。
step7c_generate_foc_cosim(1e-6,true);
step7b_generate_minimal_cosim(true,false);

% 一次场景示例。报告目录须新建且属于本次运行。
r = step7d_run_scenario('speed_ideal',1,1e-6, ...
    fullfile(pwd,'docs','reports','step7d','manual_speed_ideal'));

% 最终入口自行创建独立 run ID，完成全部必要检查。
step7d_acceptance;
```

README 要明确这些命令的模型关闭前提、环境配置、错误恢复和原始数据位置。不要宣称只改 `CONTROL_BACKEND=1` 后 GUI 点击 Run 就具备全部正确配置；GUI 一键运行不是本阶段的必要交付。

## 11. Stop and report 条件

遇到以下任一情况，不得通过改数学/放宽验收继续：

- 本地用户改动与必要文件冲突，不能安全同步；缺失工具或真实 XSI 路径不能运行。
- 真实 SLX 拓扑、信号单位、Host 轨迹或控制调度与任务假设不同，现有 live reference 无法直接复用。
- untouched legacy 性能基线不满足本任务门槛，或正常运行本来就持续复位/清积分。
- 必须修改 PI、RTL、公共接口、控制周期、逆变器数学或 plant 参数才能稳定。
- 发现双重死区、额外 PWM 延迟、标签多源、任务节拍错误、非零 range flags 或 fault。
- 需要运行时全局复位/热重启才能满足额外期望；本任务只验证禁止误重启与全新仿真启动。
- 验收缺失、数值异常、轨迹窗口无效或新鲜回归无法完成。

报告应包含失败任务、实际配置、最小复现命令、原始错误/波形、已排除原因、建议最小修订。不做“先通过、以后再解释”，也不回退/删除用户工作区。

## 12. 编写依据

本任务根据 PR31 合并基线中的以下代码和文档编写；本地 SLX 内部外环实现仍必须在 Task 1 用真实 Simulink 审计。

- PR #31：`https://github.com/kazecode666/FPGA_XC7A200T_Study/pull/31`
- `coordination/HANDOFF.md`：阶段职责、唯一工作树和 Step 7D 边界。
- `docs/reports/step7c/README.md`：现有复现顺序、默认后端与 runtime 配置。
- `scripts/step7b_integrate_simple_cosim.m`：live 标签、定点类型与端口映射。
- `scripts/step7c_add_references.m`：live/scripted reference 与 run gate 选择。
- `scripts/step7c_run_scenario.m`、`step7c_check_scenario_start.m`：初始化覆盖与 Step 7C 专用断言。
- `scripts/step7c_generate_foc_cosim.m`：20ns clock、200ns reset 与数据侧 PI reset 区分。
- `scripts/step7c_acceptance.m`：必要旧回归和报告机制。
- `simulink模型/init_PMLSM_ThreeLoop_Simple.m`、`design_PMLSM_three_loop.m`：外环周期、单位、限幅与现有整定参数。
- `motor_control_ip/integration/rtl/mc_foc_pwm_top.sv`：started/needs_reset latch 与 reset_n 语义。

## 13. 给 Codex 的启动指令

```text
开始 Step 7D，按 executing-plans 执行。

先读取：
coordination/tasks/step7d_outer_loops_cosim.md
coordination/HANDOFF.md
coordination/reports/step7c_codex_report.md
docs/reports/step7c/README.md

只在 D:/Project/FPGA_XC7A200T 原始主工作树实施。
非破坏性核对 Git、本地改动和 origin/main；确认包含 PR31。
不新建 worktree/clone，不 stash/reset/clean，不覆盖或删除我的文件。

目标是复用原 Simulink 速度/位置外环，通过 live id_cmd/iq_cmd
驱动已验证 FPGA 电流环，不复制外环，不重写电流环。

先 Task 1：审计真实 SLX、记录原外环与初始化/调度语义，
抓取并提交 legacy 数值及性能基线，再做最小接入修改。

FPGA 模式必须有效为 [backend enable inputmode refmode]=[1 1 1 1]；
保留 20ns clock、100us 电流/PWM、1ms 速度、10ms 位置、
1us exchange/plant、200ns reset、PreRunTime=0。
保留唯一 plant/inverter、CMP_active/2500、现有平均死区职责。
自由运动，不锁状态，不增加行程限制。
PI_PROFILE=0，RTL/控制增益/公共接口不改。

按顺序完成配置/来源/时序检查、速度与负载、位置与负向到位、
限幅/关闭输出/禁止误重启、收敛和必要旧回归。
PI_Reset 不得当作 reset_n；重新仿真启动不得冒充热重启。
新增门槛如在原 legacy 基线就失败，先写 blocker，不自行调参或放宽。

最终生成新鲜完整验收、报告和开放实现 PR，等待 ChatGPT Review。
不要自动合并，不开始下一阶段，不生成 bitstream，不操作硬件。
```
