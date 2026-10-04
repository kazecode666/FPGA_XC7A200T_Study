# Study-L1：速度 PI 的 HDL Coder 与手写 SystemVerilog 对照实验

> 状态：**任务书 / 设计规格，尚未授权实施代码**  
> 执行者：Codex  
> Review：ChatGPT  
> 学习者：用户  
> 目标平台：XC7A200T（学习比较目标器件）  
> 系统仿真：MATLAB / Simulink R2026b + HDL Coder + HDL Verifier + Vivado 2026.1  
> 后续实机、MDBL4、MPSoC 均不属于本任务

---

## 0. 任务定位

Study-L1 不是为了尽快做出一个“能用的速度 PI”，而是使用**同一个速度 PI 算法**完整比较以下四种实现：

1. 原 Simulink 浮点行为模型；
2. 明确定点规则的 Simulink fixed-point 模型；
3. HDL Coder 自动生成 HDL；
4. 手写 SystemVerilog RTL。

最终再把自动生成速度 PI / 手写速度 PI 分别与项目中已经验证的手写 FOC RTL 组合，通过 Vivado Simulator / XSI 接回 PMLSM 系统模型。

本任务的核心问题是：

> 同一个离散控制算法，从浮点模型变成定点模型，再变成自动生成 RTL 或手写 RTL 时，数值、时序、资源、可读性、调试方式和系统闭环行为分别发生了什么变化？

**这是一项学习实验，不要求选出唯一“正确”的开发方式，也不要求淘汰现有手写 FOC。**

---

# 1. 实施前置条件

## 1.1 PR36 必须先完成并合并

当前 PR #36 正在修复/优化 Simulink HDL 联合仿真的交互入口。

Study-L1 的代码实施必须满足：

1. PR #36 已经完成 ChatGPT Review；
2. PR #36 已合并到 `main`；
3. Codex 从 PR36 合并后的最新 `main` 开始 Study-L1；
4. 不把 PR36 的联合仿真入口修复与 Study-L1 混在同一个实现 PR。

任务书本身可以提前进入仓库，但**不得以本任务书为由提前开始 Study-L1 实现**。

## 1.2 本地工作树规则

实际实施只允许在：

```text
D:/Project/FPGA_XC7A200T
```

原始主工作树中进行。

禁止：

- 新建 linked worktree；
- 额外 clone；
- 自动 stash；
- `reset --hard`；
- `clean -fd`；
- 覆盖用户 tracked / untracked 文件；
- 覆盖用户尚未提交的 SLX 布局或硬件资料。

开始前必须记录：

- 当前 branch；
- `git status`；
- `origin/main`；
- 用户本地未提交内容。

如本地状态与任务书假设冲突，先在 GitHub 报告，不强制整理用户工作区。

---

# 2. 当前速度 PI 基线

Codex 必须以**本地真实 `PMLSM_ThreeLoop_Simple.slx` 和运行时生效值**为准，不允许只根据任务书重画一个“常见 PI”。

当前仓库文本基线为：

```text
Ts_ASR = 1 ms

Kp_ASR ≈ 0.018033474852681124
Ki_ASR ≈ 1.4426779882144898
Kaw_s  = 0.08

Speed_loop_Iq_Limit = ±1 A
Iq_int_limit         = ±0.5 A
```

当前 Simple 速度反馈单位为：

```text
mm/s
```

速度 PI 输出为 q 轴电流参考：

```text
Apeak
```

现有设计脚本中：

```text
Ki branch uses Ki_ASR * Ts_ASR
```

但以下内容**不能从任务书假设**，必须在 Checkpoint A 从真实 SLX 审计：

- error 的确切来源和符号；
- P、I、anti-windup 的运算先后顺序；
- `iq_unlimited` 与 `iq_limited` 的确切位置；
- 积分器自身限幅的位置；
- anti-windup excess 的定义；
- `hard_reset` / `int_reset` 的优先级；
- enable/disable 对积分状态的影响；
- speed task 的首次执行相位；
- 1 ms task 是否通过 held reference / tick 更新；
- reset 同拍时输出与积分器到底采用旧值还是新值。

若实际模型与以上文字基线不一致：

> 保留 as-found 事实，先报告，不为了匹配任务书擅自修改原模型。

---

# 3. 设计总原则：A / B / C / D 四层对照

本任务固定四层：

| 代号 | 实现 | 角色 |
|---|---|---|
| A | 原 Simulink double speed PI | 行为参考 |
| B | 显式 fixed-point Simulink speed PI | **bit-true 数值参考** |
| C | HDL Coder 生成 RTL | 自动硬件实现 |
| D | 手写 SystemVerilog speed PI | 人工硬件实现 |

