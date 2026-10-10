# Study-L1：速度 PI 的 HDL Coder 与手写 SystemVerilog 最终报告

Checkpoint D 的三组系统比较完成，状态为 `COMPLETE_D_WITH_HAND_SETUP_VIOLATION`。三组都通过原 Step7D 的 speed acceptance 和本次调度、hold、故障与实际 B1 raw-code 检查。**Hand SV 仍保留 Checkpoint C 的 50 MHz WNS = -1.957 ns，setup 未通过；系统联合仿真通过不能说明它已有 50 MHz 上板条件。** 等待本次 GitHub / ChatGPT Review，不自动开始后续任务。

主系统比较仅为原 Simulink Speed PI、Checkpoint B HDL Coder baseline 和 Hand SV，三组都接同一份 handwritten FOC RTL。C 的 AW CSD 只出现在历史单选项资源对比表中，没有第四个系统 case。

## 原控制器：从真实 SLX 得到的方程

原工作树 SLX 的审计及实际连接见 [A1 原 PI 审计](checkpoint_a/current_speed_pi_audit.md)；冻结 B1 的逐级 cast 规则见 [共同 RTL 契约](checkpoint_c/rtl_contract.md)。一次有效速度事件内，`x_old` 和 `d_old` 都是上一事件留下的状态：

```text
e = v_ref - v_meas
P = Kp * e
inc = (Ki * Ts_ASR) * e
AW = Kaw * d_old
u = P + x_old
l = clip(u, -1 A, +1 A)
d_next = u - l
candidate = clip(x_old + inc - AW, -0.5 A, +0.5 A)
hard = angle_init OR pi_reset OR test_mode OR NOT enable
int_reset = hard OR (abs(v_ref) < 0)
            OR (abs(v_ref) > 0.5 AND sign(v_ref)*e < -3)
iq_ref = hard ? 0 : quantize_to_25_FL15(l)
x_next = int_reset ? 0 : candidate
```

Kp=0.018033474852681124，Ki=1.4426779882144898，Ts_ASR=0.001 s，Kaw=0.08；原 friction compensation 已被注释，其输出为 0。AW 使用 **previous excess**，当前输出使用 **old integrator**，不能改成当拍新积分或当拍 excess。积分复位单独发生时，当拍输出仍使用旧 x；hard reset 令当拍输出与下一 x 为 0，**不清除 d_next**。阈值 `abs(ref)<0` 永远为假，零参考保留保持电流所需的积分。

原 scheduler 在 t=0 开始 100 us function-call，计数先加一，因此首速度事件为 **0.9 ms**，以后每 **1 ms**。位置事件首相位 9.9 ms，周期 10 ms。语义 reset/disable 只在有效速度事件采样；空闲 clock 不更新状态。FPGA 初始化 reset 与这些算法 reset 不同：同步初始化优先于 global CE，并清除寄存器/流水状态。

## Float 与 Fixed：类型、系数量化和误差

独立 float 对原 PI 副本的全部 14 项输出最大误差为 0；A 使用 2580 个样本、258 个真实速度事件。B1 是所有后续 RTL 的唯一 numerical golden，B2 只研究缩短位宽产生的误差，没有用于系统闭环。

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

所有有损转换采用 Convergent / ties-to-even，存储溢出采用 Saturate，没有 wrap。算法 ±1 A / ±0.5 A 限幅与存储饱和分别保留。全精度 error×coefficient 为 signed65/FL50，AW 乘积为 signed72/FL60，逐级转换到 work40/FL30；积分更新保留 44 位累加与 45 位减法再饱和。输出 Q15 只在内部限幅之后转换；previous excess 来自内部 u-l，不能改用量化后的外部 iq。

| Format | Coefficient | raw code | Quantized value | Error |
|---|---|---:|---:|---:|
| B1 | Kp | 19363296 | 0.018033474683761597 | -1.6891952767106311e-10 |
| B1 | KiTs | 1549064 | 0.0014426782727241516 | 2.8450966170663616e-10 |
| B1 | Kaw | 85899346 | 0.080000000074505806 | 7.4505804303903744e-11 |
| B2 | Kp | 75638 | 0.018033504486083984 | 2.9633402860024249e-08 |
| B2 | KiTs | 6051 | 0.0014426708221435547 | -7.166070935217192e-09 |
| B2 | Kaw | 335544 | 0.079999923706054688 | -7.6293945314165335e-08 |

