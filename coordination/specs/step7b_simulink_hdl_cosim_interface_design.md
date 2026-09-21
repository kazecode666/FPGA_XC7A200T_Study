# Step 7B — Simulink ↔ Vivado HDL Cosimulation 接口设计规格

**状态：设计规格，等待用户 Review。**  
**日期：2026-09-21**  
**基线：** main = `c07792fd55e175f7dae2a94ffe5b2c19093b1513`（Step 7A / PR #25 已合并）  
**目标路线：** 采用 **方案 B：以 FPGA 中实际生效的 `CMP_active` / active duty 作为 Simulink 平均值逆变器的控制边界**。  
**本阶段性质：** 工具链与接口集成，不做电机动态闭环验收。  
**主 Simulink 集成模型：** `simulink模型/PMLSM_ThreeLoop_Simple.slx`。该模型是用户此前将真实 DSP 控制逻辑做功能简化后保留的三闭环仿真副本，保留核心控制算法、平均值逆变器/死区和 PMLSM plant，删除了大量当前 FPGA 联调不需要的控制接口与观测系统。Step 7B/7C 优先基于它搭建，不再以完整 `PMLSM_MIL_ControlCore_Sim.slx` 作为主改造对象。

**环境补充：** 用户在 Step 7A 合并后已安装 SoC Blockset Support Package for AMD FPGA and SoC Devices。Step 7B 启动时只需用 R2026b 重新确认该 support package 已被当前 release 识别并记录版本；这不是重新做 7A。纯 Vivado Simulator/XSI co-sim 仍以 HDL Verifier 产品能力为准，support package 识别失败时应报告，但不应据此伪造或绕过 simulator 测试结果。

---

## 1. 设计目标

Step 7B 要把 Step 7A 的“MATLAB System Object ↔ Vivado XSI 最小联合仿真已经打通”推进到一个可长期复用的 **Simulink HDL Cosimulation 接口架构**，并证明现有 FOC/PWM RTL 可以由 Simulink HDL Cosimulation Block 驱动。

本阶段必须完成四件事：

1. **Simulink HDL Cosimulation Block 最小联通**  
   使用一个独立小 HDL 示例，真实跑通：
   ```text
   Simulink
      ↕
   HDL Cosimulation Block
      ↕
   HDL Verifier
      ↕
   Vivado Simulator 2026.1 / XSI
   ```

2. **建立专用的 FOC co-sim RTL 包装层**  
   新增 `mc_foc_cosim_top`，复用已验收 `mc_foc_pwm_top`，屏蔽 50 MHz 内部握手细节，向 Simulink 暴露稳定、可采样的 active compare 结果和状态。

3. **建立 FOC co-sim smoke model**  
   由 Simulink HDL Cosimulation Block 用固定已知输入驱动完整 FOC→CMP→PWM 装载链，确认第一笔实际生效的 `CMP_active` 与 Step 6D 已验收值一致。

4. **冻结后续 7C 的 Simple model 接口边界**  
   以 `PMLSM_ThreeLoop_Simple.slx` 为主模型，明确其中 `Simple_Host`、`Control_Task_10kHz`、`Inverter_DeadTime`、`PMLSM_Plant_Model` 以及信号标签之间哪些保留、替换、旁路，并把 deadtime、PWM update delay、采样、定点转换、时间同步的责任分配写死。

5. **把本地 Simple 模型纳入 GitHub 可追踪基线**  
   当前 GitHub `main` 尚未包含 `PMLSM_ThreeLoop_Simple.slx`。Codex 实施 7B 时必须先从原始 MAIN 中读取该本地文件，记录结构并在修改前作为第一笔基线提交纳入实现分支；后续模型修改、脚本、RTL wrapper 和报告必须继续提交/推送到 GitHub，实现 PR 不能只留下本地结果。

Step 7B **不闭合电机电流环**。动态 plant 闭环留给 Step 7C。

---

## 2. 用户授权与模型保护范围

### 2.1 允许直接修改项目中的 Simulink 副本

用户已明确：仓库/本地主项目 `simulink模型/` 下的模型是可修改副本，Codex 可以直接改。

**Step 7B 的主对象：**

```text
simulink模型/PMLSM_ThreeLoop_Simple.slx
```

该 Simple 模型从用户截图和描述可见的顶层主链为：

```text
Simple_Host
   │ refs / enable / reset / load
   v
Control_Task_10kHz
   │ cmp_a/b/c_counts
   v
Inverter_DeadTime
   │ vd / vq
   v
PMLSM_Plant_Model
   │ ia / ib / x_mm / v / theta_e / omega_e
   └────────────── feedback tags ──────────────> Control_Task_10kHz
```

