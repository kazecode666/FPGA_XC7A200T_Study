# Step 7C — 自由运动 PMLSM + FPGA 电流环联合仿真设计规格

**状态：设计规格，等待用户 Review。**  
**日期：2026-09-21**  
**基线：** main = `9572a73e09fa477d03bc56f22627b7599118de5f`（Step 7B / PR #28 已合并）  
**主模型：** `simulink模型/PMLSM_ThreeLoop_Simple.slx`  
**HDL 边界：** 继续采用方案 B，Simulink plant 使用 FPGA 中真正生效的 `CMP_active`，即 `D_high = CMP_active / 2500`。  
**本阶段目标：** 第一次让 Vivado/XSI 中的现有 FPGA FOC/PWM RTL **真正驱动** Simulink 平均值逆变器和可自由运动的 PMLSM plant，形成动态电流闭环。  
**本阶段不做：** 速度环/位置环闭环、JMAG/Maxwell、真实 ADC/编码器、板卡/bitstream、Vitis/SoC 迁移。

---

## 1. 设计目标

Step 7B 已经证明：

```text
Simulink HDL Cosimulation Block
        ↕
Vivado Simulator 2026.1 / XSI
        ↕
mc_foc_cosim_top
        ↓
real CMP_active
```

并把 `FPGA_HDL_Cosim` 作为**并联、不驱动 plant** 的 branch 放入 `PMLSM_ThreeLoop_Simple.slx`。

Step 7C 要跨过下一条边界：

> 将 `FPGA_HDL_Cosim` 的 active duty 真正送入平均值逆变器，同时把 plant 的动态 `ia/ib/ic/theta_e/omega_e` 反馈给 HDL，验证自由运动下电流闭环的因果链。

完成后，主链应为：

```text
direct id_ref / iq_ref test profile
        ↓
FPGA_HDL_Cosim
        ↓
Vivado/XSI: FOC → CMP → shadow → ZERO load
        ↓
CMP_active / 2500
        ↓
shared Simulink average inverter + deadtime
        ↓
PMLSM electrical + mechanical plant
        ↓
ia / ib / ic / theta_e / omega_e
        └──────────────────────────→ FPGA_HDL_Cosim
```

**电机机械状态正常积分，不锁定位置或速度。**

---

## 2. Step 7C 的验证边界

### 2.1 本轮只验证 FPGA 电流环

Step 7C 不把位置环、速度环同时带入第一版动态闭环。

当前控制层次：

```text
id_ref = 0
iq_ref = scripted current-test profile
        ↓
FPGA current loop
        ↓
free-moving PMLSM plant
```

位置和速度只是 plant 的自然响应，并作为 `theta_e` / `omega_e` 的来源。

### 2.2 不增加人工行程限制

用户已明确当前仿真不需要行程限制。

因此本阶段：

- 不增加 soft limit；
- 不增加 hard limit；
- 不钳制 `x_mm`；
- 不因为位置不断变化而冻结 plant；
- 只通过有限时长、有限幅值的电流测试避免无意义的长时间持续加速。

### 2.3 后续 Step 7D

Step 7D 才把 Simulink 速度环和位置环逐步接回：

```text
position loop
    ↓
speed loop
    ↓ iq_ref
FPGA current loop
    ↓
inverter + plant
```

Step 7C 不提前重构外环。

---

## 3. 控制后端选择

### 3.1 新增静态后端参数

定义：

```text
CONTROL_BACKEND = 0  legacy Simulink controller
CONTROL_BACKEND = 1  FPGA HDL current-loop backend
```

此选择在模型 update/compile 前确定。

**禁止在一次仿真运行过程中动态切换后端。**

原因：

- 两边 PI 积分器状态不同；
- PWM command history 不同；
- 无扰切换需要额外状态同步；
- 当前学习目标不需要 runtime backend handover。

### 3.2 使用静态 Variant，而不是普通运行时 Switch

推荐将 `FPGA_HDL_Cosim` 置于静态 Variant 选择中，使：

```text
CONTROL_BACKEND=0
    → legacy model 可不依赖 XSI runtime

CONTROL_BACKEND=1
    → 激活 FPGA HDL Cosimulation branch
```