| A 测试误差指标 | B1 | B2 candidate |
|---|---:|---:|
| 非饱和 iq_ref 最大误差 / A | 1.52135277977e-05 | 3.24425528691e-05 |
| 非饱和 iq_ref 最大误差 / 外部 LSB | 0.498516878875 | 1.06307757241 |
| integrator 最大误差 / A | 2.42387708904e-07 | 2.46812617036e-05 |
| 饱和时刻/方向 mismatch | 0 | 0 |

B1 在该组件测试中的输出误差约半个 Q15 LSB；B2 的误差超过 1 LSB。上述值是已运行向量的实测结果，不能扩大为所有实数或所有电机工况的误差上界。[A2/A3 完整对照](checkpoint_a/float_fixed_comparison.md)说明复位阈值、量化和 overflow 范围。

## HDL Coder 与 Hand SV：结构、可读性和 traceability

HDL Coder carrier 从 B1 复制相同 PI 运算块，只改变可生成 HDL 的承载结构和寄存器边界。冻结文件为 `generated_hdl/baseline/HDLCore.sv` 和 `PI.sv`；没有编辑生成的数学表达式。输入寄存阶段后，事件输出寄存器同时保持数值和诊断。global CE 不是算法 enable，ce_out 不是 result_valid。[HDL Coder walkthrough](checkpoint_b/hdl_coder_walkthrough.md)给出配置、SID mapping、原块→RTL 路径和 Vivado DSP48 报告，便于从熟悉的 Simulink 算法追到生成结果。

Hand SV 的 [speed_pi_sv.sv](../handwritten/speed_pi_sv.sv)用显式状态寄存器、全宽乘积、guard/sticky/retained-LSB 的偶数舍入及逐级饱和实现同一契约。一个输入阶段加一个事件输出保持阶段，不新增算法延迟。代码物理行数 152，比 baseline 的 718 行更紧凑；紧凑并没有自动带来更低资源或更好的时序。复位、previous excess、overspeed 边界与 signed minimum 取负饱和都需要人工维护和证明。

## Bit-true：组件覆盖和真实系统输入重放

B 的生成版在 2580 行 / 258 事件 / 14 项 raw code 上零差异。C 的公平比较在每版 7842 行、2886 事件上验证 baseline、AW CSD 和 hand 全部 14 项零差异，覆盖正负线性区、饱和、anti-windup、解饱和、反向、reset/disable、连续上升事件、长空闲、global CE stall 和初始化 reset 优先级。

D 又使用各次真实系统导出的输入、实际 source event 顺序和测得的物理 capture/result cycle，重新运行冻结 `models/speed_pi_fixed.slx`。共 109200 项 raw code 对照，mismatch=0；每一项中间量也验证两次有效结果之间保持。[九组 bit_true.csv/json](checkpoint_d/verification/)保存 actual B1 与观察到的 RTL raw code。original case 的 B1 检查对象是 **未选中的 baseline shadow**，没有把原 float PI 宣称为对 B1 bit-exact。真实重放 oracle、完整整数网格及实际对齐说明以各组 fresh `bit_true.json` 的 `oracle` / `alignment` 为准；不通过移动曲线或修改 PI 消除差异。

重放工具出现过一个已定位的输入时间网格问题。四组受控诊断中，`colon_default` 有 200 项 raw mismatch / 2 个 ingress mismatch（事件 154、155）；`colon_explicit_zoh` 有 343 项 / 6 个 ingress mismatch；相同输入采用整数索引构造的 `integer_default` 和 `integer_explicit_zoh` 都为 0 / 0。Colon 时间向量与离散求解器 n×Ts 向量有 119 个 timestamp 不同，最大仅 2.7755575615628914e-17 s，却足以让 FromWorkspace 在边界选到前一个 100 us 输入。直接记录 B1 的输入 Ref/Meas 证明问题发生在 oracle ingress，不是 PI 运算或 RTL 延迟。最终只把新重放 helper 的时间向量改为 `(0:round(stop/Ts))' * Ts`，匹配离散 solver 的网格；冻结 B1 参数/SLX、RTL、真实系统波形和算法都未更改。[四组原始 CSV 与诊断 summary](checkpoint_d/verification/replay_input_diagnostic/summary.json)保留失败和通过的数据。

## Vivado 公平资源和时序比较

下表来自已合并 C 的同一次边界设计：同一真实 `xc7a200tfbg484-2`、50 MHz、同一 input/output register boundary、全部 14 项诊断、同一 XDC / OOC synthesis→implementation，无 false/multicycle path。D 没有重跑或覆盖这份冻结资源结果。

