# Checkpoint A 完成 / STOP

来源 main：`944bd702377a2a90acea720f8fdb575781639a2d`，PR36/PR37已合并。
原分支 `codex/issue35-interactive-cosim`、本地修改与287个原文件哈希见 `workspace_preflight.json`。
在同一原始工作树建立 `codex/study-l1-checkpoint-a`，切换基线只新增任务书，未覆盖用户文件。

| 项目 | Fresh verification |
|---|---|
| A1 | 真实 SLX + 实际 ModelWorkspace参数 + SID连接/复位审计完成 |
| Speed task | first 0.9 ms，period 1 ms；真实function-call/scheduler逐拍一致 |
| A2 | 2580个100-us样本 / 258个speed tick，14项float与原PI副本误差0 |
| 保存的standalone模型 | float、B1、B2分别仿真，与compare_tb逐样本一致 |
| B1 | 非饱和iq误差0.498516879输出LSB，小于2 LSB门槛 |
| B2 | 非饱和iq误差1.063077572输出LSB |
| 定点核复核 | B1/B2所有信号physical与raw code对独立scalar fi bit-exact |
| 控制语义 | saturation方向/时刻、reset/enable、overspeed边界一致；idle保持 |
| 非预期存储溢出 | 未出现；实际位宽和存储边界余量单独记录 |
| 用户文件 | 原287项哈希/缺失状态保持，源SLX SHA256未变 |

真实算法的核心是 `u=Kp*e+x_old`，`d_next=u-clip(u,1)`，
`x_next=int_reset?0:clip(x_old+KiTs*e-Kaw*d_old,0.5)`，
`iq_ref=hard_reset?0:clip(u,1)`。
**excess延迟状态没有reset门控**；int-reset只覆盖下一积分状态，输出仍先用旧积分状态。
完整hard/int复位逻辑、参考来源与外层选择见 `current_speed_pi_audit.md`。

B1使用内部30位小数，外部输出保持signed25/15；B2输入需保留16位小数，12位试选丢失overspeed复位边界，未改变原严格不等式或调参。
位宽、系数量化、完整乘积和累加器规则见 `datatype_table.md`。
数值指标及覆盖见 `float_fixed_comparison.md`；精简证据在 `verification/`。
三份PNG已导出，B1图形已检查，学习模型保持原生可编辑SLX。

未解决问题：无Checkpoint A阻塞。所有实数近阈值输入的浮点/定点逐点等价没有被宣称；HDL兼容性、资源、latency、时序和整机闭环属于后续gate，本次未验证。

本阶段未调用HDL Coder、未生成RTL/bitstream、未改FOC/plant/PI参数、未保存原主SLX。
按fresh verification → commit → push → GitHub汇报完成后 **STOP，等待ChatGPT Review**。
