# Step 4：50 MHz 约束、物理实现与 Post-Route Timing

本阶段把 Step 2.5 的 PWM RTL 映射到真实 FPGA site 和布线资源，建立默认实现策略的学习基线。RTL 和 testbench 均未修改；不重复研究 PWM 功能规格。

## 前置状态与复现

- Step 3 PR #4 已于 2026-09-06 合并，main merge commit 为 `10a38b055a5115b2716e2e1bd733470db1c21876`。
- 从更新后的 main 创建 `step4-implementation-timing`。
- main 已包含 Step 3 Tcl、说明文档及综合资源报告。
- RTL 保留 `compare_value_set`、`next_time_cnt`、`next_pwm_out`、寄存器输出与 counter/output alignment。
- 工具：Vivado 2026.1；器件：`xc7a200tfbg484-2`；Design Top：`pwm_controller`。

在仓库根目录执行：

```powershell
& 'E:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat' -mode batch -nojournal -nolog -source scripts/step4_implementation_timing.tcl
```

脚本打开现有工程，检查 top、part、XDC fileset/UsedIn 和默认 strategy；重置并重跑 synth_1，再运行 impl_1 到 route_design，检查状态和进度，最后打开 routed design 导出报告。`get_clocks` 在打开综合/实现网表后验证，因为只有打开设计后时钟对象才可查询。工具生成的运行数据库留在本地，不进入 Git。

## 第一个正式时钟约束

`PWM_Controller.srcs/constrs_1/new/pwm_timing.xdc` 只有一个有效约束：

```tcl
create_clock -name sys_clk -period 20.000 [get_ports clk]
```

50 MHz 对应 20 ns。RTL 中的“50 MHz”注释只向人解释设计意图，不会给静态时序分析器建立时钟。XDC 的 `create_clock` 才定义时钟端口、名称与周期；默认波形为 rise 0 ns / fall 10 ns。

工程引用明确启用 synthesis 和 implementation。两阶段均实际返回 `get_clocks = sys_clk`、`PERIOD = 20.000 ns`。没有额外 clock uncertainty、I/O delay、false path 或 multicycle path 约束。

## Implementation 的实际含义

```text
RTL → synth_design → FPGA primitives
    → opt_design → place_design → phys_opt_design → route_design
```

综合决定逻辑结构及 LUT、FDCE、CARRY4 等映射。`opt_design` 优化网表，`place_design` 把实例放入器件 site，`route_design` 使用真实连线资源连接实例。当前 `Vivado Implementation Defaults` 自动执行了 post-place `phys_opt_design`；没有手工切换 strategy 或反复物理优化。

Synthesized Design 可查看 primitive 和逻辑连接，但还没有最终的物理位置、路由和实际互连延迟。Implemented Design 包含 LOC/BEL、布线以及 post-route timing。本次报告头均标识 `Design State: Routed`，不能用综合估计时序代替这些结果。

## 执行结果

| 阶段 | Status | Progress | 结论 |
|---|---|---|---|
| synth_1 | synth_design Complete! | 100% | PASS |
| impl_1 | route_design Complete! | 100% | PASS |

`opt_design`、`place_design` 和 `route_design` 均实际完成。Implementation PASS 表示完成本轮物理实现，不等于完整板级时序签核。

## Timing Summary

来源：[post-route timing summary](reports/step4_timing_summary.rpt)。

| 指标 | 实测值 |
|---|---:|
| WNS | 13.349 ns |
| TNS | 0.000 ns |
| Setup failing / total endpoints | 0 / 33 |
| WHS | 0.272 ns |
| THS | 0.000 ns |
| Hold failing / total endpoints | 0 / 33 |
| Worst pulse-width slack (WPWS) | 9.500 ns |
| Total pulse-width negative slack (TPWS) | 0.000 ns |
| Pulse-width failing / total endpoints | 0 / 98 |

