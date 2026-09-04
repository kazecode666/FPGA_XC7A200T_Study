# Step 3: PWM RTL Synthesis and Hardware Mapping

## 目标与环境

本阶段使用 Vivado 2026.1 对 `pwm_controller` 运行 RTL Synthesis，观察 SystemVerilog 状态与组合逻辑如何映射到器件 `xc7a200tfbg484-2` 的实际资源。本阶段不修改 PWM RTL 功能。

## 综合前预测

从 RTL 状态变量看，理论寄存状态需求约为：

| RTL 状态 | 位数 |
|---|---:|
| `period_set_reg` | 32 |
| `compare_value_reg` | 32 |
| `time_cnt` | 32 |
| `pwm_out_reg` | 1 |
| 合计 | 97 |

97 bit 是综合前的 RTL 层预测，不代表 Vivado 最终一定使用 97 个 FF。综合器可以根据可观察行为、控制条件和器件映射进行优化，最终数量必须以实际综合网表为准。

## 综合结果

`synth_1` 实际运行成功：

```text
Synthesis status: synth_design Complete!
Synthesis progress: 100%
```

这说明当前 RTL 能够被 Vivado 2026.1 转换为目标器件的综合网表。

## Utilization 摘要

数据来自 [`step3_synth_utilization.rpt`](reports/step3_synth_utilization.rpt)：

| Resource | Used | 主要来源 |
|---|---:|---|
| Slice LUTs | 106 | counter 算术、周期判断、PWM 比较和 next-state 多路选择 |
| Slice Registers / FF | 97 | 三组 32-bit 状态寄存器和 1-bit `pwm_out_reg` |
| CARRY4 | 24 | 32-bit 递增、减一和比较相关的快速进位逻辑 |
| IBUF | 67 | `clk`、`reset_n`、`config_en` 和两组 32-bit 配置输入 |
| OBUF | 1 | `pwm_out` |
| BUFG | 1 | `clk` 全局时钟缓冲 |
| Bonded IOB | 68 | 67 个输入端口和 1 个输出端口 |
| Block RAM / DSP | 0 / 0 | 当前设计不需要存储器或乘法器资源 |

LUT primitive 的实际分布为：LUT1 32、LUT3 1、LUT4 74、LUT5 41、LUT6 6。Slice LUT 总数是 106，因为 report utilization 会按 LUT combining 规则调整物理 LUT 统计，不能直接把各 LUT primitive 数量相加作为 Slice LUT 数量。

实际使用 97 个 FF，与综合前的 97-bit 状态预测一致。综合器没有裁剪这些状态位，因为当前完整宽度的周期、比较值和 counter 都会影响可观察输出。

## RTL 到硬件的对应关系

| RTL | Elaborated Design | Synthesized Design |
|---|---|---|
| `period_set_reg[31:0]` | 32-bit 异步复位寄存状态 | 32 个 FDCE |
| `compare_value_reg[31:0]` | 32-bit 异步复位寄存状态 | 32 个 FDCE |
| `time_cnt[31:0]` | 32-bit counter 状态以及加法、减法、比较和 mux | 32 个 FDCE，相关 LUT/CARRY4 |
| `pwm_out_reg` | 1-bit 异步复位寄存状态 | 1 个 FDCE，相关比较和选择逻辑映射到 LUT/CARRY4 |
| `next_time_cnt` | 组合 next-state 信号 | 0 个独立综合网表 cell，不增加 FF |
| `next_pwm_out` | 组合 next-state 信号 | 0 个独立综合网表 cell，不增加 FF |

FDCE 是带 clock enable 和异步 clear 的 D 触发器。Utilization 的寄存器类型表显示 97 个寄存器均属于 clock-enable、asynchronous-reset 类。`period_set_reg <= period_set_reg` 和 `compare_value_reg <= compare_value_reg` 的保持语义没有生成额外反馈寄存器；Vivado 将更新条件识别为寄存器 enable/保持控制。低有效 `reset_n` 被组合为 FDCE 的异步 clear 控制。

Elaborated Design 中实际出现 1 个 `RTL_ADD`、1 个 `RTL_SUB`、2 个 `RTL_GEQ`、1 个 `RTL_LT` 和多组 `RTL_MUX`。这层结构仍接近源码中的 `time_cnt + 1`、`period_set_reg - 1`、周期判断、PWM 阈值判断和配置选择。

Synthesized Design 已经展开并优化为 97 个 FDCE、154 个 LUT primitive、24 个 CARRY4，以及输入、输出和时钟 buffer。综合网表中的 24 个 CARRY4 分布在 `time_cnt` 和 `pwm_out_reg` 相关逻辑命名下，说明 counter 算术、周期比较和 PWM 比较共同使用了器件快速进位结构。综合优化已经合并和重命名部分逻辑，因此不能把每一个 CARRY4 无歧义地分配给某一条 RTL 表达式。

## Elaborated 与 Synthesized Schematic

Vivado 的 RTL elaboration 和 synthesized netlist 均已实际打开并查询：

- Elaborated Design 保留 register、adder、subtractor、greater-or-equal comparator、less-than comparator 和 mux 等高层结构，适合从 RTL 阅读数据流。
- Synthesized Design 显示 FDCE、LUT、CARRY4、IBUF、OBUF 和 BUFG 等 7-series primitive，适合观察经过优化后的器件映射。
- `period_set_reg`、`compare_value_reg`、`time_cnt` 和 `pwm_out_reg` 均能在综合网表命名中识别。`next_time_cnt` 与 `next_pwm_out` 在展开层作为组合逻辑存在，在综合网表中已被吸收到 LUT/CARRY4/连接逻辑，没有独立寄存器。

## Messages

`synth_1/runme.log` 的实际综合摘要为：

| Severity | Count |
|---|---:|
| ERROR | 0 |
| CRITICAL WARNING | 0 |
| WARNING | 0 |

未发现 latch inference、multiple drivers、combinational loop、unresolved reference、width mismatch、重要逻辑被裁剪、时钟综合问题或意外 constant propagation。Utilization 同时确认 Register as Latch 为 0、Black Boxes 为 0。

打开工程时 Vivado 另有一条 `[Project 1-5713]` 警告：工程的 board part 为空且无法找到，因此 Vivado 清除了 BoardPart 属性。当前工程明确指定器件 `xc7a200tfbg484-2`，所以该工程元数据警告不影响本次器件级 Synthesis；它也说明当前尚未建立板卡定义和引脚映射。

## 当前验证边界

当前工程没有 XDC，综合日志明确报告 `No constraint files found`。因此本阶段的 Synthesis PASS 只证明 RTL 可以转换成目标 FPGA 网表，并不表示 50 MHz timing 已通过。

本阶段未运行 Implementation、Place Design、Route Design、Timing Sign-off 或 Generate Bitstream，也未增加 pin constraints，未进行 FPGA 上板验证。
