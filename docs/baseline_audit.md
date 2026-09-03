# PWM_Controller Vivado 工程基线审计

审计日期：2026-09-03  
审计范围：`PWM_Controller/` 现有 Vivado 工程、RTL、testbench 与版本控制边界  
审计约束：本轮不修改 PWM 功能行为；只新增本文档

## 1. 结论摘要

`PWM_Controller` 是一个很小的 SystemVerilog RTL 工程。设计只使用输入 `clk` 驱动三个时序过程，没有 PLL、MMCM、Clocking Wizard、逻辑分频时钟或门控时钟。RTL 的时序赋值均使用非阻塞赋值，未发现锁存器、组合环、延时语句或其他明显不可综合结构。

当前工程仍不具备可靠的上板与时序验收条件：工程没有任何 XDC 约束，也没有综合、实现或时序报告；当前 shell 找不到 `vivado`、`xvlog`、`xelab`、`xsim`、`iverilog` 或 `verilator`，因此本次结论是工程文件和 RTL 的静态审计结果，未执行编译、综合、实现或仿真。

当前实现对合法参数的稳定态周期计数是明确的，但 `pulse_width_set` 对应低电平持续拍数，而不是常见定义下的高电平脉宽。对 `period_set = N`、`pulse_width_set = P` 且 `1 <= P <= N`：

- 计数器循环范围为 `0 ... N-1`；
- PWM 频率为 `f_clk / N`；
- 输出低电平持续 `P` 拍，高电平持续 `N-P` 拍；
- 高电平占空比为 `(N-P)/N`，低电平占空比为 `P/N`；
- 比较结果被寄存，观察同一时刻的 `time_cnt` 与 `pwm_out_reg` 时，输出相对计数状态滞后一拍。

这可能是设计者有意生成低有效 PWM，也可能是命名/极性与预期不一致。下一阶段重构前必须先冻结接口语义，本轮不调整。

## 2. 工程识别

| 项目 | 当前基线 |
|---|---|
| 工程路径 | `PWM_Controller/PWM_Controller.xpr` |
| 工程文件头 | Vivado v2026.1 (64-bit) |
| 目标 FPGA | `xc7a200tfbg484-2`，即 AMD/Xilinx Artix-7 XC7A200T、FBG484、速度等级 -2 |
| Board Part | 空；未绑定 Vivado board part |
| 工程类型 | Default / RTL |
| 设计源文件集 | `sources_1` |
| 设计 top | `pwm_controller` |
| 约束文件集 | `constrs_1`，类型为 XDC，但内容为空 |
| 仿真文件集 | `sim_1`，RTL simulation |
| 仿真 top | `pwm_controller_tb` |
| 活动仿真器 | XSim |
| 综合/实现 run | 定义了 `synth_1` 和 `impl_1`，目录与结果当前不存在 |
| IP / Block Design | 0 个 `.xci`、`.xcix`、`.bd` 或 IP checkpoint；当前未使用 IP |

工程头部为 Vivado 2026.1，综合/实现 flow 也是 2026；但 `.xpr` 中各仿真器版本字段仍包含 XSim/ModelSim/Questa 2025.2 等值。这属于工程元数据的版本不一致，建议下一阶段用实际 Vivado 2026.1 打开后重新验证 compile order 与仿真器设置。

### 2.1 现有源文件

| 用途 | 文件 | SHA-256（审计前） |
|---|---|---|
| 工程元数据 | `PWM_Controller/PWM_Controller.xpr` | `BEB707C79C88D4AF519B5BCE25A85C9185255D965526FD2983CDA78C43E237AE` |
| 设计 RTL | `PWM_Controller/PWM_Controller.srcs/sources_1/new/pwm_control.sv` | `A88AB70DFFA82B4CDD50D5D5C081AD6A07C87B527C3FDD10B116385341508BD0` |
| testbench | `PWM_Controller/PWM_Controller.srcs/sim_1/new/pwm_controller_tb.sv` | `3EFF9EBFE371EC1BF2D53967FF1052CD4B9ECE8583E4624CED2C51C9B28FBAE5` |

`pwm_controller_tb.sv` 位于 `sim_1`，所以其职责是仿真。`.xpr` 为它记录了通用的 synthesis/implementation/simulation `UsedIn` 属性，但它不在 `sources_1` 设计源文件集中。下一阶段可在 Vivado 中确认该文件明确设置为 simulation only。

### 2.2 当前目录性质

- `PWM_Controller.cache/`：Vivado 缓存；当前仅有少量工作区元数据。
- `PWM_Controller.hw/`：硬件管理器状态；当前有 `PWM_Controller.lpr`。
- `PWM_Controller.ip_user_files/`：IP 生成输出目录；当前为空。
- `PWM_Controller.sim/`：仿真输出目录；当前为空。
- `PWM_Controller.srcs/`：包含真正需要保留的 RTL 与 testbench，不能整体忽略。
- 当前没有 `PWM_Controller.runs/`、`PWM_Controller.gen/`、综合 checkpoint、bitstream 或 timing report。