WNS（Worst Negative Slack）是最差 setup slack；无违例时本报告仍给出正的最小裕量。Setup 检查数据是否来得太晚：`setup slack = required time - arrival time`。WNS ≥ 0 表示当前受约束路径无 setup violation。TNS 累加各 failing endpoint 最差的负 setup slack，不能把报告中所有可能路径简单重复累加。

Hold 检查数据是否变化得太早：`hold slack = arrival time - required time`，与 setup 的减法方向相反。WHS 是最差 hold slack，THS 是各 failing endpoint 的负 hold slack 总和。本次 WHS > 0，THS = 0。

97 个 FF 均有时钟，但这不意味着 97 个 D 引脚都有完整外部输入时序预算。报告中的 33 个内部同步数据终点是计数器 32 位和 PWM 输出寄存器；64 位配置寄存器的外部输入路径仍缺少 input delay。

## 一条实际 Worst Setup Path

来源：[5 条 worst setup paths](reports/step4_worst_setup_paths.rpt)。

| 项目 | 实测结果 |
|---|---|
| Startpoint（报告 Source） | `period_set_reg_reg[19]/C` |
| 数据发射引脚 | `period_set_reg_reg[19]/Q` |
| Endpoint | `pwm_out_reg_reg/D` |
| Start / end site | `SLICE_X4Y124` → `SLICE_X1Y118` |
| Path type | Setup / Max / Slow corner |
| Requirement | 20.000 ns |
| Data path delay | 6.617 ns |
| Logic delay | 2.607 ns（39.399%） |
| Route delay | 4.010 ns（60.601%） |
| Logic levels | 11：7 CARRY4 + LUT1 + LUT4 + LUT5 + LUT6 |
| Required time | 24.346 ns |
| Arrival time | 10.997 ns |
| Slack | 13.349 ns |

数据从起点 FF 的 clock-to-Q（0.379 ns）出发，经过 LUT、CARRY4 及路由，到达 PWM 输出 FF 的 D 引脚。这里 `6.617 = 2.607 + 4.010 ns`；Vivado 的 logic delay 已包含 clock-to-Q 等器件数据弧延迟，不能再把它额外加一遍。

Required time 不直接等于 20 ns，因为报告还计入目的时钟插入延迟、clock pessimism removal、uncertainty 和 endpoint setup 弧。Arrival time 同样包含源时钟插入延迟。报告以更高精度计算，再将各值显示到 0.001 ns。

本例路由占数据延迟约 60.6%。综合知道需要哪些逻辑，实现后才知道资源在哪里、互连怎么走，所以 post-route timing 比 synthesis estimated timing 更接近这一物理布局的硬件行为；最终板级接口仍取决于后续真实约束。

## Worst Hold Path

来源：[5 条 worst hold paths](reports/step4_worst_hold_paths.rpt)。

| 项目 | 实测结果 |
|---|---|
| Startpoint（报告 Source） | `time_cnt_reg[0]/C` |
| Endpoint | `time_cnt_reg[0]/D` |
| Site | `SLICE_X3Y113` |
| Path type | Hold / Min / Fast corner |
| Data path delay | 0.363 ns |
| Logic / route | 0.186 / 0.177 ns |
| Required time | 1.679 ns |
| Arrival time | 1.952 ns |
| Slack | 0.272 ns |

路径经过本位 Q、LUT4，再返回 D。最短路径也必须有足够延迟，避免时钟沿之后过早破坏刚采样的数据。显示值相减得到约 0.273 ns，与报告 0.272 ns 的 0.001 ns 差异来自显示舍入，结论采用 Vivado 原始 slack 字段。

## check_timing 与约束覆盖范围

来源：[check_timing、route status 与 DRC](reports/step4_check_timing.rpt)。

