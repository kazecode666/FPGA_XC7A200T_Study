# 首轮原位宽核心 OOC 预检

结论：**综合完成、容量满足；20 ns 核心综合时序估算失败，M3 接受仍受阻塞。** 保留首轮结果，不缩减位宽、不修改生成 RTL、不重新整定 PI，也不改默认死区。本轮不增加流水线候选或扫描配置；任何后续候选须另行审定并重新完成受影响的 C/D/F gate。

本次使用 B3 最终生成清单，SHA256 为 `cfd8b1d7639275f273ed683c83344b02678ada8e8130b805a1ac42b6eda09098`。器件 `xc7a200tfbg484-2`，实际 HDL 时钟输入 `clk`，`m3_core_clk` 周期 20.000 ns。沿用既定类型：Work 64/40、DivideWide 72/40；数据端口保持变量。只运行 non-project `synth_design -mode out_of_context -flatten_hierarchy none`。

| 项目 | 实测 | 容量 / 门槛 | 结论 |
|---|---:|---:|---|
| LUT | 69,673 | 134,600 | 满足，51.76% |
| FF | 73,840 | 269,200 | 满足，27.43% |
| DSP48E1 | 439 | 740 | 满足，59.32% |
| BRAM36 等效 | 0 | 365 | 满足 |
| 最差 setup slack | -58.833 ns | >= 0 ns | **FAIL** |
| 最差 hold slack | +0.144 ns | >= 0 ns | 满足本次估算 |
| latch / blackbox | 0 / 0 | 0 / 0 | 满足 |
| 无时钟 / 内部未约束端点 | 0 / 0 | 0 / 0 | 满足 |
| 组合环 / latch 环 | 0 / 0 | 0 / 0 | 满足 |

最差 setup 路径从 `u_dq_voltage_limiter/u_Divide/matching_delays_reg_reg[108]/C` 到 `u_SVPWMG/u_T1T2_Calculate/u_Fcn1/u_Defined_Quotient/dividend_in_reg_reg[63]/D`。数据路径 78.788 ns，其中逻辑 57.113 ns、估算连线 21.675 ns；154 层逻辑包含 104 个 CARRY4、18 个 DSP48E1。负余量来自每时钟组合路径；5000 拍控制帧间隔不构成放宽这些寄存器路径的理由。本次未使用全局 false path 或 5000 倍 multicycle 约束。

| 层级热点 | LUT | FF | DSP |
|---|---:|---:|---:|
| SVPWMG | 37,324 | 45,529 | 163 |
| T1T2_Calculate（SVPWMG 子层级） | 27,930 | 38,078 | 32 |
| dq_voltage_limiter | 21,851 | 27,846 | 76 |

综合日志给出 0 error、0 critical warning、65 warnings；主要为未使用端口或寄存器裁剪。完整诊断还包含：

- `DPIP-1` 530 项、`DPOP-1` 397 项、`DPOP-2` 397 项，提示 DSP 输入、PREG、MREG 流水线；作为后续候选依据，当前不自动修改。
- `Timing 38-242`：OOC 的 `clk` 未指定上层 `HD.CLK_SRC`，无法估计时钟分布延迟和偏斜；未虚构未知的顶层 clock buffer 位置。
- `check_timing` 的 `no_input_delay` 276 项、`no_output_delay` 96 项：外部端口尚无板级采样时序合同，因此明确未签核；内部寄存器端点没有未约束项。
- `CFGBVS-1`：未设配置电压与 CFGBVS；以及 `DRC 23-814` 说明 OOC 不执行全部基于连接性的 DRC。本阶段不引入板级设置。

归档的 `.rpt` 与 JSON 由真实运行结果逐文件原样复制，来源及 SHA256 见 `evidence_index.json`。`runner_result.json` 保留整体 FAIL，`ooc_result.json` 分别记录 completed/resources_ok/timing_ok。23 MB 的本地 DCP 不纳入紧凑报告，原件仍保留在 `.runtime/m3_20261024_001/ooc_001/synth/post_synth.dcp`。

没有执行 opt/place/route、bitstream 或硬件操作；本报告不证明最终布线时序、板级 I/O 时序、完整 DRC 或硬件可上电。即使容量满足，负 WNS 仍必须作为开放 Review 中的明确阻塞保留。