## 3. PWM 实现原理

### 3.1 输入时钟

RTL 端口注释声明 `clk = 50 MHz`，testbench 用 20 ns 周期产生 50 MHz 时钟。工程没有 `create_clock` 约束，因此 50 MHz 目前只是源码和 testbench 的约定，尚未由 XDC 约束，也无法确认实际板级晶振、输入管脚和时钟质量。

设计中的所有功能寄存器都由 `posedge clk` 驱动，没有把计数器位、PWM 输出或组合逻辑结果当作新时钟。

### 3.2 reset

`reset_n` 是低有效异步复位。三个时序过程都采用：

```systemverilog
always_ff @(posedge clk, negedge reset_n)
```

复位时，周期寄存器、脉宽寄存器、计数器和输出寄存器全部清零。异步拉低可以立即复位，但释放没有同步器；如果硬件中 `reset_n` 在 `clk` 边沿附近释放，可能违反恢复/移除时间并造成不同触发器退出复位的拍次不一致。

testbench 在 40 ns 释放复位，而 20 ns 时钟的上升沿也发生在 40 ns；后续 `config_en` 和配置总线也在 80 ns、100 ns 等上升沿时刻改变。这些不同 `initial`/`always` 过程处于同一仿真时间槽，存在事件调度竞争，波形可能依赖仿真器执行顺序。

### 3.3 配置锁存

当 `config_en = 1` 时，`period_set` 和 `pulse_width_set` 在时钟上升沿锁存到 32 位寄存器，同时 `time_cnt` 清零。`config_en = 0` 时配置寄存器保持原值。

当前接口假设 `config_en`、`period_set` 和 `pulse_width_set` 已与 `clk` 同步，并在采样边沿满足建立/保持时间。如果这些信号来自另一时钟域、处理器异步接口或板外管脚，当前没有同步、握手或原子快照机制，可能出现亚稳态或周期/脉宽取自不同配置字的问题。

### 3.4 counter、period 与 frequency

`time_cnt` 为 32 位无符号计数器。对合法的 `period_set_reg = N >= 1`：

```text
0, 1, 2, ..., N-2, N-1, 0, ...
```

因此：

```text
T_pwm = N / f_clk
f_pwm = f_clk / N
```

若按注释使用 50 MHz：

| period_set | PWM 周期 | PWM 频率 |
|---:|---:|---:|
| 10 | 200 ns | 5 MHz |
| 15 | 300 ns | 3.333333 MHz |

计数器没有额外分频级。`period_set` 本身就是以输入时钟拍数表示的周期。

### 3.5 duty-cycle 与输出逻辑

输出条件为：

```systemverilog
time_cnt > (pulse_width_set_reg - 1'b1)
```

对于 `P >= 1`，等价于旧计数值 `time_cnt >= P` 时输出高。因此在稳定态且 `1 <= P <= N`：

| 参数 | 低电平拍数 | 高电平拍数 | 高电平占空比 |
|---|---:|---:|---:|
| `N=10, P=4` | 4 | 6 | 60% |
| `N=15, P=10` | 10 | 5 | 33.333333% |

`pwm_out_reg` 在独立的 `always_ff` 中读取上一拍的 `time_cnt`。由于非阻塞赋值语义，输出是注册后的比较结果，不会产生组合毛刺，但波形上输出相对更新后的 `time_cnt` 滞后一拍。配置写入的那个边沿，输出仍按旧配置与旧计数状态计算；下一拍才开始按新脉宽与已清零的计数器计算。

`pwm_out` 是模块输出 net，由连续赋值 `assign pwm_out = pwm_out_reg` 驱动。该结构可综合。

### 3.6 counter 位宽与边界

计数器和两个配置寄存器都是 32 位：

- 可直接表示的非零周期范围为 `1 ... 2^32-1` 个时钟拍；
- 在 50 MHz 下，最大非零周期约为 85.8993459 s；
- `period_set = 0` 时，`period_set_reg - 1` 下溢为 `32'hFFFF_FFFF`，计数器实际运行 `2^32` 拍后回零，而不是停用或报告非法值；
- `pulse_width_set = 0` 时，比较阈值也下溢为 `32'hFFFF_FFFF`，输出不会满足“大于阈值”，因此恒为低；
- `pulse_width_set >= period_set` 时，在通常非零周期范围内输出恒低；
- 当前没有输入范围检查、饱和、错误标志或明确的非法配置策略。