Step 7B 优先围绕这条简化主链增加 FPGA co-sim 接口。

完整模型：

```text
simulink模型/PMLSM_MIL_ControlCore_Sim.slx
simulink模型/PMLSM_ControlCore_Block.slx
```

降级为**参考模型/算法来源**。除非实施中发现 Simple 模型缺少必须的参数或 block 需要对照，否则 7B 不主动修改它们。

参数脚本 `simulink模型/init_PMLSM_*.m` 可按当前阶段需要小范围修改或新增 co-sim 参数文件，但不做无关重构。

### 2.2 外部原始模型目录继续只读

以下外部目录不是当前仓库实施目录：

```text
D:/Project/PMSLM_Simulation
```

Codex 可以读取和对照，但 **不得在 Step 7B 修改该目录中的源模型**。

### 2.3 Vivado 工程与历史 RTL 基线

保留：

```text
FOC_Current/
FOC_PWM/
FOC_Gates/
```

历史 C1–C4、PWM、gate RTL 和参考向量默认只读。  
仅允许为 co-sim 增加新的 wrapper，以及本规格明确授权的只读监视端口扩展。


### 2.4 本地 Simple 模型与 GitHub 同步规则

截至本规格修订时，GitHub `main` 的 `simulink模型/` 目录尚未出现 `PMLSM_ThreeLoop_Simple.slx`，因此它应视为用户原始 MAIN 中的本地新增文件，而不是远端已有基线。

Codex 开始实施时必须：

1. 在 `D:/Project/FPGA_XC7A200T/simulink模型/PMLSM_ThreeLoop_Simple.slx` 核对真实文件；
2. 用 MATLAB/Simulink API 只读导出顶层 block inventory、solver、sample time、InitFcn 和关键 subsystem path；
3. **在任何功能修改之前**，把 as-found 的 Simple 模型作为独立 baseline commit 加入 7B 实现分支；
4. 后续改动再用后续 commit 提交，使 Git 历史能区分“用户原始简化模型”和“FPGA co-sim 改造”；
5. 推送实现分支并创建 GitHub PR，不能只更新本地 D 盘模型；
6. 不把 `.slxc`、`slprj`、Vivado/MATLAB cache 或系统 TEMP 产物整体提交。

如果本地实际文件名、模型引用或依赖与用户描述不一致，先报告并以真实文件为准，不凭截图复制模型。

---

## 3. 选择方案 B 的原因

### 3.1 方案 B 的联合仿真边界

```text
Simulink plant
      ↑
D_high_u/v/w = CMP_active / 2500
      ↑
Vivado HDL
FOC → SVPWM → duty adapter → PWM shadow → ZERO → CMP_active
```

`CMP_active` 表示当前 PWM 周期真正生效的上管 HIGH 比例对应比较值。

已有关系：

```text
TBPRD = 2500
D_high = CMP_active / 2500
```

### 3.2 不使用 raw C4 duty

如果直接把 C4/SVPWM 刚算出的调制量送给 Simulink，会绕过：

- `d_foc -> D_high` 极性适配；
- CMP 量化；
- shadow；
- 下一 ZERO 原子装载；
- 已验收的采样→计算→应用时序。

因此不采用。

### 3.3 不使用六路 gate 作为当前平均值逆变器输入

Step 6E 的 `UH/UL/VH/VL/WH/WL` 用于逻辑门极与 deadtime 验证。  
当前 Simulink plant 使用平均值逆变器，并已有 deadtime 等效模型。

如果把六路 gate 再换算后送入“带 deadtime 的平均值逆变器”，容易重复计算 deadtime。

所以：

```text
7B/7C 主链：使用 CMP_active
Simulink 平均逆变器：负责平均 deadtime 效应
RTL 六路 deadtime：保留，但不进入 plant 主链
```

以后若改成器件级/开关级逆变器模型，再重新定义 gate 边界。

---

## 4. Step 7B 总体架构

Step 7B 采用“**Simple 模型作为集成骨架，FPGA branch 先并联观察、不抢 plant 控制权**”的方式：