| 检查项 | 结果 | 含义 |
|---|---:|---|
| no_clock | 0 | 寄存器时钟已覆盖 |
| constant_clock | 0 | 未发现常量时钟 |
| pulse_width_clock | 0 | 没有仅具 pulse-width 检查的时钟引脚；不表示没做 pulse-width 检查 |
| unconstrained_internal_endpoints | 0 | 未发现此检查定义下的内部最大延迟未约束终点 |
| no_input_delay | 66 | period_set[31:0]、compare_value_set[31:0]、config_en、reset_n |
| no_output_delay | 1 | pwm_out |
| multiple_clock / generated_clocks | 0 / 0 | 未发现多时钟到达或生成时钟定义问题 |
| loops / latch_loops | 0 / 0 | 未发现组合环或 latch 环 |
| partial_input_delay / partial_output_delay | 0 / 0 | 没有只写一半的 I/O delay |

Unconstrained Path Table 明确包含 `sys_clk → (none)` 和 `(none) → sys_clk`。对应外部输出和外部输入路径的 slack 显示 `inf`，意味着缺少时序要求，不能理解为无限裕量或测试通过。单个 sys_clk 下的内部寄存器路径有时序预算；外部接口的时钟关系和到达/接收要求尚未定义，不能据此认定外部输入同步或 CDC 安全。

`reset_n` 驱动异步复位，列在 no_input_delay 中。当前报告没有给出可用于签核的 reset recovery/removal 数值；“Clock Pessimism Removal”是时钟悲观消除，不是异步复位 removal 检查。未添加 reset false path，也未把缺少 recovery/removal 结论写成 PASS。复位释放相对时钟的关系、同步释放架构与恢复/移除验证留待后续设计决策。

输入延迟需要外部器件输出时序、相对时钟关系和 PCB delay；输出延迟需要接收端 setup/hold 和板级走线信息。现在没有这些事实，所以不编造 1/2/5 ns 的约束。

**Post-route timing for the currently constrained 50 MHz internal synchronous paths passes. Full board-level timing sign-off has not been performed because external I/O timing constraints are not yet defined.**

## 资源、时钟与 Placement

来源：[post-implementation utilization](reports/step4_impl_utilization.rpt) 与 [clock utilization](reports/step4_clock_utilization.rpt)。

| 资源 | Step 3 synthesis | Step 4 post-route |
|---|---:|---:|
| FF / FDCE | 97 | 97 |
| Slice LUTs | 106 | 105 |
| CARRY4 | 24 | 24 |
| IBUF / OBUF | 67 / 1 | 67 / 1 |
| BUFG | 1 | 1 |
| BRAM / DSP | 0 / 0 | 0 / 0 |

105 个物理 LUT 占 134600 个 LUT 的 0.08%；97 FF 占 269200 个 FF 的 0.04%；使用 47 个 Slice（0.14%）。逻辑相对 XC7A200T 很小，但当前把配置总线直接暴露为顶层端口，68 个 IOB 占可用 bonded IOB 的 23.86%，不能把逻辑占用比例套用到 I/O。

LUT 的物理占用统计包含 O5/O6 combining：57 个仅使用 O6，48 个同时使用 O5/O6，共 105 个物理 LUT。实现后的 LUT primitive 数量不是这个物理资源数，不能直接逐类型相加后当作 Slice LUTs。本轮加入时钟约束后重新综合的本地 `pwm_controller_utilization_synth.rpt` 已经是 105 LUT；post-route 仍是 105，因此不能把相对 Step 3 减少的 1 LUT 归因于 place/route。时钟约束会影响综合优化/映射，本轮 primitive 分布为 LUT4=76、LUT5=35、LUT1=32、LUT6=10；未修改 RTL，也不能声称删除了功能逻辑。

`sys_clk` 从 `clk` 端口经过 `clk_IBUF_inst`（`IOB_X0Y128`），到 `clk_IBUF_BUFG_inst`（`BUFGCTRL_X0Y0`），再通过 `clk_IBUF_BUFG` 全局时钟网络驱动 97 个 clock loads、0 个 non-clock loads。只使用 1/32 个 BUFGCTRL 资源，负载集中在一个 clock region：`X0Y2`。