比较关系：

```text
            A: float Simulink
                   |
             float -> fixed
                   v
            B: fixed Simulink
               /         \
              /           \
             v             v
    C: HDL Coder RTL   D: Hand SV RTL
              \           /
               \         /
                 Vivado
                   |
            system co-simulation
```

关键规定：

1. A→B 用来研究定点误差；
2. **B 是 C/D 的 golden model**；
3. C/D 只有在有效输出时刻对齐后，才做 bit-exact 比较；
4. 不允许用 double A 直接要求 RTL bit-exact；
5. 不允许 C 与 D 使用不同算法，再用“波形差不多”作为等价证明。

---

# 4. 任务边界

## 4.1 本任务允许做

- 从现有 Simple 模型审计真实速度 PI；
- 新建独立 Study-L1 Simulink testbench；
- 新建 float / fixed-point 速度 PI 学习模型；
- 使用 HDL Coder 生成 HDL；
- 生成并阅读 HDL report / traceability；
- 将生成 HDL 放入 Vivado Simulator；
- Vivado synthesis / implementation / timing / utilization；
- 手写一个等价 SystemVerilog speed PI；
- 建立 bit-true 自动比较；
- 对 HDL Coder 版本做**一个**有控制变量的优化实验；
- 建立 Study-L1 专用 XSI co-simulation；
- 将生成速度 PI / 手写速度 PI 分别接到现有手写 FOC RTL；
- 使用现有 Simulink plant 验证速度闭环；
- 生成学习报告和复现说明。

## 4.2 本任务明确不做

- 不修改 AUM3-S4 电流 PI 参数；
- 不重新整定速度 PI；
- 不引入位置差分测速；
- 不引入 IIR 速度滤波；
- 不把学习笔记中另一套 4.6 ms 延迟模型带入 Simple；
- 不 HDL 化位置环；
- 不 HDL 化轨迹规划；
- 不设计实际 ADC；
- 不设计 QEP；
- 不接 BX72 GPIO；
- 不接 MDBL4；
- 不生成 bitstream；
- 不操作 FPGA 硬件；
- 不操作真实电机；
- 不做 MPSoC / PS / AXI / Linux / R5；
- 不做 Embedded Coder；
- 不做 Vitis HLS；
- 不重写现有 FOC；
- 不重跑完整 Step 6 / Step 7D 历史验收；
- 不把 `CONTROL_BACKEND` 扩展成同时管理所有学习实现的大开关。

---

# 5. 目录与产物规划

建议建立独立目录：

```text
learning/
└── study_l1_speed_pi_hdl_compare/
    ├── README.md
    ├── models/
    │   ├── speed_pi_float.slx
    │   ├── speed_pi_fixed.slx
    │   └── speed_pi_compare_tb.slx
    ├── handwritten/
    │   └── speed_pi_sv.sv
    ├── generated_hdl/
    │   └── baseline/
    ├── integration/
    │   ├── study_l1_speed_hdlcoder_cosim_top.sv
    │   └── study_l1_speed_handsv_cosim_top.sv
    ├── scripts/
    │   ├── study_l1_init.m
    │   ├── study_l1_generate_vectors.m
    │   ├── study_l1_compare_bittrue.m
    │   ├── study_l1_run_hdlcoder.m
    │   ├── study_l1_run_vivado_compare.m
    │   └── study_l1_run_system_cosim.m
    └── reports/
        ├── checkpoint_a/
        ├── checkpoint_b/
        ├── checkpoint_c/
        └── checkpoint_d/
```

最终名称允许 Codex根据实际 HDL Coder 工作流做**小范围命名调整**，但必须保持：

- float/fixed/generated/handwritten/integration 清晰分离；
- 自动生成代码与手写代码不能混在同一个目录；
- generated HDL 不能手工修改后再冒充 HDL Coder 输出。

## 5.1 Git 中允许提交

允许提交：

- Study-L1 SLX 学习模型；
- 初始化脚本；
- 测试向量生成脚本；
- bit-true 比较脚本；
- 手写 SystemVerilog；
- baseline HDL Coder 生成的**核心 HDL 源码**；
- 生成配置 manifest；
- 精简后的 Vivado 报告文本；
- 对比表；
- 学习说明。

## 5.2 Git 中禁止提交

禁止提交：