```text
PMLSM_ThreeLoop_Simple.slx

Simple_Host
     │
     ├──────────────────────────────┐
     │                              │
     v                              v
existing Control_Task_10kHz    FPGA_HDL_Cosim (new, 7B)
     │ cmp counts                   │ fixed-point inputs
     │                              v
     │                       HDL Cosimulation Block
     │                              │
     │                       mc_foc_cosim_top
     │                              │
     │                       CMP_active + command_id
     │                              │
     │                         log / assertion only
     │
     v
Inverter_DeadTime  <── 7B 仍由 existing controller 驱动
     │
     v
PMLSM_Plant_Model
     │
     └── ia/ib/x/v/theta/we feedback
```

因此 7B 可以直接在用户简化三闭环模型里搭好未来 FPGA backend，但不改变当前 plant 的默认控制源。

Step 7C 再把：

```text
FPGA_HDL_Cosim.CMP_active / 2500
```

通过明确的 backend selector 接到 `Inverter_DeadTime`，并旁路旧 count polarity / PWM update delay。

仍保留一个独立的最小 counter model 来证明 Simulink HDL Cosimulation Block 本身能工作，但**不再新增第二个完整 FOC smoke SLX**。完整 FOC smoke 直接在 `PMLSM_ThreeLoop_Simple.slx` 的并联 `FPGA_HDL_Cosim` subsystem 中完成。

---

## 5. 新 co-sim RTL 包装层

新增：

```text
motor_control_ip/integration/rtl/mc_foc_cosim_top.sv
```

### 5.1 设计职责

`mc_foc_cosim_top` 只负责：

- 复用现有 `mc_foc_pwm_top`；
- 自动响应内部 sample request；
- 将 Simulink 持续提供的输入在真实 FOC 接受边沿用于计算；
- 将窄脉冲事件转换成长期可观察状态/计数；
- 暴露实际生效的 active CMP。

不得：

- 复制 FOC；
- 复制 PWM carrier；
- 改 PI/SVPWM 数学；
- 自己重新计算 duty；
- 绕过 shadow/ZERO；
- 引入另一套 deadtime。

### 5.2 输入接口

```systemverilog
input  logic                    clk;
input  logic                    reset_n;
input  logic                    run_enable;

input  logic signed [23:0]      ia;
input  logic signed [23:0]      ib;
input  logic signed [23:0]      ic;
input  logic        [15:0]      theta_e;
input  logic signed [31:0]      we;
input  logic signed [24:0]      id_ref;
input  logic signed [24:0]      iq_ref;
input  logic signed [24:0]      vdc;

input  logic                    pi_reset;
input  logic                    uq_zero_en;
```

格式保持现有 RTL：

| Signal | RTL format |
|---|---|
| ia/ib/ic | S24/F15 |
| theta_e | U16 binary angle |
| we | S32/F16 |
| id_ref/iq_ref/vdc | S25/F15 |
| enable/reset | Boolean |

### 5.3 sample_valid 不再由 Simulink 产生

Simulink 不负责追踪几十 ns 的 `sample_request` 窗口。

wrapper 内部采用：

```text
sample_valid_internal = sample_request_internal
```

因此只要 Simulink 输入在采样事件附近保持稳定，已有 6D 调度器会在合法峰值窗口自动接受样本。

wrapper 必须继续检查/输出 fault 状态，不得通过强行恒 1 sample_valid 破坏原协议。

### 5.4 输出接口

至少输出：

```systemverilog
output logic [11:0] cmp_u_active;
output logic [11:0] cmp_v_active;
output logic [11:0] cmp_w_active;

output logic [31:0] accepted_sample_id;
output logic [31:0] active_command_id;
output logic        active_valid;

output logic        needs_reset;
output logic [2:0]  fault_code;
```

可另外输出少量 debug：

```text
sample_event
load_event
pwm_u/pwm_v/pwm_w
```

但 Simulink plant 的正式控制边界只依赖：

```text
cmp_u_active
cmp_v_active
cmp_w_active
active_valid
active_command_id
needs_reset
fault_code
```

### 5.5 事件转状态

`accepted_sample_id`：

- 每次实际 accepted transaction 加 1；
- wrapper 可使用 `sample_request && sample_ready`，因为内部 sample_valid 与 request 同步生成；
- reset 清 0。

`active_command_id`：

- 每次 `pwm_command_loaded` 加 1；
- reset 清 0；
- 不输出只有 20 ns 的“必须被 Simulink 捕获”的事件作为唯一依据。

`active_valid`：

- reset 后为 0；
- 第一笔实际 `pwm_command_loaded` 后为 1；
- `run_enable=0`、`needs_reset=1` 时清 0；
- 下一次恢复必须经过 reset 和新命令装载。

---