实测 placement inventory 给出所有 primitive 的 LOC/BEL；Slice 实例分布范围为 `X0..X6 / Y113..Y124`。I/O 由实现器自动临时放置，报告中 clk 的 U20、pwm_out 的 P20 等位置只是本次实现结果，**不是验证过的 BX72 引脚映射**，也没有写入 XDC。clock report 的 `Constraint: None` 指物理位置约束，不表示缺少 sys_clk 的 20 ns 时序约束。

## Methodology、Messages 与 DRC

GUI 检查记录：已在 Vivado 打开本轮 `pwm_controller_routed.dcp`，查看 Device 全器件布局、X0Y2 小区域的实例分布，以及 `Step4_Setup` 的 5 条 setup 路径。第一条路径的 GUI 数据与正式文本报告一致，Path Properties 显示 source、destination 和 13.349 ns slack。旧工程窗口未刷新 batch run 状态，`open_run impl_1` 在该旧 GUI 报告未启动，因此改为打开本轮实际生成的 routed checkpoint；batch 的 open_run 与正式报告均成功。随后用户要求停止 Computer Use，路径高亮未完成验证，未声称完成该项 GUI 操作。实际 LOC、逐段 routed net 和 logic/route delay 由正式报告保留。

来源：[message summary](reports/step4_messages.txt)、[methodology](reports/step4_methodology.rpt) 和 check_timing 文件末尾的独立 DRC。

| 证据范围 | Error | Critical Warning | Warning | Advisory |
|---|---:|---:|---:|---:|
| synth_1 runme.log | 0 | 0 | 0 | 不适用 |
| impl_1 runme.log | 0 | 0 | 0 | 不适用 |
| 最终批处理外层输出 | 0 | 0 | 2 | 不适用 |
| 独立 post-route methodology violations | 0 | 0 | 67 | 0 |
| 独立 post-route DRC violations | 0 | 2 | 1 | 0 |

这些是不同口径，不能把 run log 的 0 warning 写成“设计没有警告”。

- `TIMING-18`：67 个 missing I/O delay，属于当前阶段预期覆盖缺口；完整签核前必须根据真实接口处理。
- `NSTD-1` / `UCIO-1`：各 1 个 Critical Warning，分别涉及全部 68 个逻辑端口的默认 IOSTANDARD / 未由用户指定物理位置。后续真实板级 top 必须处理；本轮不猜引脚、不降级 DRC severity。
- `CFGBVS-1`：1 个 Warning，配置 bank 电压属性尚未设置。后续结合真实板卡确定 CFGBVS / CONFIG_VOLTAGE，本轮不编造。
- 外层 `[Project 1-5713]`：原工程空 BoardPart 提示，不阻止指定 FPGA part 的实现。
- 外层 `[Vivado 12-1017]`：重置 synth_1 时部分旧 run 文件未能清除；当时另一个 Vivado GUI 打开着旧综合网表，可能存在文件占用。没有手工批量删除；本轮新的综合和实现进程均实际运行，并由当前报告时间、完成状态及 276/276 routable nets 完全布线共同验证，不能仅凭旧 DCP 判断成功。

Route status：472 logical nets，其中 196 个无需外部路由的内部连接，276 个 routable nets 全部 fully routed，routing errors = 0。本轮没有需要修改 RTL 的 blocker；板级约束缺口是后续签核前的必要工作。

## 范围声明

未做真实 PACKAGE_PIN assignment、IOSTANDARD、DRIVE/SLEW/PULLUP/PULLDOWN；未做完整 I/O timing；未添加 false path 或 multicycle path；未生成 bitstream；未上板、未打开 Hardware Manager、未执行 ILA 或示波器测试。RTL 与 testbench 无修改，没有继续 Step 5。
