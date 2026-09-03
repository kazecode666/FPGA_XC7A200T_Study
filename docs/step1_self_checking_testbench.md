# Step 1: Self-Checking PWM Testbench

## 目的

验证当前 PWM RTL 的真实稳定态行为，不修改 RTL 语义。testbench 在 `negedge clk` 改变 reset/config 输入并采样 `pwm_out`，避免与 DUT 的 `posedge clk` 非阻塞更新发生仿真竞争。checker 先同步到稳定的 HIGH→LOW 边界，再自动测量一个完整周期的 LOW、HIGH 和总拍数。

## 测试结果

实际工具：Vivado Simulator / XSim 2026.1，RTL simulation。

| Case | Period | Pulse width | Expected LOW/HIGH/TOTAL | Result |
|---:|---:|---:|---:|---|
| 1 | 10 | 4 | 4 / 6 / 10 | PASS |
| 2 | 15 | 10 | 10 / 5 / 15 | PASS |
| 3 | 8 | 1 | 1 / 7 / 8 | PASS |
| 4 | 8 | 7 | 7 / 1 / 8 | PASS |

仿真最终输出：`ALL PWM TESTS PASSED`。

## 留待 Step 2

- `period_set = 0`；
- `pulse_width_set = 0`；
- `pulse_width_set >= period_set`；
- `pulse_width_set` 当前表示 LOW width；
- RTL reset 同步策略。