## 6. 唯一授权的旧 RTL 监视接口扩展

当前 `mc_foc_pwm_top` 内部已有：

```text
cmp_u_active
cmp_v_active
cmp_w_active
```

但未导出。

Step 7B 授权增加三个**只读监视输出**，不增加寄存器、不改变计算/载波/装载行为，例如：

```systemverilog
output logic [11:0] cmp_u_active_mon;
output logic [11:0] cmp_v_active_mon;
output logic [11:0] cmp_w_active_mon;

assign cmp_u_active_mon = cmp_u_active;
assign cmp_v_active_mon = cmp_v_active;
assign cmp_w_active_mon = cmp_w_active;
```

旧 TB 中所有使用 `dut(.*)` 的实例必须补齐对应声明。

新增端口后必须重新跑原 6D 回归，证明行为不变。

不允许使用可综合的跨层引用：

```text
control.pwm.cmp_u_active
```

作为长期 wrapper 接口。

---

## 7. Simulink fixed-point 输入适配

### 7.1 原则

Simulink plant 和外环继续使用物理单位 double。  
进入 HDL Cosimulation Block 前显式量化为 RTL 格式。

不把 RTL 接口改成浮点。

### 7.2 输入换算

```text
ia_fp = quantize(ia_A, S24/F15)
ib_fp = quantize(ib_A, S24/F15)
ic_fp = quantize(ic_A, S24/F15)

theta_u16 = modulo(theta_e_rad, 2*pi) * 65536/(2*pi)

we_fp = quantize(we_radps, S32/F16)

id_ref_fp = quantize(id_ref_A, S25/F15)
iq_ref_fp = quantize(iq_ref_A, S25/F15)
vdc_fp    = quantize(vdc_V,    S25/F15)
```

### 7.3 推荐 Simulink 数据类型

```text
ia/ib/ic      fixdt(1,24,15)
theta_e       fixdt(0,16,0)
we            fixdt(1,32,16)
id_ref/iq_ref fixdt(1,25,15)
vdc           fixdt(1,25,15)
```

转换必须：

- 饱和而非 wrap；
- 明确 rounding；
- 记录溢出/饱和；
- smoke 用例必须选择无需争议 rounding 的精确可表示值。

### 7.4 angle adapter

`theta_e` 必须在适配器中完成：

```text
x_mm / ideal angle
 -> theta_e_rad
 -> wrap [0, 2*pi)
 -> U16 binary angle
```

后续 plant 使用：

```text
theta_e_rad = mod(2*pi*x_mm/60 + theta_offset, 2*pi)
we_radps    = 2*pi*v_mmps/60
```

其中位置/速度单位均按现有 PMLSM 约定换算。

---

## 8. Simulink 输出适配

### 8.1 active duty

只有 `active_valid=1` 时，正式 plant duty 定义为：

```text
duty_u = cmp_u_active / 2500
duty_v = cmp_v_active / 2500
duty_w = cmp_w_active / 2500
```

范围应为 0..1。

### 8.2 inactive / fault

若：

```text
active_valid = 0
or needs_reset = 1
```

则不能继续把旧 `CMP_active` 当成新的有效驱动命令。

Step 7B smoke 只检查状态；  
Step 7C 接 plant 时再冻结平均逆变器“disabled”的续流/关断语义。

不得把“bridge disabled”简单解释为三个 duty 都为 0 后就宣称等于真实三相桥全关。

---

## 9. HDL Cosimulation Block 时钟与时间尺度

### 9.1 HDL 时钟

Vivado co-sim 中：

```text
clk: 50 MHz
period = 20 ns
active edge = rising
```

`clk` 在 Cosimulation Wizard 中标记为 **Clock**，由 HDL Verifier/Vivado simulator 产生，不要求 Simulink 以 20 ns 步长显式翻转。

`reset_n` 标记为 **Reset**：

- initial value = 0；
- active-low；
- duration 取多个 50 MHz 周期，例如 200 ns；
- reset 释放后 run_enable 可保持 1。

### 9.2 物理时间保持 1:1

采用 absolute timing：

```text
1 second Simulink = 1 second HDL
```

即：

```text
TimeScale = {1, 's'}
```

Step 7B 要实际读取生成 block 的 timescale/clock summary，不能只设置后假定成功。

### 9.3 Simulink ↔ HDL 交换周期

FOC smoke 的目标通信步长：

```text
50 us
```

这是 carrier 半周期：

```text
ZERO ---------- PEAK ---------- ZERO
0 us            50 us           100 us
```