计数器在正常非零周期下会在到达终值时显式回零，不依靠自然溢出。真正的风险是减一运算对零输入的无符号下溢及其未文档化行为。

## 4. 代码检查结果

| 检查项 | 结论 | 严重度 | 证据与影响 |
|---|---|---:|---|
| 不合理时钟分频 | 未发现 | 通过 | 只使用输入 `clk`；没有生成、门控或把数据当时钟。计数器只是同步周期计数。 |
| blocking/non-blocking | RTL 未发现问题 | 通过 | 三个 `always_ff` 全部使用 `<=`。testbench 使用 blocking 赋值本身合理，但激励与 DUT 上升沿同一时刻，形成仿真竞争。 |
| 位宽问题 | 有边界风险 | 中 | 数据通路统一为 32 位；`32-bit - 1'b1` 会按表达式扩展计算，但零值减一产生 `32'hFFFF_FFFF`。建议后续使用显式 32 位常量并先处理零值。 |
| 溢出/下溢 | 存在 | 高 | `period_set=0` 和 `pulse_width_set=0` 产生减一后的无符号下溢，行为可能与接口预期不符。 |
| reset | 存在硬件与 TB 风险 | 高 | RTL 异步释放未同步；TB 又恰在 `posedge clk` 释放复位。 |
| 不可综合结构 | 设计 RTL 未发现 | 通过 | RTL 没有 `#delay`、`initial`、`forever` 或 `$stop`。这些结构只存在于 testbench，符合仿真用途。 |
| 潜在时序问题 | 无法签核 | 高 | 无 XDC、无 `create_clock`、无管脚/IOSTANDARD、无综合实现报告。32 位加法、减法、比较链在 50 MHz 下看似宽松，但必须以实现后的 WNS/TNS 为准。 |
| 跨时钟域 | 接口来源未知 | 中/高 | 若配置接口不是 `clk` 同步域，当前多位总线与 `config_en` 没有 CDC 保护。 |
| 踩时钟/派生时钟 | RTL 未发现；TB 存在边沿竞争 | 中 | RTL 只在 `posedge clk` 工作；TB 在上升沿同时改变 reset/config/data，无法保证确定性采样。 |
| 输出极性/命名 | 需要规格确认 | 高 | `pulse_width_set=P` 实际定义低电平宽度，高电平宽度为 `N-P`。若预期是常见的高有效脉宽，当前极性相反。 |
| 配置切换 | 存在一拍旧状态 | 中 | `config_en` 边沿锁存参数并清计数器，但输出寄存器同一边沿仍读取旧参数和旧计数器。无组合毛刺，但相位与过渡语义需要规格化。 |
| 自保持赋值 | 冗余但无功能错误 | 低 | `reg <= reg` 可省略；综合结果通常等价。 |
| testbench 完整性 | 不足 | 中 | 只有两个定向案例，没有 assertion、自检、边界值、频率/占空比自动测量或重配置过渡检查。 |

## 5. Git 提交边界

### 5.1 当前应提交 Git 的文件

当前工程还没有可替代 `.xpr` 的工程重建 Tcl，因此建议提交：

```text
PWM_Controller/PWM_Controller.xpr
PWM_Controller/PWM_Controller.srcs/sources_1/new/pwm_control.sv
PWM_Controller/PWM_Controller.srcs/sim_1/new/pwm_controller_tb.sv
docs/baseline_audit.md
```

后续新增时也应提交：

- 手写 RTL：`.v`、`.sv`、`.vhd`；
- XDC 约束；
- 自检 testbench 与仿真脚本；
- 可重建工程的 Tcl 脚本；
- IP 配置源，如 `.xci`、`.xcix`、`.bd`，以及自研 IP 源码；
- 源数据文件，如确实参与综合的 `.coe`/`.mem`，不能仅因扩展名像生成文件而忽略；
- README、接口规格和验证文档。

### 5.2 可选提交的文件

- `.wcfg` 波形配置：团队希望复现观察窗口时可提交；
- `.bit`、`.bin`、`.ltx`：只作为带版本、带器件与源提交号的正式 release artifact 保存，不建议混入日常源码提交；
- DCP：仅在明确采用增量编译、OOC IP 交付或跨团队 netlist 交付时保存；
- `.xpr`：目前应提交。未来若 `scripts/create_project.tcl` 已能从空目录重建工程，`.xpr` 可转为可选文件或生成文件。

### 5.3 应加入 `.gitignore` 的 Vivado 生成内容

建议规则如下；不要忽略整个 `*.srcs/`，因为当前 RTL 和 testbench 就在其中。

```gitignore
# Vivado workspace/cache
.Xil/
*.cache/
*.hw/
*.ip_user_files/
*.sim/
*.runs/
*.gen/

# Logs, journals, temporary databases
vivado*.jou
vivado*.log
vivado_pid*.str
*.wdb
*.pb
*.str

# Generated implementation artifacts
*.dcp
*.bit
*.bin
*.ltx
*.xsa
*.hwh
```