- `.Xil/`；
- `xsim.dir/`；
- Vivado cache；
- Vivado generated run directories；
- temporary codegen cache；
- bitstream；
- 大型二进制仿真中间文件；
- 用户全局工具配置。

如果 HDL Coder 默认输出目录含大量临时内容，只选择对学习和复现必要的 HDL 源码/配置/报告摘要提交。

---

# 6. Checkpoint A：审计原速度 PI + Float/Fixed 建模

Checkpoint A 的目的：

> 先完全理解“当前 PI 算的到底是什么”，再谈 HDL。

---

## Task A1：审计真实速度 PI

Codex 必须读取真实 `PMLSM_ThreeLoop_Simple.slx`，并形成：

```text
learning/study_l1_speed_pi_hdl_compare/reports/checkpoint_a/current_speed_pi_audit.md
```

报告至少包含：

| 项目 | 必须给出的内容 |
|---|---|
| Speed task | 周期、首次执行相位、触发条件 |
| 输入 | v_ref / v_meas 的真实来源、单位 |
| Error | 符号和更新时刻 |
| P branch | 完整表达式 |
| I branch | 完整离散表达式 |
| Integrator | 初值、状态更新时间 |
| Anti-windup | 完整表达式、excess 定义 |
| Output limit | ±值与所在位置 |
| Integrator limit | ±值与所在位置 |
| Reset | hard_reset/int_reset/pi reset 各自语义 |
| Enable | disable 时输出和状态怎样变化 |
| Output | `iq_unlimited` / `iq_limited` / outer reference 关系 |

必须把真实控制器写成明确的离散方程/伪代码。

禁止：

- 根据常见并联 PI 猜公式；
- 为了方便 HDL Coder 先简化算法；
- 发现结构奇怪就直接改原 SLX。

---

## Task A2：建立独立浮点 Test Bench

从真实速度 PI 语义建立独立 Study-L1 浮点版本。

最少输入：

```text
v_ref_mmps
v_meas_mmps
enable
reset
sample_tick
```

最少输出：

```text
iq_ref_A
iq_unlimited_A
integrator_A
saturation_active
```

### 测试向量必须覆盖

1. 零误差；
2. 小正误差；
3. 小负误差；
4. 正向输出饱和；
5. 负向输出饱和；
6. 持续饱和形成 anti-windup；
7. 从饱和解除；
8. 正饱和后反向命令；
9. reset；
10. disable；
11. re-enable；
12. reset 与有效 tick 相邻的边界情况。

饱和测试不要写死一个随参数失效的魔法数字。优先根据：

```text
Speed_loop_Iq_Limit / Kp_ASR
```

自动生成能够明确越过饱和门槛的速度误差。

### A2 验收

独立浮点 PI 与原 SLX 在相同输入/调度下：

- `iq_unlimited` 一致；
- `iq_limited` 一致；
- integrator state 一致；
- reset/enable 语义一致。

若原 SLX 无法直接抽出单模块测试，允许通过保存的运行输入/内部日志进行对照，但必须证明比较的是**同一 PI 算法和同一 tick**。

---

## Task A3：建立定点 Golden Model B

不要先由任务书指定固定 `Qx.y`。

Codex 应先记录实际范围，再设计两套数据类型：

### B1：conservative / readable

目标：

- 容易理解；
- 无非预期限幅；
- 足够精度；
- 作为 C/D baseline。

### B2：resource-oriented candidate

只在 B1 正确后建立，用来研究缩短位宽对误差和资源的影响。

必须生成：

```text
reports/checkpoint_a/datatype_table.md
```

至少列：

| Signal | Observed/required range | Signed | Word length | Fraction length | LSB |
|---|---:|---|---:|---:|---:|
| v_ref | | | | | |
| v_meas | | | | | |
| speed error | | | | | |
| Kp | | | | | |
| KiTs | | | | | |
| anti-windup term | | | | | |
| integrator | | | | | |
| iq_unlimited | | | | | |
| iq_ref | | | | | |

必须明确：

- rounding mode；
- overflow mode；
- saturate / wrap；
- coefficient quantization；
- intermediate product width；
- accumulation width。

### 外部 iq_ref 边界

如果没有技术阻碍，Study-L1 最终系统集成边界应优先与现有 FOC `iq_ref` 接口兼容：

```text
signed 25-bit, fraction length 15
```

如果 B1 证明这不是合适的速度 PI 输出格式，可使用内部格式并在 integration adapter 中显式转换，但必须记录转换误差；不能偷偷改变现有 FOC 接口。

### A3 数值验收

A（double）对 B1（fixed）不要求 bit-exact。

