# A3：datatype table

范围来源：本地真实 PI 的 A2 测试结果 `verification/observed_ranges.csv`；不是整机 plant 范围证明。
先用 float 结果确认工作量级，再选 B1 保守精度和 B2 缩短位宽候选。B1 为后续 C/D 唯一 golden model。

| Signal | Observed / required range | Signed | B1 WL | B1 FL | B1 LSB | B2 WL | B2 FL | B2 LSB |
|---|---|---|---:|---:|---:|---:|---:|---:|
| v_ref / v_meas | test: +/-110.9048598 / [-0.23456,10]; input contract: each [-2048,2048) | True | 32 | 20 | 9.53674316406e-07 | 28 | 16 | 1.52587890625e-05 |
| speed error | [-110.90486, 110.90486]; representable [-4096,4096) | True | 33 | 20 | 9.53674316406e-07 | 29 | 16 | 1.52587890625e-05 |
| Kp | 0.018033474852681124 | False | 32 | 30 | 9.31322574615e-10 | 24 | 22 | 2.38418579102e-07 |
| KiTs | 0.0014426779882144898 | False | 32 | 30 | 9.31322574615e-10 | 24 | 22 | 2.38418579102e-07 |
| Kaw | 0.08 | False | 32 | 30 | 9.31322574615e-10 | 24 | 22 | 2.38418579102e-07 |
| P product result | [-2, 2]; full input contract: about +/-73.865 | True | 40 | 30 | 9.31322574615e-10 | 28 | 18 | 3.81469726562e-06 |
| KiTs product result | [-0.16, 0.16]; full input contract: about +/-5.91 | True | 40 | 30 | 9.31322574615e-10 | 28 | 18 | 3.81469726562e-06 |
| anti-windup term | [-0.12, 0.12]; full input contract: magnitude <6 | True | 40 | 30 | 9.31322574615e-10 | 28 | 18 | 3.81469726562e-06 |
| excess / previous excess | [-1.5, 1.5]; full input contract: magnitude <74 | True | 40 | 30 | 9.31322574615e-10 | 28 | 18 | 3.81469726562e-06 |
| integrator / x_next | [-0.5, 0.5]; algorithm limit +/-0.5 | True | 32 | 30 | 9.31322574615e-10 | 20 | 18 | 3.81469726562e-06 |
| iq_unlimited / iq_limited internal | [-2.5, 2.5]; full input contract: magnitude <75 | True | 42 | 30 | 9.31322574615e-10 | 30 | 18 | 3.81469726562e-06 |
| integrator accumulation | x + KiTs*e - AW; full input contract: magnitude <13 | True | 44 | 30 | 9.31322574615e-10 | 32 | 18 | 3.81469726562e-06 |
| iq_ref external | algorithm limit +/-1; compatible with existing FOC | True | 25 | 15 | 3.0517578125e-05 | 25 | 15 | 3.0517578125e-05 |

## 转换规则

- 每个 Gain 的系数类型、输出类型、每个 Sum 的累加器和输出类型均显式指定，见 `study_l1_types.m` 和 `study_l1_build_pi.m`。
- 所有有损转换使用 **Convergent（ties to even）**；算术存储 overflow 为 **Saturate**；没有 wrap。算法的 ±1 / ±0.5 限幅器独立于存储饱和。
- 输入先量化，error 作精确减法：B1 33/20，B2 29/16。复位阈值用相应输入/error 格式，0、0.5、-3 均精确可表示。
- B1 error×coefficient 全精度中间乘积为 signed **65/50**，量化到 work **40/30**；B2 为 signed **53/38**，量化到 **28/18**。
- B1 previous-excess×Kaw 全精度中间乘积 signed **72/60**；B2 为 signed **52/40**。之后转为相应 work 格式。
- P+x 与积分更新使用累加器 B1 **44/30**、B2 **32/18**。P+x 输出转 sum；积分更新先限幅再转 state；excess 使用内部限幅前后量相减。
- 输出格式转换位于内部 ±1 限幅之后、hard reset 输出选择之前。anti-windup 反馈使用内部 `u-l`，不使用外部 15-fraction 输出的量化差。
- UnitDelay 从已显式量化的输入继承 state / work 类型；初值0精确表示。
- 实际 Simulink ToWorkspace 保留 fi 类型；每个 raw code 与独立 scalar fi 运算核全样本、全信号比较。`observed_ranges.csv` 给出实际 WL/FL 与存储边界余量。
- 声明输入区间 [-2048,2048) 之外不属于数值保证；复位比较阈值极近点也可能受输入量化影响。本次向量覆盖实际阈值及边界，未宣称对所有实数输入逐点等价。
- B2 的12小数位试选会把 8.0001 mm/s 量化为8，使 sign(v_ref)*e<-3 的 int-reset 丢失；因此保留16输入小数位。此调整保持原严格不等式和参数，没有改变算法。

## 系数量化

| Format | Coefficient | raw code | Quantized value | Error |
|---|---|---:|---:|---:|
| B1 | Kp | 19363296 | 0.018033474683761597 | -1.6891952767106311e-10 |
| B1 | KiTs | 1549064 | 0.0014426782727241516 | 2.8450966170663616e-10 |
| B1 | Kaw | 85899346 | 0.080000000074505806 | 7.4505804303903744e-11 |
| B2 | Kp | 75638 | 0.018033504486083984 | 2.9633402860024249e-08 |
| B2 | KiTs | 6051 | 0.0014426708221435547 | -7.166070935217192e-09 |
| B2 | Kaw | 335544 | 0.079999923706054688 | -7.6293945314165335e-08 |
