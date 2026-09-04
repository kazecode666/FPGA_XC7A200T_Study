# Step 2: PWM Compare Value Semantics

## 规格

定义 `N = period_set`、`C = compare_value_set`。当 `N > 0` 时，counter 稳定运行于 `0 ... N-1`，比较器采用：

```text
counter >= C  -> PWM HIGH
counter < C   -> PWM LOW
```

在 `0 < C < N` 的稳定工作区内：

```text
LOW clocks  = C
HIGH clocks = N - C
HIGH duty   = (N - C) / N
```

`compare_value` 是硬件比较阈值，不是 pulse width，也不是 duty。

## 边界行为

| 条件 | PWM 行为 |
|---|---|
| `N = 0` | disabled，counter 保持 0，PWM LOW |
| `N > 0, C = 0` | PWM 恒 HIGH，100% HIGH |
| `N > 0, C = N` | PWM 恒 LOW，0% HIGH |
| `N > 0, C > N` | 保留原始比较值，PWM 恒 LOW |

`time_cnt` 和 `pwm_out_reg` 仍在独立的 `posedge clk` 时序过程中更新。`pwm_out_reg` 比较的是该上升沿之前的 `time_cnt`，所以波形中输出相对更新后的 counter 存在一拍视觉错位；Step 2 有意保留此寄存式输出架构。

## XSim 2026.1 结果

Case 1–4 的正常 PWM 回归，以及 Case 5–8 的恒高、恒低和 disabled 边界测试均实际 PASS。仿真最终输出：`ALL STEP 2 PWM TESTS PASSED`。
