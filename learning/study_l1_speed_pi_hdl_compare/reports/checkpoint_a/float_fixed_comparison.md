# A2/A3：float / fixed comparison

验证版本：26.2.0.3386108 (R2026b)；2580 个 100-us 样本，258 个有效 speed tick。
输入从 `study_l1_generate_vectors.m` 生成；所有版本使用相同输入和 tick。饱和阈值按 limit/Kp 生成，不写死速度魔法值。

| Comparison | Result |
|---|---|
| 独立 float vs 原 PI 副本，14项输出/内部量 | max error = 0 |
| 真实 scheduler vs 独立输入 tick | 逐拍一致；first 0.9 ms，period 1 ms |
| B1 / B2 Simulink vs scalar fi | 全样本、全信号 physical / raw code bit-exact |
| 保存的三份 standalone SLX vs compare_tb 副本 | 分别仿真，14项输出逐样本一致 |
| reset / enable / int-reset / idle hold | 原 PI、float、B1、B2 一致 |

| Metric | B1 | B2 candidate |
|---|---:|---:|
| 输出饱和时刻/方向 mismatch 数 | 0 | 0 |
| 非饱和 iq_ref 最大偏差 (A) | 1.52135277977e-05 | 3.24425528691e-05 |
| 非饱和 iq_ref 最大偏差 (external LSB) | 0.498516878875 | 1.06307757241 |
| 积分状态最大偏差 (A) | 2.42387708904e-07 | 2.46812617036e-05 |
| iq_unlimited 最大偏差 (A) | 2.1910464465e-07 | 2.63046745344e-05 |
| 所有 iq_ref 最大偏差 (A) | 1.52135277977e-05 | 3.24425528691e-05 |

B1 的非饱和输出门槛为 2 LSB = 0.00006103515625 A，自动断言未放宽。B2 用于位宽/误差研究；未测量或声称资源节省。
B1/B2各3项 Gain 出现系数精度损失提示，standalone与对照台中数值均与 datatype table 的系数量化一致；这是已记录的系数量化，未出现非预期存储溢出。

覆盖零误差、小正/负误差、正/负饱和、持续 anti-windup、解饱和、饱和后反向、饱和中 reset/disable、re-enable、同 tick 和相邻 tick 的 reset、仅 idle 间出现的 reset、overspeed int-reset、角初始化和 Iq_Test_Mode。
另外验证：hard reset 时当拍 integrator 输出为旧状态；x_next=0；excess 未被 reset 清零。

`verification/tick_comparison.csv` 保存每个有效 tick 的原模型、float、B1、B2 数值，定点同时给 physical unit 与 raw code。完整 100-us 序列留作本地复核，精简后的 tick 表进入 Git。

限定：组件行为与本次输入范围证据；没有整机闭环、HDL、RTL、资源、时序或硬件验证。Checkpoint B 尚未开始。