不能仅在输出端放普通 Switch、却让 HDL Cosimulation block 在 legacy 模式下仍然初始化。

Legacy backend 必须可以在一个未生成 Step 7C XSI runtime 的新 MATLAB 会话中运行短仿真。

---

## 4. 共用一个逆变器，不复制 plant

### 4.1 原则

Step 7C 不创建第二套逆变器和第二套 motor plant。

只保留：

```text
one shared average inverter/deadtime implementation
one shared PMLSM_Plant_Model
```

Legacy 与 FPGA 的区别只发生在**逆变器命令入口之前**。

### 4.2 推荐结构

把现有 `Inverter_DeadTime` 的输入前端职责拆开：

```text
legacy controller CMP counts
        ↓
Legacy_PWM_Command_Adapter
  - existing PWM_Update_HalfTs
  - existing legacy count/polarity mapping
        ↓
legacy D_high
                         ┐
                         │
                         v
                  Backend Select
                         │
                         v
                  common D_high
                         │
                         v
               shared DeadTime model
                         │
                         v
            shared average voltage model
                         │
                         v
                  PMLSM plant
                         ^
                         │
FPGA CMP_active/2500 ----┘
```

其中 FPGA 路径：

```text
CMP_active
   ↓
double(CMP_active) / 2500
   ↓
saturate [0,1] only as interface guard
   ↓
common D_high
```

### 4.3 Legacy path 行为必须保持

`CONTROL_BACKEND=0` 时必须继续保留原 Simple 模型：

- 原 `cmp_a/b/c_counts` 语义；
- 原 `PWM_Update_HalfTs`；
- 原旧计数归一化/极性；
- 原平均 deadtime；
- 原 plant。

Step 7C 的逆变器入口重构不能破坏 legacy 参考路径。

---

## 5. FPGA backend 必须旁路的旧逻辑

### 5.1 旁路 legacy PWM update delay

当前 Simple 模型 legacy 路径已有 `PWM_Update_HalfTs`，包含：

```text
command ZOH at Ts = 100 us
+
half-period delay at Ts/2 = 50 us
```

FPGA RTL 已经真实实现：

```text
sample at carrier phase
 → FOC latency
 → CMP shadow
 → next physical ZERO
 → CMP_active
```

因此 `CONTROL_BACKEND=1` 下：

```text
legacy PWM_Update_HalfTs = BYPASS
```

不得再增加 50 us 或 100 us 命令延迟。

### 5.2 旁路 legacy count/polarity mapping

FPGA 输出：

```text
D_high = CMP_active / 2500
```

已经是逻辑上管 HIGH fraction。

不得再经过 legacy：

```text
count → scale → polarity inversion
```

不能为了适配旧接口，把 FPGA duty 反算成“伪 DSP counts”。

---

## 6. Deadtime 责任

### 6.1 当前 average-plant 主链的唯一 deadtime

在 Step 7C：

```text
Simulink average inverter owns deadtime effect
```

FPGA Step 6E 的六路 gate / 500 ns deadtime：

```text
not used to drive the average plant
```

避免 double deadtime。

### 6.2 两个场景

第一版动态闭环至少跑：

**Scenario A — ideal inverter**

```text
PMLSM_deadtime_s = 0
```

用于建立控制方向和动态基线。

**Scenario B — existing average deadtime**

```text
PMLSM_deadtime_s = 1 us
PMLSM_deadtime_ratio = PMLSM_deadtime_s / Ts = 0.01
```

用于观察当前 Simple 模型平均 deadtime 对闭环的影响。若测试脚本通过 `SimulationInput` 覆盖 deadtime，必须同时重算/覆盖 ratio，不能只改 `PMLSM_deadtime_s` 留下旧 ratio。

不把 RTL 500 ns 参数改成 1 us，也不把 Simulink 1 us 改成 500 ns来“统一数字”。二者属于不同抽象层。

---

## 7. 动态反馈来源

`CONTROL_BACKEND=1` 时，HDL 输入必须来自当前正在运行的 plant：