HDL simulator 在两个 Simulink sample hit 之间自行运行 2500 个 50 MHz 时钟。

这并不意味着 Step 7C plant 的所有连续动力学都必须用 50 us 固定步长；7C 可根据 plant solver 重新评估。但 co-sim 边界至少每 50 us 有一个离散交换点。

### 9.4 边沿排序必须实测

不能仅根据文档假定：

```text
Simulink 在 50 us 更新输入
vs
HDL carrier peak 在 50 us 采样
```

的 scheduler 顺序。

Step 7B 必须增加一个 timing alignment test：

- 让 Simulink 在相邻 50 us hit 改变一个可观察输入；
- 使用 accepted_sample_id / 首次命令结果确认哪一个值实际被 FOC 捕获；
- 记录 input apply 与 HDL active clock edge 的顺序；
- 如需要，使用 Wizard 提供的 clock edge offset / timing suggestion 方式消除零时刻竞争。

最终必须写出一个明确契约：

```text
第 k 个 Simulink 50 us 输入值
在哪个 HDL sample transaction 生效
```

不得把 scheduler race 留给 7C。

---

## 10. 最小 Simulink HDL Cosimulation Block 证明

在接完整 FOC 前先建立：

```text
simulink模型/PMLSM_HDL_Cosim_Minimal.slx
```

使用 Step 7A 的简单 HDL counter 或等价寄存器：

```text
in_data -> HDL -> out_data = in_data + 1
```

要求：

- 使用 **Simulink HDL Cosimulation Block**，不是 MATLAB System Object；
- Vivado Simulator 2026.1；
- 由 Cosimulation Wizard 生成 Vivado block / DLL workflow；
- 输入至少 0、1、42、127、254、255；
- 检查 255→0；
- reset 真正作用；
- 保存模型、生成 block 所需配置和可复现步骤；
- 不把 TEMP/cache 大量提交仓库。

成功标记示例：

```text
STEP7B_SIMULINK_MINIMAL_COSIM_PASS
```

这一步失败则不继续完整 FOC smoke。

---

## 11. Simple 模型中的 FOC co-sim smoke branch

Step 7B **不再创建** `PMLSM_FOC_HDL_Cosim_Smoke.slx`。

FOC smoke 直接落在：

```text
simulink模型/PMLSM_ThreeLoop_Simple.slx
  /FPGA_HDL_Cosim
```

这个新 subsystem 在 7B 中与现有 `Control_Task_10kHz` **并联观察**，不驱动 `Inverter_DeadTime`。

### 11.1 HDL DUT

顶层：

```text
mc_foc_cosim_top
```

HDL source 使用仓库现有 C1–C4、adapter、motor_pwm_core 及 wrapper。

不使用 Step 6E gate layer 作为 plant 接口。

### 11.1.1 HDL source / ROM staging

FOC smoke 必须使用仓库真实 RTL source set，保持 package 编译依赖顺序可解析。特别注意 `mc_sincos_lut.sv` 当前通过：

```text
$readmemh("sin_qw_4096x18.mem", ...)
```

加载 ROM。因此 Cosimulation Wizard 生成的 Vivado/XSim 工作目录必须能解析：

```text
motor_control_ip/foc/rom/sin_qw_4096x18.mem
```

允许在生成/启动脚本中把该 `.mem` 作为 simulation data file 加入或复制到实际 XSim 运行目录；**不允许为了 co-sim 修改 ROM 内容或改变已验收 LUT 数学**。日志必须确认没有 readmemh file-not-found，并至少用历史 smoke CMP 证明 ROM 内容实际生效。

### 11.2 Simple 模型中的输入来源

`FPGA_HDL_Cosim` 预留两种输入来源，但 7B 默认使用 smoke source：

```text
FPGA_Cosim_Input_Mode = 0 : fixed smoke constants (7B default)
FPGA_Cosim_Input_Mode = 1 : Simple model live feedback / refs (7C 使用)
```

7B 模式 0 不参与 plant 驱动，只验证完整 HDL 链。

### 11.3 默认参数

```text
PI_PROFILE = 0
clk = 50 MHz
PWM = 10 kHz
TBPRD = 2500
```

### 11.4 固定 smoke 输入

第一笔采用历史 d_current：

```text
ia     = +1.0 A
ib     = -0.5 A
ic     = -0.5 A
theta  = 0
we     = 0
id_ref = 0
iq_ref = 0
vdc    = 48 V
pi_reset  = 0
uq_zero_en = 0
run_enable = 1
```