要求：

- 无预期外溢；
- 输出饱和方向和时刻一致；
- reset / enable 行为一致；
- 非饱和测试点的 `iq_ref` 偏差不超过 B1 输出格式的 2 LSB（若实际算法量化结构导致无法达到，先报告原因，不擅自放宽）；
- 积分状态误差有独立统计；
- 所有差异用 raw fixed code + physical unit 两种方式记录。

---

## Checkpoint A 停止点

完成 A1-A3 后：

1. 提交一次 Git commit；
2. 在 Study-L1 GitHub Issue/PR 留下摘要；
3. 给出：
   - 实际离散方程；
   - datatype table；
   - float/fixed comparison；
   - 未解决问题。
4. **不自动进入 Checkpoint B，等待 ChatGPT Review。**

---

# 7. Checkpoint B：HDL Coder + Vivado baseline

Checkpoint B 的目的：

> 第一次完整体验“Simulink fixed-point model → HDL Coder → Vivado”的自动 RTL 路径。

---

## Task B1：建立 HDL Coder baseline configuration

以 B1 fixed-point model 为唯一 baseline。

要求：

- 优先生成 SystemVerilog；若当前 R2026b 工作流对该模型只适合 Verilog，可以使用 Verilog，但必须记录；
- 第一版以可读性和可追溯性优先；
- 不先开启大量 optimization；
- clock target = 50 MHz；
- target part 使用当前项目真实 XC7A200T part，必须从现有工程/XDC/项目属性审计得到，禁止凭型号字符串猜 part；
- 保留明确 `clk/reset/enable(sample_tick)` 语义；
- 速度 PI 仍然每 1 ms 更新，不允许创建独立 1 kHz 物理时钟来替代 CE。

生成前检查：

- HDL compatibility；
- unsupported blocks；
- fixed-point types；
- reset behavior；
- sample/clock enable behavior。

---

## Task B2：生成 baseline HDL

Codex 执行 HDL Coder，但必须保留用户可学习的产物：

- generation command/config；
- HDL report；
- traceability；
- generated top；
- relevant generated submodules；
- latency summary。

baseline generated HDL 必须写入：

```text
generated_hdl/baseline/
```

并建立：

```text
generated_hdl/baseline/MANIFEST.md
```

MANIFEST 至少记录：

- MATLAB release；
- HDL Coder version；
- HDL language；
- source SLX；
- top subsystem；
- target part；
- target clock；
- fixed-point B1 version；
- generator options；
- latency；
- output files；
- generation timestamp/commit。

禁止直接编辑 generated baseline HDL。

若必须修生成错误：

> 回到模型或生成配置修，再重新生成。

---

## Task B3：Vivado functional simulation

将 baseline generated HDL 加入一个最小 Vivado/XSim testbench。

测试向量必须与 Checkpoint A 相同。

必须观察/记录：

```text
clk
reset
sample_tick / clock_enable
v_ref
v_meas
integrator state（如果生成代码可合理观察）
iq_ref
output_valid / enable-equivalent
```

核心验收：

**在按 generator latency 对齐以后，C 的有效输出 raw code 必须与 fixed-point B bit-exact。**

若生成 RTL 隐藏了内部积分状态，输出 bit-exact 是硬要求；内部状态可通过 traceability / simulator probe 记录，不要求为了暴露它改生成代码。

---

## Task B4：Vivado synthesis + implementation baseline

使用同一个 XC7A200T part 和 50 MHz 约束。

记录：

```text
LUT
FF
DSP48
BRAM
WNS
critical path summary
latency
initiation/update interval
```

本任务不是为了追求高频极限。

硬门槛：

```text
50 MHz timing must close (WNS >= 0)
```

如果一个速度 PI baseline 连 50 MHz 都不能通过：

> 先分析 generator/interface/constraint 问题，不直接堆 optimization。

---

## Task B5：用户学习材料

Codex 必须生成：

```text
reports/checkpoint_b/hdl_coder_walkthrough.md
```

其中明确指出：

1. Model 中误差计算对应生成 RTL 哪部分；
2. Kp multiplication 对应哪里；
3. KiTs / integration 对应哪里；
4. integrator register 在哪里；
5. saturation logic 在哪里；
6. reset 在哪里；
7. CE/sample tick 在哪里；
8. latency 是多少；
9. 是否使用 DSP48；
10. Vivado utilization / timing 报告路径。

不要求用户亲自写代码，但必须让用户可以沿这些路径阅读生成结果。

---

## Checkpoint B 停止点