若团队选择在 Git release 中保存 bitstream，应对 release 目录使用例外规则，而不是从日常工程目录取消全部忽略。

## 6. 建议的仓库目录结构

下面是建议目标，不代表本轮移动任何文件：

```text
FPGA_XC7A200T/
├─ README.md
├─ .gitignore
├─ docs/
│  ├─ baseline_audit.md
│  ├─ interfaces/
│  └─ verification/
├─ hardware/
│  ├─ boards/
│  │  └─ BX72/
│  ├─ drivers/
│  │  └─ MDBL4/
│  └─ controllers/
│     └─ TMS320F28388D/
├─ fpga/
│  ├─ PWM_Controller/
│  │  ├─ rtl/
│  │  │  └─ pwm_controller.sv
│  │  ├─ tb/
│  │  │  └─ pwm_controller_tb.sv
│  │  ├─ constraints/
│  │  │  └─ BX72.xdc
│  │  ├─ ip/
│  │  ├─ scripts/
│  │  │  ├─ create_project.tcl
│  │  │  └─ run_checks.tcl
│  │  └─ project/
│  │     └─ PWM_Controller.xpr
│  └─ 01_LED_blik/
│     ├─ rtl/
│     ├─ tb/
│     ├─ constraints/
│     └─ scripts/
└─ releases/
   └─ README.md
```

工程脚本应使用相对路径，并以 `create_project.tcl` 作为可复现入口。硬件 PDF、管脚表与 FPGA 工程分开存放，但接口文档应记录所依据的板卡资料版本。

## 7. 下一阶段重构建议（本轮不执行）

建议按以下顺序开展，先冻结规格，再改 RTL：

1. 明确 PWM 极性与 `pulse_width_set` 语义：它表示高电平拍数、低电平拍数，还是比较阈值；定义 `0%`、`100%` 和非法值行为。
2. 明确配置生效时机：立即清零、当前周期结束后切换，或通过显式 update/ack 握手原子切换。
3. 为 `period_set=0`、`pulse_width_set=0`、`pulse_width_set>=period_set` 定义并实现确定策略，避免减一运算先发生下溢。
4. 若配置来自其他时钟域，增加 CDC 握手或异步 FIFO；多位总线不能只对单个 `config_en` 做简单双触发器同步。
5. 采用异步置位/复位、同步释放的 reset 结构，或根据系统复位树统一改成同步复位。
6. 决定输出是组合比较还是注册比较，并把一拍延迟及周期边界行为写入接口规格。
7. 根据最大所需周期参数化计数器宽度，避免固定 32 位在小范围用途中的冗余，同时保留明确的类型和位宽。
8. 增加 BX72 对应 XDC：时钟周期、时钟管脚、PWM 输出管脚、IOSTANDARD，以及必要的 input/output delay；约束必须与实际原理图和管脚表交叉核对。
9. 重写为无竞争的 self-checking testbench：在下降沿或 clocking block 驱动激励，加入 assertion、周期/占空比自动测量、边界值、随机配置和运行中重配置测试。
10. 建立可复现检查链：SystemVerilog lint、XSim 仿真、综合 DRC、实现、`report_timing_summary`、CDC/reset 检查；保存工具版本和关键报告摘要。
11. 用 Tcl 从源文件重建工程，减少 `.xpr` 中绝对路径和工具版本漂移带来的复现风险。

## 8. Git 状态、diff 与无功能改动证明

审计开始时在 `D:\Project\FPGA_XC7A200T` 执行：

```text
git rev-parse --show-toplevel
fatal: not a git repository (or any of the parent directories): .git
```

因此当前没有 Git HEAD、index 或工作树，`git status` 与 `git diff` 不可用；不能用 Git 证明“diff 为空”。本轮采用源文件 SHA-256 前后对比作为补充证据。审计完成后的结果应满足：

- `pwm_control.sv` 哈希仍为 `A88AB70DFFA82B4CDD50D5D5C081AD6A07C87B527C3FDD10B116385341508BD0`；
- `pwm_controller_tb.sv` 哈希仍为 `3EFF9EBFE371EC1BF2D53967FF1052CD4B9ECE8583E4624CED2C51C9B28FBAE5`；
- `PWM_Controller.xpr` 哈希仍为 `BEB707C79C88D4AF519B5BCE25A85C9185255D965526FD2983CDA78C43E237AE`；
- 本轮唯一预期新增文件为 `docs/baseline_audit.md`。

Git 初始化、`.gitignore` 创建、目录移动和任何 RTL 重构均留待后续阶段，本轮不执行。