这些量在第一笔命令完成前保持稳定。

### 11.5 第一笔预期 active CMP

历史已验收第一笔：

```text
CMP_u_active = 1165
CMP_v_active = 1335
CMP_w_active = 1335
```

对应：

```text
D_u = 1165 / 2500 = 0.4660
D_v = 1335 / 2500 = 0.5340
D_w = 1335 / 2500 = 0.5340
```

注意这是 **D_high**，不是原始 C4 `d_foc`。

smoke 只把第一笔结果作为 golden。由于 PI 积分器后续会继续更新，不要求后续命令保持相同 CMP。

### 11.6 smoke 验收

必须确认：

- `PMLSM_ThreeLoop_Simple/FPGA_HDL_Cosim` 内的 Simulink HDL Cosimulation Block 真正启动 Vivado/XSI；
- accepted_sample_id 从 0→1；
- active_command_id 从 0→1；
- active_valid 在第一笔装载后变 1；
- 第一笔 CMP 是 1165/1335/1335；
- needs_reset=0；
- fault_code=0；
- 日志显示 input fixed-point 值与 HDL 端口格式一致；
- **现有 `Control_Task_10kHz -> Inverter_DeadTime -> PMLSM_Plant_Model` 主链在 7B 中仍保持原连接，FPGA branch 不影响 plant。**

成功标记：

```text
STEP7B_FOC_COSIM_SMOKE_PASS
```

---

## 12. PMLSM_ThreeLoop_Simple 的 Retain / Replace / Bypass 设计

这张表冻结 Step 7C/7D 的主模型边界。

| Simple model component | 7B | 7C/7D decision | Reason |
|---|---|---|---|
| `Simple_Host` | RETAIN | RETAIN selectively | 提供位置/速度/电流测试给定、enable/reset/load 等简化控制入口 |
| `Control_Task_10kHz` | RETAIN as plant source | SPLIT/REPLACE progressively | 7B 保持原控制；7C 电流测试模式由 FPGA 内环替代；7D 再决定外环保留/拆分 |
| `Inverter_DeadTime` | RETAIN | RETAIN | 作为 average inverter + plant-side deadtime |
| `PMLSM_Plant_Model` | RETAIN | RETAIN | 电气/机械 plant |
| 原 `cmp_a/b/c_counts` 到 inverter 的旧映射 | RETAIN in 7B | BYPASS on FPGA backend | FPGA 输出已是 `D_high=CMP_active/2500` |
| 原 PWM update delay/近似（若 Simple 内仍存在） | RETAIN in legacy branch | BYPASS on FPGA backend | HDL 已真实完成 shadow/next-ZERO 更新 |
| 原 PI/Clarke/Park/SVPWM | RETAIN in legacy branch | REPLACE on FPGA backend | 由 RTL C1–C4 |
| 原速度/位置环 | RETAIN | DEFER decision to 7D | 当前 FPGA 只实现内环 |
| plant `ia/ib/ic/x_mm/v/theta_e/omega_e` | RETAIN | RETAIN | FPGA input / outer-loop feedback |
| encoder quantization/model（若 Simple 已删除则不恢复） | NO CHANGE | OPTIONAL later | 7C 先用理想 plant 状态 |
| Step 6E six-gate deadtime | OBSERVE ONLY | OBSERVE ONLY in average plant path | 防止与 `Inverter_DeadTime` 重复 |

### 12.1 7C 电流环模式的预期切换

7C 先使用 Simple 模型已有的 current-test / iq-test 接口，不要求立即把三闭环全部迁移：

```text
Simple_Host iq_test_ref / id_ref / enable
                │
                v
        FPGA_HDL_Cosim
                │
        active CMP / 2500
                │
                v
        Inverter_DeadTime
                │
                v
        PMLSM_Plant_Model
```

速度环和位置环在 7C 可以保持关闭。

### 12.2 7D 三闭环方向

到 7D 再从 `Control_Task_10kHz` 中保留/拆出速度环与位置环的参考生成逻辑，使：

```text
Simulink position/speed outer loops
             ↓ id_ref / iq_ref
FPGA HDL current loop + PWM
             ↓ active duty
Simulink inverter + plant
```

不要在 7B 提前重构外环。

---

## 13. 对 PMLSM_ThreeLoop_Simple 的 Step 7B 修改策略

### 13.1 先保留用户原始 Simple 基线，再修改

由于该文件目前只在用户本地主目录、尚未进入 GitHub main：