完成后：

- commit；
- GitHub 汇报；
- ChatGPT Review；
- **不自动进入手写 RTL。**

---

# 8. Checkpoint C：手写 SystemVerilog + 公平比较

Checkpoint C 的目的：

> 使用同样的 fixed-point B1 算法，自己实现一份 RTL，再与 HDL Coder RTL 做公平对照。

---

## Task C1：定义共同 RTL contract

C 和 D 的比较必须使用同样：

- physical units；
- input fixed formats；
- output fixed format；
- coefficient raw values；
- rounding；
- saturation；
- integrator limit；
- anti-windup；
- reset semantics；
- sample tick semantics。

建议统一逻辑接口：

```text
clk
reset_n
enable
sample_valid / speed_tick
v_ref
v_meas
iq_ref
result_valid
```

具体 bit width 由 Checkpoint A B1 冻结。

若 HDL Coder 顶层接口命名不同，可以使用**极薄 wrapper**对齐接口。

wrapper 只能做：

- rename；
- CE/valid adaptation；
- 明确的数据类型边界。

不能在 wrapper 里重新实现 PI 运算。

---

## Task C2：手写 `speed_pi_sv.sv`

手写版允许自己选择：

- pipeline；
- register placement；
- state machine；
- multiplier scheduling；
- CE implementation。

但禁止改变：

- 数学算法；
- fixed-point formats；
- rounding/saturation；
- anti-windup；
- reset；
- output limit。

---

## Task C3：bit-true regression

固定模型 B、生成 RTL C、手写 RTL D 同时使用同一组测试向量。

要求对齐各自 latency 后：

```text
B raw iq_ref == C raw iq_ref == D raw iq_ref
```

所有有效样本 bit-exact。

测试必须至少覆盖：

- 正线性；
- 负线性；
- 零误差；
- 正饱和；
- 负饱和；
- anti-windup；
- 解除饱和；
- 饱和后反向；
- reset；
- disable；
- re-enable；
- 连续有效 tick；
- 空闲 50 MHz 时钟之间不更新状态。

如果 C/D latency 不同：

> 允许 latency 不同，但必须按 result_valid/已知 latency 对齐；禁止通过任意波形平移掩盖错误。

---

## Task C4：公平 Vivado resource/timing comparison

必须尽量消除不公平因素：

- 同目标器件；
- 同 50 MHz constraint；
- 同外部 fixed formats；
- 同输入/输出寄存边界；
- 同 reset/enable contract。

比较表：

| Metric | HDL Coder C | Hand SV D |
|---|---:|---:|
| LUT | | |
| FF | | |
| DSP48 | | |
| BRAM | | |
| Latency (clocks) | | |
| Update interval | | |
| WNS @ 50 MHz | | |
| Generated/hand RTL LOC | | |
| Major critical path | | |

不设置“手写必须更小”或“自动必须更快”的结论。

---

## Task C5：只做一个 HDL Coder optimization experiment

根据 baseline 报告，在以下方向中只选择**一个**：

- pipeline；
- resource sharing；
- multiplier mapping；
- register balancing；
- 其他 HDL Coder 中明确可归因的单一配置。

要求：

```text
Coder baseline
vs
Coder optimized
```

记录：

- 数值是否仍 bit-true；
- LUT/FF/DSP；
- latency；
- WNS。

禁止一次开启多个无法归因的优化。

---

## Checkpoint C 停止点

生成：

```text
reports/checkpoint_c/final_rtl_comparison.md
```

报告必须分开：

- 自动生成的优势；
- 自动生成的不足；
- 手写的优势；
- 手写的不足；
- 哪些差异来自架构；
- 哪些差异来自工具；
- 哪些差异暂时无法归因。

commit + GitHub 汇报 + ChatGPT Review 后，才进入系统联合仿真。

---

# 9. Checkpoint D：Generated Speed PI + Handwritten FOC 系统联合仿真

Checkpoint D 的目的：

> 第一次让 HDL Coder 生成的控制模块与现有手写 FOC RTL 在同一硬件控制链中合作。

---

## 9.1 系统架构

目标 Case C：

```text
Simulink Host / Position loop
          |
        v_ref
          |
          v
HDL Coder Speed PI
          |
       iq_ref
          |
          v
existing handwritten FOC RTL
Clarke/Park -> dq PI -> limiter -> InvPark -> SVPWM -> active CMP
          |
          v
Simulink average inverter/deadtime
          |
          v
PMLSM plant
          |
       v_meas / currents / theta
```

目标 Case D：