| HDL input | Step 7C source |
|---|---|
| `ia` | `PMLSM_Plant_Model` phase-a current |
| `ib` | `PMLSM_Plant_Model` phase-b current |
| `ic` | `PMLSM_Plant_Model` phase-c current |
| `theta_e` | plant 当前 electrical angle |
| `we` | plant 当前 electrical angular speed |
| `vdc` | Simple model current DC-bus command/parameter |
| `id_ref` | Step 7C direct current-test reference |
| `iq_ref` | Step 7C direct current-test reference |
| `run_enable` | FPGA backend enable + PWM enable |
| `pi_reset` | explicit controller reset policy |
| `uq_zero_en` | normal dynamic tests = 0 |

### 7.1 不重复重算 angle/speed

如果 Simple model 已提供：

```text
theta_e_actual
omega_e
```

优先直接使用这些 plant 输出。

不要同时再用 `x_mm` / `v_mmps` 计算另一份 theta/we 并混用。

### 7.2 仍保持三电流采样

继续传：

```text
ia
ib
ic
```

不在 Step 7C 改成两电流重构。

---

## 8. 参考值来源

### 8.1 拆分“反馈来源”和“参考来源”

保留 Step 7B：

```text
FPGA_Cosim_Input_Mode = 0
    fixed smoke
```

新增清晰语义：

```text
FPGA_Cosim_Input_Mode = 1
    live plant feedback
```

再定义：

```text
FPGA_Reference_Mode = 0
    Step 7C scripted current test

FPGA_Reference_Mode = 1
    future host/outer-loop reference
```

Step 7C accepted dynamic tests 使用：

```text
FPGA_Cosim_Input_Mode = 1
FPGA_Reference_Mode   = 0
```

### 8.2 Step 7C 电流测试 profile

默认动态 profile：

```text
0.0 ms  →  1.0 ms     iq_ref =  0.0 A
1.0 ms  → 11.0 ms     iq_ref = +0.5 A
11.0 ms → 16.0 ms     iq_ref =  0.0 A
16.0 ms → 26.0 ms     iq_ref = -0.5 A
26.0 ms → 31.0 ms     iq_ref =  0.0 A

id_ref = 0 A throughout
vdc    = 48 V nominal
load   = 0 N nominal
```

该 profile 必须由可复现的脚本/From Workspace/测试子系统生成，不依赖人工拖动 Scope 或 GUI 改常数。

### 8.3 为什么不长时间恒定 iq

当前 plant 默认：

```text
Bv = 0
Fc = 0
```

长时间恒定 q 电流会持续施加净推力并持续加速。

有限脉冲既能让 motor 真正运动，又避免无意义的长时间速度增长。

---

## 9. FPGA PI 参数策略

Step 7C 默认使用：

```text
PI_PROFILE = 0
```

保持 Step 6D/6E/7B 已验收的 FPGA PI 参数。

**本阶段不重新调 PI。**

当前 Simple legacy controller 的电流 PI 整定与 HDL profile0 不同，所以：

- 不把两种 backend 的曲线逐点一致作为验收；
- 不因为上升时间不同就修改 RTL；
- legacy backend 只用于回归模型结构和方向参考；
- 如以后要公平对比，再单独统一 gains / AW / initial state / delay。

---

## 10. Backend enable / stop / fault 语义

### 10.1 FPGA bridge enable

FPGA backend 的 `run_enable` 只由 PWM/backend enable 语义决定，不能被 legacy speed/position loop enable 隐式控制。

定义：

```text
fpga_bridge_enable =
    PWM_EN
    && active_valid
    && !needs_reset
    && (fault_code == 0)
```

第一笔实际 active command 出现之前：

```text
fpga_bridge_enable = 0
```

因此不会把复位后的 `CMP_active=0` 当成有效电压命令。

### 10.2 Stop / fault

若：

```text
PWM_EN = 0
or needs_reset = 1
or fault_code != 0
```

则 shared average inverter 进入 disabled 状态，当前 Step 7C 继续使用现有 average-model zero-voltage shutdown approximation。

不自动重启。

每个 acceptance scenario 从新的 simulation/reset state 开始。

### 10.3 物理边界说明