1. Codex 先只读打开/Update Model，导出结构；
2. 确认用户本地文件不是 cache/临时备份；
3. **第一笔实现提交只把 as-found `PMLSM_ThreeLoop_Simple.slx` 和结构清单纳入 Git**；
4. 第二笔及以后提交才增加 FPGA co-sim 功能。

这样 GitHub 能保留用户这版“简化 DSP 三闭环模型”的原始快照，而不是只看到改完后的二进制 SLX。

### 13.2 7B 在 Simple 模型里新增的内容

允许增加：

```text
PMLSM_ThreeLoop_Simple/FPGA_HDL_Cosim
```

内部建议再分：

```text
FPGA_Input_Adapter
HDL_Cosimulation
FPGA_Output_Adapter
FPGA_Cosim_Monitor
```

还可添加：

- `FPGA_Cosim_Input_Mode`；
- active CMP / duty / ids / fault logging；
- 注释说明未来 7C backend selector 接入点；
- 最少量 scope/display/assert 辅助。

7B **不改变**：

```text
Control_Task_10kHz -> Inverter_DeadTime
```

的 plant 默认驱动关系。

### 13.3 独立最小模型只保留一个

允许新增：

```text
simulink模型/PMLSM_HDL_Cosim_Minimal.slx
```

用于证明 Simulink HDL Cosimulation Block + Vivado 2026.1。

不再新增第二个完整 FOC smoke 模型；FOC smoke 直接在 Simple 模型并联 branch 内完成。

### 13.4 参数脚本

可新增：

```text
simulink模型/init_PMLSM_fpga_cosim_params.m
```

只放：

- co-sim enable / smoke mode；
- Vivado tool path 可配置项；
- HDL clock；
- co-sim communication period；
- fixed-point format constants；
- smoke expected CMP；
- future backend selector placeholder。

不得在 7B 改写 motor/plant 参数。

### 13.5 GitHub 同步是交付的一部分

Step 7B 实现完成必须同时满足：

```text
local MAIN has runnable SLX/RTL
AND
Git implementation branch contains authorized model/RTL/script/report changes
AND
open PR exists for ChatGPT Review
```

不接受：

- 只改本地 `.slx` 不 commit；
- 只提交文字报告、不提交可复现模型；
- 把用户原始 Simple 模型留成 untracked；
- 只返回一个本地路径而不 push GitHub；
- 提交 Simulink/Vivado cache 垃圾代替真正模型源文件。

---

## 14. Deadtime 责任

当前已知：

```text
Step 6E demo deadtime = 500 ns
PMLSM plant parameter PMLSM_deadtime_s = 1 us
```

二者目前不是同一目标。

Step 7B/7C 规定：

```text
average plant deadtime effect:
    Simulink inverter model owns it

RTL gate deadtime:
    not fed into average plant
```

因此不要求把两者改成一样。

后续若研究“RTL deadtime 对平均电压的真实影响”，另开独立模式：

```text
gate-level switching model
or
effective-duty model derived from gate waveforms
```

不得在本主链双重应用。

---

## 15. PWM update delay 责任

现有 MIL `PWM_Update_Delay` 曾用平均/一拍近似模拟命令更新延迟。

Step 7C 使用 FPGA active CMP 后：

```text
FOC result
 -> CMP shadow
 -> next ZERO
 -> CMP_active
```

延迟已经由 RTL 真实实现。

因此：

```text
old MIL PWM_Update_Delay = BYPASS
```

不得再叠加 0.5 sample 或 1 sample。

plant 可以在两次 `active_command_id` 之间保持 duty，这是正常 ZOH，不叫“额外 PWM delay”。

---

## 16. 电流采样责任

Step 7B 不接 plant，但冻结未来原则：

- Simulink 计算/输出 plant 电流；
- fixed-point adapter 负责量化；
- HDL wrapper 的真实 carrier sample slot 决定 FOC 何时接受；
- 不再保留一套专为 DSP/MIL 人工模拟的“controller sample delay”；
- 若未来要模拟 ADC conversion / sensor filter，则作为明确独立的物理测量链建模。

不要把现有 `PMLSM_sensor_delay_samples=50` 自动套到三相电流上；现有模型中的速度/编码器路径和电流采样路径必须逐块区分。

---

## 17. Simulink 模型修改的可审查性

`.slx` 是二进制 ZIP，GitHub diff 不足以证明改动正确。

Codex 修改模型时必须使用 MATLAB/Simulink API，避免 GUI 手工拖动造成不可复现的大范围格式变化。

Step 7B 报告至少保存：