```text
Simulink Host / Position loop
          |
        v_ref
          |
          v
Handwritten Speed PI
          |
       iq_ref
          |
          v
same existing handwritten FOC RTL
          |
          v
same Simulink inverter + plant
```

对照 Case A：

```text
Original Simulink Speed PI
          +
same existing handwritten RTL FOC
```

---

## 9.2 调度边界

本任务只比较速度 PI 实现，不顺带实现最终 FPGA scheduler。

因此 Study-L1 system co-sim 应保留一个显式：

```text
speed_tick / sample_valid
```

输入，使 C/D 在**与当前 Simulink speed task 同一个更新时刻**计算。

必须先从 Task A1 得到真实 speed tick 首相位。

不要简单假设：

```text
t = 0, 1ms, 2ms...
```

如果现有模型实际首相位不同，Study-L1 必须跟随真实调度。

纯 FPGA 上最终使用“50 MHz divider / scheduler 产生 speed_tick”属于后续实机任务。

---

## 9.3 RTL integration boundary

当前现有 FOC `iq_ref` 接口保持不变。

速度 PI 输出只在 `result_valid` 时更新一个 held iq_ref register；在两个 speed tick 之间：

```text
iq_ref must remain held
```

FOC 仍按现有 100 us transaction 运行。

禁止：

- 将速度 PI 改成 100 us 更新；
- 将 current loop 改成 1 ms；
- 因为 generated RTL latency 改变原 FOC transaction；
- 因为方便联合仿真修改电流 PI。

---

## 9.4 不修改正式主模型的原则

Checkpoint D 优先采用：

- 独立 Study-L1 system testbench；
- Model Reference；
- 临时程序化配置；
- 或专用 study copy。

**不得直接保存永久修改到 `PMLSM_ThreeLoop_Simple.slx`。**

如果必须永久修改主 SLX 才能完成：

> stop and report，由 ChatGPT/用户另行授权。

---

## 9.5 XSI runtime

C 与 D 建议使用独立的 Study-L1 cosim tops/runtime，例如：

```text
study_l1_speed_hdlcoder_cosim_top
study_l1_speed_handsv_cosim_top
```

不要把现有 `CONTROL_BACKEND` 改成 0/1/2/3 多重学习开关。

现有语义继续是：

```text
CONTROL_BACKEND=0 -> legacy Simulink current backend
CONTROL_BACKEND=1 -> RTL current backend
```

Study-L1 选择哪一种 speed PI，应由 Study-L1 自己的脚本/runtime 决定。

---

## 9.6 系统级场景

最少运行：

1. `speed_ideal`；
2. `speed_deadtime`；
3. 一个短 position prefix sanity（仅确认位置外环→HDL速度环→HDL电流环链路）。

比较：

```text
v_ref
v
speed_pi_iq_ref
iq
speed PI result_valid
FOC accepted_sample_id
FOC active_command_id
fault_code
needs_reset
```

### 系统硬门槛

三种速度 PI 实现均要求：

- 无 NaN/Inf；
- 方向正确；
- 不发散；
- `fault_code=0`；
- 正常运行 `needs_reset=0`；
- iq 不异常；
- FOC accepted/active 时序保持；
- 当前 Step 7D 对应 speed scenario 的 acceptance 仍满足。

**不要求 Case A/C/D 波形逐点完全一样。**

如果 generated speed PI 因真实 pipeline latency 导致小差异：

- 记录 latency；
- 解释差异；
- 不为“看起来一样”偷偷重调 PI。

如果性能明显失败：

1. 先查 speed tick phase；
2. valid/hold；
3. data type；
4. reset/enable；
5. pipeline latency；
6. integration adapter；
7. 最后才讨论控制器是否需要因新增真实延迟重新设计。

本 Study-L1 不授权重新整定。

---

# 10. Codex 实施职责

本任务代码工作主要由 Codex 完成。

Codex 负责：

- 真实 SLX 审计；
- 建立独立学习模型；
- 数据类型设计；
- test vectors；
- HDL Coder 配置与脚本；
- 自动生成 HDL；
- Vivado/XSim 工程自动化；
- 手写 SV；
- bit-true regression；
- Vivado synthesis/implementation；
- resource/timing 报告解析；
- Study-L1 XSI 联合仿真；
- Git 提交；
- 报告；
- GitHub checkpoint 汇报。

Codex **不得**因为用户主要观察结果，就跳过代码可读性、复现脚本或验证证据。

---

# 11. 用户学习目标

用户不负责主要编码，但本任务结束后应能够根据 Codex 产物回答：

