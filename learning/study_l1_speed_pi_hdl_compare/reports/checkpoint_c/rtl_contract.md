# C1：共同 RTL contract

唯一数值标准是 Checkpoint A 的 `models/speed_pi_fixed.slx`（B1），SHA256
`b87195c56830254e65ecc6b9b2d395c2e48c30319fd9c804e71474757742f26c`。
原始 PI 审计、datatype table 和 Checkpoint B 全部冻结。C/D 指任务书的自动生成 / 手写 RTL。

| 量 | 单位 / 类型 | 规则 |
|---|---|---|
| ref、meas | mm/s，signed32 FL20 | 每个输入完整 raw 范围对应 [-2048,2048) |
| error | signed33 FL20 | ref-meas，精确减法 |
| Kp / KiTs / Kaw | unsigned32 FL30 | raw 19363296 / 1549064 / 85899346 |
| P / inc | signed65 FL50 → signed40 FL30 | 全精度乘法后 Convergent + Saturate |
| AW | signed72 FL60 → signed40 FL30 | **上一有效事件**的 excess 乘 Kaw |
| x / x_next | signed32 FL30 | 积分限幅 ±536870912 raw（±0.5 A） |
| u / limited | signed42 FL30 | P + **旧 x**；内部输出限幅 ±1073741824 raw（±1 A） |
| excess | signed40 FL30 | u-limited，内部限幅量参与反馈 |
| 更新累加 | signed44 FL30 | 先 x+inc，再用45位减AW，饱和回44位，积分限幅，再转state |
| iq_ref | Apeak，signed25 FL15 | 内部 limited 做 Convergent + Saturate，再 hard-reset 选择0 |

所有显式存储转换都 Saturate；有损转换 ties-to-even，不能用截断或统一加半 LSB。
无损扩展必须 sign-extend。手写的 round20 / round30 / output_format 用 arithmetic floor 加
`guard & (sticky | retained_LSB)`，负数半值也按偶数舍入，进位在更宽临时量中完成后再饱和。
在声明输入和可达积分状态范围内，P <74 A、|excess|<74 A、|AW|<6 A、更新<13 A，
均有存储余量；RTL 仍保留 B1 指定的逐级 cast 和存储饱和。

每个事件的行为：

```
e = ref - meas
P = quantize(Kp * e); inc = quantize(KiTs * e)
AW = quantize(Kaw * old_excess)
u = cast42(P + old_x); limited = clip(u, -1, +1)
new_excess = cast40(u - limited)
candidate = cast32(clip(cast44(cast44(old_x + inc) - AW), -0.5, +0.5))
hard = pi_reset OR angle_init OR test_mode OR NOT enable
int_reset = hard OR (sat_abs(ref) < 0)
                OR (sat_abs(ref) > 0.5 AND cast33(sign(ref)*e) < -3)
iq_ref = hard ? 0 : cast25_FL15(limited)
new_x = int_reset ? 0 : candidate
```

B1 的 Signum 是 int32，但值域只有 -1/0/+1。手写 sign_product 用34位精确表示
e、-e、0，然后做同样的33位饱和；没有用无条件窄位取负。AbsRef 的最小负输入也饱和到
signed32 最大正值。0、0.5、-3 的比较都是 B1 的严格不等式。
hard/int_reset 不清除 new_excess；int_reset 单独发生时，当前 iq_ref 仍使用 old_x。

物理接口是 `handwritten/speed_pi_compare.sv`：

- clk 是唯一 50 MHz clock；init_reset 是同步、高有效的硬件初始化，优先于 global CE。
- clk_enable 是全局 CE。enable 是独立的算法 enable，不能混用。
- 7 项逻辑输入、14 项诊断/数值输出、ce_out 和 result_valid 两版全部一致。
- init_reset 清零输入寄存器、积分/previous-excess、输出保持寄存器和valid；trigger记忆初始化高。
  启动先送低 tick 至少2个CE时钟，首正常事件仍在0.9 ms。
- sample_tick 经过输入寄存器，用**上升沿**生成事件。保持高只执行一次；无事件不更新 x/d 或诊断。
- pi_reset/angle_init/test_mode/disable 在**有效事件**采样；空闲复位指令不能异步清状态。
- 两边都是1个输入寄存阶段、1个事件输出保持阶段。同一输入在 launch 边沿后驱动，
  下一边沿接受，再下一边沿提交：launch-to-valid 为2 clocks / 40 ns；accept-to-valid为1 clock。
- result_valid 是共享薄适配器的上升沿事件延迟两级CE寄存器；ce_out只是global CE。
  CE=0 时数据/状态/valid pipeline 保持，result_valid门控为0；恢复后待处理事件只提交一次。
- 正常源更新在0.9 ms、1.9 ms…，每1 ms一个事件（50000 clocks）；输出相位增加40 ns。
  Fresh TB 为避免驱动/采样竞争，在negedge驱动：下一posedge接受，随后posedge提交，
  drive-to-output=30 ns，#1观察为31 ns。若按上述posedge后launch约定，则为40 ns；
  两种说法有明确驱动边沿，accept-to-output均为1 clock，不做任意波形平移。
  无内部忙状态；最小事件间隔2 clocks，新增stress验证高低交替的连续事件。
  stress加速只验证离散事件排序，不把 KiTs 或正常调度周期改成40 ns。

适配器只做 CE/valid 对齐，不含 PI 运算、不新增数据pipeline、不删除诊断。
Vivado 使用同一顶层、同一原始 50 MHz XDC（所有输入/输出各2 ns预算）、相同 OOC flow。
没有 false/multicycle path。端口过多，采用内部IP OOC，不能解释成整板I/O timing。