| Metric | HDL Coder baseline | HDL Coder optimized（AW CSD，仅 C） | Hand SV |
|---|---:|---:|---:|
| LUT | 685 | 1049 | 705 |
| FF | 555 | 476 | 555 |
| DSP48 | 10 | 6 | 10 |
| BRAM | 0 | 0 | 0 |
| Register boundaries / accepted-input latency | 2 stages / 1 clock | 2 stages / 1 clock | 2 stages / 1 clock |
| Update interval | 50000 clocks / 1 ms | 50000 clocks / 1 ms | 50000 clocks / 1 ms |
| WNS @ 50 MHz / ns | 0.331 | 0.862 | -1.957 |
| RTL LOC（含空行、注释） | 718 | 719 | 152 |

每版另有同一份 45 行薄 valid/CE adapter。C 的 CSD 只对 AW Gain 的 `ConstMultiplierOptimization` 从 none 改为 csd；DSP48 从 10 降为 6，LUT 从 685 增为 1049，WNS 从 +0.331 ns 变为 +0.862 ns，没有更改算法或 latency。Hand 同样用了 10 个 DSP48，LUT=705，WNS=-1.957 ns，关键路径从 ref_q_reg 到 d_reg，52 级逻辑 / 21.632 ns data delay。[公平比较与关键路径](checkpoint_c/final_rtl_comparison.md)区分结构选择与工具映射，并保留未解释到门级的归因限制。

B 早期单核心报告的 683 LUT / 472 FF 与 C 的 685 LUT / 555 FF 来自不同薄适配器/诊断边界；不能拿两个边界的数字直接当作工具优劣。最终公平比较以本表的 C 同边界结果为准。OOC IP 内部时序通过不等同于 board I/O signoff。

## 系统联合仿真：同一 Host、Position、FOC、inverter 和 plant

三组均为 CONTROL_BACKEND=1。仅 Study copy 内的速度来源选择不同，选择后仍经共同 Reference_Manager 和原 FPGA_Input_Adapter 进入同一 FOC。正式主 SLX、FOC/PWM RTL、控制周期、PI 参数、plant 和 inverter 算法没有保存或改写。average inverter 在 ideal 用 0 deadtime，在 deadtime 用 1 us；同一场景的三组值完全相同。每次模型配置前后的 shared fingerprint 都相同，包含原块计算参数及内部 Line 连接；九组 metrics 的 `cfg.shared_fingerprint` 保存相同 Host、Position、原 PI、scheduler、Reference_Manager、FOC、plant、inverter、adapter 的图结构证据。

| Scenario | Speed PI | Worst speed-window RMSE / mm/s | iq RMSE / A | Speed events | FOC accepted / active | Physical latency / ns |
|---|---|---:|---:|---:|---:|---:|
| speed_ideal | original | 0.0926415902 | 0.000541208732 | 1200 | 12000 / 11999 | 0 |
| speed_ideal | coder_baseline | 0.0910688383 | 0.000538910451 | 1200 | 12000 / 11999 | 30 |
| speed_ideal | hand_sv | 0.0910688383 | 0.000538910451 | 1200 | 12000 / 11999 | 30 |
| speed_deadtime | original | 0.236091294 | 0.00352830927 | 1200 | 12000 / 11999 | 0 |
| speed_deadtime | coder_baseline | 0.247049518 | 0.00359459885 | 1200 | 12000 / 11999 | 30 |
| speed_deadtime | hand_sv | 0.247049518 | 0.00359459885 | 1200 | 12000 / 11999 | 30 |
| convergence_prefix | original | prefix sanity | prefix sanity | 200 | 2000 / 1999 | 0 |
| convergence_prefix | coder_baseline | prefix sanity | prefix sanity | 200 | 2000 / 1999 | 30 |
| convergence_prefix | hand_sv | prefix sanity | prefix sanity | 200 | 2000 / 1999 | 30 |

每组 speed case 完整运行 1.2 s，position prefix 为 0.2 s。speed 的固定窗口、MAE/RMSE/max 和 current gates 使用未修改的 `step7d_assert_result.m`；prefix 只确认 Host trajectory→Position→speed→FOC→plant 的方向、有限性和电流/故障/调度，不宣称完整位置 settling。

RTL physical source→result 的实测值为 [30.0] ns，来自第一 posedge `$time` 和 actual cycle ordinal，而不是强加的时间平移。冻结 RTL 的 accepted input→result 仍为 1 个 20 ns clock。1 us XSI communication 观察到计数变化，再经显式 1 us feedback hold、共同 100 us Control_Task / Reference_Manager 消费；新增 carrier transport 与原 RTL pipeline 分开记录，通常在下一 100 us task 发布参考。各组 metrics 的 `managed_reference_events` 保存实测发布、FOC accepted 与配对 active 时刻，仅对数值发生变化的结果测量 transport；连续相同数值仍由结果计数覆盖。