1. 为什么 1 ms speed PI 不需要 1 kHz FPGA physical clock？
2. Clock Enable / sample tick 与新建低速时钟有什么区别？
3. `Ki` 与 `Ki*Ts` 有什么区别？
4. 为什么积分器必须是状态寄存器？
5. fixed-point 的整数位怎样根据 range 决定？
6. fractional bits 减少后对 LSB 和量化误差有什么影响？
7. rounding 与 saturation 在 RTL 中怎样表现？
8. HDL Coder 生成的乘法是否用了 DSP48？依据是什么？
9. generated HDL 的 latency 是多少？如何从 valid/报告中确认？
10. HDL Coder 与手写 RTL 的资源和时序为什么可能不同？
11. 为什么 C/D 应与 fixed model B bit-exact，而不是与 double model A bit-exact？
12. 为什么 HDL Coder generated RTL 和 hand SystemVerilog 可以放在同一 Vivado 工程？
13. 为什么 system co-sim 中 generated speed PI 可以与 handwritten FOC 组合？
14. 为什么本 Study-L1 使用外部 speed_tick，而真正上板时才设计板内 scheduler？
15. 如何从 Vivado utilization/timing report 判断一个模块是否真的适合目标 FPGA？

Codex 的报告必须给用户足够路径和数据，使这些问题可以由用户自行阅读回答。

---

# 12. Review 与提交节奏

Study-L1 不允许 Codex 一口气完成所有 Checkpoint 后再第一次请求 Review。

执行顺序固定：

```text
Checkpoint A
audit + float/fixed
        |
        v
ChatGPT Review
        |
        v
Checkpoint B
HDL Coder + Vivado baseline
        |
        v
ChatGPT Review
        |
        v
Checkpoint C
Hand SV + bittrue + resource compare
        |
        v
ChatGPT Review
        |
        v
Checkpoint D
system XSI co-simulation
        |
        v
Final Review
```

每个 Checkpoint：

1. fresh verification；
2. commit；
3. push；
4. GitHub 留下摘要；
5. 停止；
6. 等待 Review。

可以使用一个长期 Study-L1 实现 PR，并在 Checkpoint 内逐步追加 commits；也可以由 Codex提出更合适的 GitHub组织方式，但不得失去阶段性 Review gate。

---

# 13. Stop-and-report 条件

遇到以下情况立即停止当前 Checkpoint并报告，不自行改变任务目标：

1. 真实 speed PI 结构与任务书文字假设明显不同；
2. 现有 speed PI 有明确 bug，需要先修原算法；
3. HDL Coder 无法表达现有 anti-windup/reset 语义；
4. 为生成 HDL 必须改变原算法；
5. fixed-point B 无法在合理位宽下满足数值语义；
6. C 无法对 B bit-exact 且原因不清楚；
7. D 无法对 B bit-exact；
8. 50 MHz baseline timing 失败；
9. system integration 需要永久修改主 Simple SLX；
10. system integration 需要修改现有 FOC RTL；
11. 需要重新整定 speed PI；
12. 发现必须引入位置差分/IIR；
13. 工具版本、许可证或 target part 与任务书不一致；
14. PR36 尚未合并；
15. 本地用户文件存在覆盖风险。

报告时必须区分：

- tool limitation；
- model limitation；
- numerical difference；
- RTL bug；
- integration bug；
- taskbook assumption error。

---

# 14. 最终报告

完成 Checkpoint D 后生成：

```text
learning/study_l1_speed_pi_hdl_compare/reports/STUDY_L1_FINAL_REPORT.md
```

至少包括：

## 14.1 原控制器

- 离散方程；
- reset/enable/anti-windup；
- 调度。

## 14.2 Float vs Fixed

- datatype table；
- coefficient quantization；
- error metrics；
- overflow/saturation。

## 14.3 HDL Coder

- generation architecture；
- latency；
- traceability；
- resource/timing；
- readability observations。

## 14.4 Hand SV

- architecture；
- latency；
- resource/timing；
- readability/debug observations。

## 14.5 Bit-true

- B/C/D test coverage；
- raw code comparison；
- all mismatches（若有）。

## 14.6 Vivado fair comparison

完整表：

| Metric | HDL Coder baseline | HDL Coder optimized | Hand SV |
|---|---:|---:|---:|
| LUT | | | |
| FF | | | |
| DSP48 | | | |
| BRAM | | | |
| Latency | | | |
| Update interval | | | |
| WNS @ 50 MHz | | | |
| RTL LOC | | | |