这个 disabled 行为是**平均模型近似**，不是：

- 真实六个 IGBT/MOSFET 关断验证；
- 二极管续流细节；
- 母线回灌；
- 驱动器硬件 trip。

---

## 11. 通信与 plant 数值时间尺度

### 11.1 Step 7B 已知问题

Step 7B 使用：

```text
co-sim communication = 50 us
```

实际 FPGA active load 在约 `100.2 us` 已发生，但 Simulink 直到 `150 us` 的通信网格才看到它。

作为 monitor 没问题，但作为 actuation 会多引入接近 50 us 的额外延迟。

### 11.2 Step 7C reference timing

Step 7C accepted reference configuration：

```text
HDL clock                     = 20 ns / 50 MHz
PWM / current transaction     = 100 us / 10 kHz
Simulink↔HDL communication    = 1 us
plant electrical/mechanical step = 1 us
physical timescale            = 1:1
XSI reset                     = 200 ns
PreRunTime                    = 0
```

**控制周期仍然是 100 us。**

1 us 只是：

- plant 积分步长；
- Simulink↔HDL 数据交换粒度；
- active CMP 施加到 average inverter 的时间量化。

### 11.3 Expected first-cycle relation

当前 reset/clock 相位下，预期关系约为：

```text
plant/input update grid      50.000 us
HDL first sample accept     ~50.22 us
actual first active load    ~100.20 us
Simulink sees/applies duty  ~101.00 us
```

这只是已知时序的设计预期。

Step 7C 必须重新实测，不得把这些近似数字当作硬编码 PASS 条件。

### 11.4 1 us 配置必须参数化所有相关位置

不能只改 model `FixedStep`。

必须统一：

- Simulink solver/fixed-step；
- plant discrete integrator sample times；
- HDL Cosimulation block input/output sample time；
- generated block `PortTimes`；
- Step 7C data/logging sample period。

`Ts_ACR=100 us` 不允许跟随 plant step 一起变成 1 us。

---

## 12. 数值收敛检查

### 12.1 0.5 us 短时 convergence probe

在 1 us reference scenario 跑通后，对 Scenario A 再运行：

```text
communication / plant step = 0.5 us
```

比较 1 us 与 0.5 us：

- `id`；
- `iq`；
- `v_mmps`；
- `x_mm`。

建议 acceptance：

```text
max |iq_1us - iq_0.5us| < 0.05 A
max |id_1us - id_0.5us| < 0.05 A
max |v_1us - v_0.5us|   < 2 mm/s
max |x_1us - x_0.5us|   < 0.02 mm
```

如果任一超限：

- 不为了通过测试而放宽到很大；
- 先检查 sample/apply timing；
- 再判断 1 us 是否不足。

### 12.2 10 us 不是 acceptance reference

可以在本阶段末尾作为运行速度 benchmark 额外测试 10 us，但：

- 不能用它替代 1 us reference acceptance；
- 不能在没有 timing/performance evidence 时把默认改为 10 us。

---

## 13. 自由运动 dynamic current-loop acceptance

### 13.1 Scenario A — ideal inverter

条件：

```text
CONTROL_BACKEND = FPGA
PI_PROFILE = 0
PMLSM_deadtime_s = 0
FPGA_Cosim_Input_Mode = 1
FPGA_Reference_Mode = 0
id_ref = 0
iq pulse profile = 0 / +0.5 / 0 / -0.5 / 0 A
vdc = 48 V
load = 0 N
```

必须满足：

- plant `ia/ib/ic` 真正进入 HDL；
- `theta_e` 随位置变化；
- `omega_e` 在 motor 运动后非零；
- accepted/active command 持续更新；
- `fault_code=0`；
- `needs_reset=0`；
- fixed-point range/saturation flags 为 0；
- positive q-current pulse 时 motor 朝正方向加速；
- negative q-current pulse 时加速度方向反转；
- `iq` 在 +0.5 A 阶段至少达到 +0.25 A；
- `iq` 在 -0.5 A 阶段至少达到 -0.25 A；
- `|id| < 0.5 A` 全程；
- `|iq| < 2.0 A` 全程；
- 无 NaN/Inf。