- 修改前/后的 root-level block inventory；
- 新增 subsystem 的完整 block path；
- HDL Cosimulation block 参数；
- sample time / data type；
- model solver / fixed-step 设置；
- InitFcn 变化；
- Model Update/compile 结果；
- 必要截图或 `get_param` 文本导出。

不得使用全局自动布局重排整个模型。

---

## 18. Step 7B 验收

### 18.1 最小 Simulink block

必须有真实 XSI 数据交换：

```text
STEP7B_SIMULINK_MINIMAL_COSIM_PASS
```

### 18.2 完整 FOC smoke

必须有：

```text
STEP7B_FOC_COSIM_SMOKE_PASS
accepted_sample_id = 1
active_command_id  = 1
active CMP = 1165,1335,1335
fault_code = 0
needs_reset = 0
```

### 18.3 原 RTL 回归

由于增加 `CMP_active` 只读输出：

- Step 6D profile0 DEMO=0 回归；
- Step 6D profile1 DEMO=0 回归；
- Step 6E 默认 smoke/回归至少一组；

均不得改变旧算法结果。

无需重新跑所有 C1/C2/C3 单元和完整 route。

### 18.4 PMLSM_ThreeLoop_Simple 默认路径

Step 7B 修改 `PMLSM_ThreeLoop_Simple.slx` 后必须确认：

- `Control_Task_10kHz` 仍是默认 plant source；
- `Inverter_DeadTime -> PMLSM_Plant_Model` 仍按原 Simple 主链工作；
- `FPGA_HDL_Cosim` 在 7B 只是并联 smoke/monitor branch，不驱动 plant；
- Update Model 无 error；
- 至少做一个短时 baseline run 或模型初始化检查；
- Simple 模型原有 current/speed/position enable 接口没有因新增 branch 被破坏；
- GitHub 中存在修改前 baseline commit 和修改后实现 commit。

---

## 19. Step 7B 不做的内容

本阶段不做：

- 动态电机闭环；
- id/iq transient tuning；
- speed loop；
- position loop；
- JMAG/Maxwell；
- gate-level inverter；
- 两边同时 deadtime；
- ADC/编码器真实接口；
- SoC/Vitis；
- AXI；
- FPGA-in-the-Loop；
- bitstream；
- 板卡运行；
- 功率级安全验证。

---

## 20. Step 7C 的预期入口

Step 7B 完成后，Step 7C 将直接在 `PMLSM_ThreeLoop_Simple.slx` 中复用：

```text
FPGA_HDL_Cosim
  ├─ mc_foc_cosim_top
  ├─ HDL Cosimulation Block
  ├─ fixed-point adapters
  └─ active CMP output adapter
```

并把该 branch 正式接入 `Inverter_DeadTime`，形成：

```text
Simulink motor current
        ↓
quantization
        ↓
Vivado HDL FOC/PWM
        ↓
CMP_active / 2500
        ↓
Simulink average inverter
        ↓
motor electrical/mechanical plant
        ↓
next current sample
```

第一阶段只做静止电流环。

Step 7D 再恢复：

```text
speed loop
position loop
full motion
```

---

## 21. 官方工具行为依据

Step 7B 的工具配置以当前 MathWorks HDL Verifier 文档为参考：

- Vivado Simulator 的 HDL Cosimulation Block 必须通过 Cosimulation Wizard 生成；
- Block 可映射整数、Boolean 和 fixed-point 端口；
- Vivado block 可以定义 clock/reset；
- output ports 需要明确 sample time；
- Simulink 与 HDL simulator 通过 timescale 映射物理时间；
- Vivado cosimulation block 自己加载/执行编译后的设计，不需要另开一个独立 simulator 会话。

R2026b Prerelease + Vivado 2026.1 的实际兼容性以 Step 7A 本机成功证据为准，而不是把“未 fully tested”的版本警告当成失败。

---

## 22. 完成定义

Step 7B 完成的含义是：

> `PMLSM_ThreeLoop_Simple.slx` 已被纳入 GitHub 基线，并在不改变原 plant 默认控制源的前提下增加可运行的 FPGA HDL co-sim branch；Simulink HDL Cosimulation Block 能够通过 Vivado 2026.1 驱动现有完整 FOC/PWM RTL并读到真实 ZERO 装载后的 active CMP，同时 7C 在 Simple 模型内的后续切换边界已经冻结。

它**不意味着**电机闭环已经正确，也不意味着 Simulink plant 与 RTL deadtime/ADC/外环全部完成集成。