## 14.7 System co-sim

- Simulink Speed PI + Hand FOC；
- HDL Coder Speed PI + Hand FOC；
- Hand SV Speed PI + Hand FOC；
- speed_ideal；
- speed_deadtime；
- short position sanity；
- latency effect；
- metrics。

## 14.8 学习结论

禁止写简单的：

> HDL Coder better / Hand HDL better

必须分场景总结：

- 哪个更适合算法快速迭代；
- 哪个更适合细粒度时序控制；
- 哪个更易修改；
- 哪个更易追踪数值；
- 哪个资源更好；
- 哪个时序更好；
- 哪些结果与最初预期相反；
- 后续哪些模块值得尝试 HDL Coder；
- 哪些模块仍推荐手写 RTL。

---

# 15. 最终完成定义

Study-L1 只有同时满足以下条件才算完成：

- [ ] 原 speed PI 实际语义已审计；
- [ ] 独立 float model 与原速度 PI 对齐；
- [ ] fixed B1 golden model 完成；
- [ ] datatype table 完成；
- [ ] HDL Coder baseline 生成；
- [ ] generated RTL 对 fixed B bit-exact；
- [ ] Vivado simulation 通过；
- [ ] HDL Coder baseline 50 MHz timing 通过；
- [ ] Hand SV 完成；
- [ ] Hand SV 对 fixed B bit-exact；
- [ ] C/D 公平 resource/timing comparison 完成；
- [ ] 一个 HDL Coder optimization experiment 完成；
- [ ] generated speed PI + handwritten FOC co-sim 完成；
- [ ] hand speed PI + handwritten FOC co-sim 完成；
- [ ] system speed scenarios 满足当前 acceptance；
- [ ] 没有修改现有 FOC 算法；
- [ ] 没有修改正式 Simple 主模型（除非另行授权）；
- [ ] 没有生成 bitstream；
- [ ] 没有操作硬件；
- [ ] 最终学习报告完成；
- [ ] 每个 Checkpoint 都经过 GitHub Review gate。

---

# 16. Codex 启动指令（PR36 合并后使用）

PR36 合并后，由用户/ChatGPT对 Codex 发出：

```text
开始 Study-L1：速度 PI 的 HDL Coder 与手写 SystemVerilog 对照实验。

严格读取并执行：
coordination/tasks/study_l1_speed_pi_hdl_coder_vs_sv.md

只在：
D:/Project/FPGA_XC7A200T
原始工作树工作。

第一步先确认 PR36 已合并，并同步到其合并后的最新 main。
审计 git status 和我的所有本地 tracked/untracked 修改。
不要新建 worktree/clone，不 stash，不 reset/clean，不覆盖我的文件。

本任务代码主要由你完成，但这是学习实验：
必须保留清晰的模型、生成 HDL、Vivado 报告、bit-true 对比和可阅读说明。

严格按 Checkpoint A -> B -> C -> D 执行。
每完成一个 Checkpoint：
fresh verification -> commit -> push -> GitHub 汇报 -> STOP，
等待 ChatGPT Review。
不得自动进入下一 Checkpoint。

Checkpoint A 首先读取真实 PMLSM_ThreeLoop_Simple.slx，
审计现有速度 PI 的离散方程、anti-windup、reset、enable 和 speed tick。
不要根据常见 PI 结构猜。
不要修改原速度 PI来适应 HDL Coder。

不要修改：
- AUM3-S4 current PI
- existing FOC RTL
- PWM timing
- plant
- current CONTROL_BACKEND semantics
- speed PI tuning

不要加入：
- position-difference speed measurement
- IIR delay model
- ADC/QEP/MDBL4
- MPSoC/AXI/Linux/R5
- Embedded Coder / Vitis HLS

不要生成 bitstream，不操作 FPGA，不操作真实电机。

Study-L1 的 fixed-point B1 是 HDL Coder RTL 与 Hand SV 的唯一 bit-true golden model。
C/D 必须在 latency/valid 对齐后 raw-code bit-exact。
系统级差异允许存在，但不能通过偷偷重调 PI 消除。

如果任务书的结构与真实 SLX 不一致，或者必须改现有控制算法/主 SLX/FOC，
立即 stop and report。
```

---

# 17. 任务书完成后的下一阶段关系

Study-L1 完成后，才讨论：

```text
XC7A200T 单板：
speed PI + current FOC + PWM
        |
        v
ILA / oscilloscope
```

之后再进入真实 ADC / encoder / MDBL4。

Study-L1 本身不构成上板授权。
