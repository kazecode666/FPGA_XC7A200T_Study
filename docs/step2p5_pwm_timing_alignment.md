# Step 2.5: Registered PWM Output Timing Alignment

## 问题

Step 2 中，`time_cnt` 与 `pwm_out_reg` 分别在两个时序过程中更新。由于非阻塞赋值在时钟沿结束后统一生效，输出比较使用的是更新前的 `time_cnt`，因此波形中 `pwm_out` 与更新后的 counter 相差一拍。

## 实现

本阶段采用 current/next-state 结构：组合逻辑先计算 `next_time_cnt`，再根据同一个下一计数状态计算 `next_pwm_out`，最后在同一个 `posedge clk` 时序过程中同时寄存两者。`pwm_out` 仍由 `pwm_out_reg` 驱动，保持寄存式输出，避免引入从 counter 到输出端口的组合路径。

当 `config_en` 有效时，下一计数状态立即设为 0，并直接使用本次输入的 `period_set` 和 `compare_value_set` 计算输出。配置时钟沿结束后，counter、配置寄存器和 PWM 输出描述同一份新配置。

在 `period_set_reg != 0` 的每个稳定采样点，关系为：

```text
pwm_out == (time_cnt >= compare_value_reg)
```

Step 2 的比较语义和边界行为保持不变：`N=0` 时 disabled/LOW；`C=0` 时恒 HIGH；`C=N` 或 `C>N` 时恒 LOW。

## XSim 2026.1 验证

使用 Vivado Simulator 2026.1 运行实际 behavioral simulation：

- Step 2 Case 1–8 全部 PASS。
- counter/PWM 对齐检查 `N=10, C=4`、`N=10, C=0`、`N=10, C=10`、`N=0, C=0` 全部 PASS。
- `N=10, C=4` 时，`time_cnt=4` 对应 `pwm_out=HIGH`。
- 仿真最终输出：`ALL STEP 2.5 PWM TESTS PASSED`。

本阶段未进行综合、实现、时序分析或 FPGA 上板验证。