### 13.2 Scenario B — 1 us average deadtime

与 Scenario A 相同，但：

```text
PMLSM_deadtime_s = 1 us
```

必须：

- 保持稳定闭环；
- fault/reset/range flags 正常；
- 记录 deadtime 开/关两组：
  - q-current tracking error；
  - id cross-axis error；
  - peak speed；
  - final position；
  - active duty 波形。

不要求两组完全相同。

### 13.3 Scenario C — stop during free motion

使用 Scenario A 的自由运动状态，在 motor 已有非零速度和非零 electrical angle 时关闭 `PWM_EN`。

必须：

- average inverter 停止应用有效 FPGA duty；
- `active_valid` 进入无效；
- `fpga_bridge_enable=0`；
- plant 电流按当前 average-model disabled 语义自然变化；
- 旧 active CMP 可以作为历史状态保留，但不能以 enabled 状态继续驱动 plant；
- 不要求无 reset 自动恢复；
- 无 NaN/Inf。

本阶段不把 voltage-saturation/anti-windup 压力测试列为必须验收项。等第一版自由运动闭环稳定后，再单独增加更高参考或低母线场景。

---

## 14. 需要记录的波形和指标

### 14.1 Control performance

至少记录：

```text
id_ref
id_plant
iq_ref
iq_plant
```

测量：

- positive step rise time；
- negative step response；
- peak overshoot；
- steady tracking error；
- max |id|；
- stop 后 current decay / response。

### 14.2 Mechanical motion

至少记录：

```text
x_mm
v_mmps
theta_e
omega_e
```

需要证明：

- motor 确实移动；
- positive/negative q command 对运动方向的影响一致；
- theta/we 是动态 plant feedback，不是固定 smoke 值。

### 14.3 FPGA actuation

至少记录：

```text
accepted_sample_id
active_command_id
active_valid
CMP_active_u/v/w
D_high_u/v/w
fpga_bridge_enable
fault_code
needs_reset
```

### 14.4 Shared inverter output

至少记录：

```text
inverter vd/vq or equivalent alpha/beta voltage
deadtime mode/value
backend selected
```

用来确认 FPGA backend 不是只计算了 duty 而没有真正施加到 plant。

---

## 15. Step 7C 模型结构建议

建议把 Step 7B 的顶层逐步整理成：

```text
PMLSM_ThreeLoop_Simple
│
├─ Simple_Host
│
├─ Control_Task_10kHz                  # legacy controller remains
│
├─ Controller_Backend                  # static variant
│   ├─ Legacy_Command_Backend
│   │    └─ legacy counts/update mapping
│   └─ FPGA_Command_Backend
│        └─ FPGA_HDL_Cosim
│             ├─ FPGA_Input_Adapter
│             ├─ HDL_Cosimulation
│             ├─ FPGA_Output_Adapter
│             └─ FPGA_Cosim_Monitor
│
├─ Inverter_DeadTime                   # common normalized-duty/deadtime core
│
└─ PMLSM_Plant_Model                   # one shared free-moving plant
```

### 15.1 FPGA branch outputs

Step 7C 中 `FPGA_HDL_Cosim` 不再是无输出 monitor-only subsystem。

至少正式输出：

```text
fpga_duty_u
fpga_duty_v
fpga_duty_w
fpga_bridge_enable
active_command_id
fault / status for logging
```

但对 shared inverter 的正式控制输入只有：

```text
duty_u/v/w
bridge_enable
```

### 15.2 不把 debug/status 混入逆变器数学

`active_command_id`、fault、range flags 只用于：

- logging；
- assertion；
- enable gating。

不能被当成电压计算的一部分。

---

## 16. Legacy regression

由于 Step 7C 会重构 inverter command front-end，必须先保存并复测 legacy backend。

### 16.1 Before-change baseline

实现前用当前 main 跑一段固定短场景，记录：

```text
legacy cmp_a/b/c
duty before deadtime
inverter vd/vq
ia/ib/ic
x_mm
v_mmps
```

### 16.2 After-change backend=0

`CONTROL_BACKEND=0` 重跑同场景。

要求：