| Speed PI | Observed physical-result → managed-reference delay / us |
|---|---:|
| original | 0 … 0 |
| coder_baseline | 99.97 … 99.97 |
| hand_sv | 99.97 … 99.97 |

RTL physical result 的 30 ns 相位与后续约 99.97 us 的管理器消费延迟是不同的量：source→managed publish 为 100 us。Original float 在同一 speed task 中发布，测得管理器 transport 为 0。Coder baseline 与 Hand SV 在相同承载边界下，全部七项数值比较字段的未移位差异都是 0；原 float 与 fixed 的差异只描述实际测量，不要求其 raw code 相等。

FOC 在每组保持 accepted 首观察 51 us、active 首观察 101 us、后续 100 us transaction、accepted→active 50 us。内部电流计算延迟与 PWM 时序未变。全部 fault_code / needs_reset / range flags 为 0。当前波形不要求 float 与 fixed 逐点相同，量化、实际 pipeline 与 carrier consumption 的小差异没有通过重新整定隐藏。

[D 逐组数值与未移位差异表](checkpoint_d/verification/comparison.md)、[交互式同时间曲线](checkpoint_d/verification/comparison.html)和 [系统 walkthrough](checkpoint_d/system_walkthrough.md)提供 v_ref、v、speed PI iq_ref、iq、新结果、accepted/active、fault/reset、位置与实际管理后参考。图表网格为 100 us；new_result 表示自上一图表样本后观察到的 completion-count 增量，不冒充一个 20 ns valid pulse。

## 学习结论和可复现边界

算法快速迭代时，HDL Coder 更便于把已冻结的 Simulink 定点模型、datatype 和 SID traceability 连接起来；每次改模型都必须重新验证 raw code、资源与时序。手写 SV 更适合明确控制 CE、valid、接口协议和寄存器布局，但这次 hand 实现没有获得预期的资源/时序优势：baseline 的 LUT 更少且 50 MHz 通过，hand 尚未通过。

资源选择取决于约束：AW CSD 节省 4 个 DSP48，却多用 364 个 LUT；若 DSP 紧张值得评估，若 LUT 更紧张则 baseline 更合适。这一个实验不能推广为所有乘法都改 CSD。之后可讨论在已固定类型的独立控制/运算核上尝试 HDL Coder；FOC transaction、PWM、安全复位、握手和最终 scheduler 这类时序协议仍适合保留明确的手写 RTL，且需要另行任务授权。

1 ms 是 PI **状态更新间隔**，不是 FPGA 的 physical clock 周期。50 MHz clock 运行所有寄存器，外部 sample_tick/CE 只允许规定事件改变状态；不必生成 1 kHz 新时钟。Ki 是连续增益，Ki×Ts 才是每事件积分增量；积分器与 previous excess 必须作为状态寄存器保留。整数位来自真实输入/内部范围，小数位决定 LSB；舍入及饱和必须与模型中的逐级转换相同。DSP48 的使用依据是实际 Vivado utilization，而不是仅看 RTL 中是否有乘号。

模型算法修改时优先改模型并重新生成，不修改生成文件；握手或架构修改时显式改手写 carrier并重新证明同一数值边界。两种 RTL 能组合是因为 FPGA RTL 模块按共同 clock / fixed-point 端口互连，HDL 来源不改变接口规则；系统闭环成功仍不能代替实现时序验收。

此次保护核验保留 288 个用户本地文件/缺失状态、166 个冻结 A/B/C 文件、1260 个其他 tracked 源文件；源 SHA 和 fresh runtime snapshot/log 见 [D summary](checkpoint_d/summary.json)及 [verification provenance](checkpoint_d/verification/provenance.json)。仅使用原工作树和独立 runtime/model copies；无 worktree/clone、stash、reset/clean、批量删除、bitstream 或硬件操作。

复现先阅读 [系统 walkthrough 的命令](checkpoint_d/system_walkthrough.md)，用从未存在的新 run 名生成 XSI，运行三种 speed PI 的三个场景并重放实际 B1，再调用 `study_l1_d_publish.py` 的明确参数发布。MATLAB=26.2.0.3386108 (R2026b)，Vivado=2026.1。全部数学/接口证据与 Hand timing 失败同时保留；本次 completion 不构成下一阶段或上板授权。