- 原旧 control-to-inverter 路径语义保持；
- 不需要 XSI runtime；
- 关键波形在浮点数值误差范围内一致。

建议：

```text
max abs voltage/current/state difference <= 1e-10
```

若因模型 block 调度重构产生不可避免但可解释的 floating ordering 差异，则必须在报告中给出最大差异和原因，不能直接删掉 legacy regression。

---

## 17. Step 7B 回归保留

Step 7C 不能破坏 Step 7B 结果。

最终至少重跑：

```text
Step 7B minimal Simulink HDL Cosimulation
Step 7B standalone wrapper
Step 6D profile0 DEMO=0
Step 6E profile0 DEMO=0
```

不要求再跑所有 profile1、大规模 route。

若 Step 7C 没修改 RTL，则重点是证明：

- generated HDL block 仍可加载；
- interface metadata 没被模型重构破坏；
- 旧 FPGA smoke 仍可用作诊断模式。

---

## 18. 失败处理原则

Step 7C 第一次闭环可能暴露真实系统问题。

若发生：

### 18.1 电流发散

先检查顺序：

```text
duty polarity
→ phase order
→ theta sign/units
→ omega_e sign/units
→ current feedback sign
→ duplicated update delay
→ duplicated deadtime
→ communication apply timing
→ PI/profile
```

禁止第一反应就重调 PI。

### 18.2 Motor 运动方向相反

先检查：

- q-axis convention；
- phase sequence；
- electrical angle direction；
- plant force sign。

不要通过交换 U/V/W 相线或对最终 duty 做临时负号来掩盖接口错误。

### 18.3 HDL fault

保留第一处 root cause：

- invalid vdc；
- protocol deadline；
- missing sample；
- range overflow。

不要绕过 fault logic 来强行闭环。

---

## 19. 实施边界

Step 7C 允许：

- 修改 `PMLSM_ThreeLoop_Simple.slx`；
- 修改/新增 Step 7C Simulink scripts；
- 修改 Step 7B generator/output sample-time 参数；
- 小范围修改 co-sim wrapper monitor ports（仅当动态 timing 观测确有必要）；
- 新增 backend/variant/legacy adapter；
- 新增动态 current-loop test profiles；
- 保存图、CSV/TXT/Markdown 报告；
- GitHub 同步和实现 PR。

Step 7C 不允许：

- 修改 C1–C4 算法以“让闭环好看”；
- 重调 FPGA PI 作为首选修复；
- 修改 Step 6E gate deadtime 来匹配 average deadtime；
- 增加位置限制；
- 接入速度/位置闭环；
- 接入 JMAG/Maxwell；
- FPGA board/FIL/bitstream；
- Vitis/PS 软件；
- 产品级保护策略。

---

## 20. 完成定义

Step 7C 完成意味着：

> 在 `PMLSM_ThreeLoop_Simple.slx` 中选择 FPGA backend 后，Vivado/XSI 中的现有 FOC/PWM RTL 使用自由运动 PMLSM plant 的动态三相电流、electrical angle 和 electrical speed 进行闭环计算；真实 `CMP_active` 经 `/2500` 后绕过 legacy PWM-update/count mapping，进入同一套 Simulink average inverter/deadtime 和 motor plant；电机在有限 q-current profile 下产生可解释的实际运动，电流能够双向跟踪，且不存在重复 deadtime、重复 PWM delay 或约 50 us 的额外 co-sim actuation delay。

Step 7C **不意味着**：

- 三闭环已完成；
- FPGA 参数已经最终优化；
- average deadtime 等价真实 gate switching；
- board hardware 已验证。

---

## 21. Step 7D 入口

Step 7C 接受后，Step 7D 才开始：

```text
Simulink position/speed outer loops
             ↓
        id_ref / iq_ref
             ↓
      FPGA current loop
             ↓
  average inverter + plant
```

届时优先复用 Step 7C 已冻结的：

- `CONTROL_BACKEND`；
- normalized active-duty boundary；
- FPGA live feedback adapter；
- 1 us reference co-sim timing；
- shared inverter/deadtime core；
- dynamic logging infrastructure。

不会再重新定义一套 Simulink↔HDL 接口。
