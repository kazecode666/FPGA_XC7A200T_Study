# M1A 独立纯 Simulink 浮点基线实施报告

日期：2026-10-23。实施起点 `origin/main@b404bea`（PR46 已合并），分支 `codex/m1a-float-baseline`。仅在原仓库工作；没有 clone/worktree、stash/reset/clean、文件删除或修改外部原始目录。

当前状态：M1A 模型实现与限定 MATLAB 验收完成，交付开放实现 PR 等待 Review。最终新模型 706 块；组合入口已输出 M1A_ALL_PASS，五文件隔离目录双进程配对通过。

## 来源保护与实现

使用 M0 审计过的本地未提交 Simple 保存版本，SLX 556658 bytes、初始化 .m 3055 bytes，与 M0 快照逐字节相同。七份受保护源快照、原 tracked binary patch 和 untracked 清单留在 `.runtime/m1a_20261023`。旧 Simple、MIL、ControlCore、DSP、原初始化/MAT 和 RTL 不保存、不改写。详见[来源清单](../../docs/reports/m1a_float_baseline/source_inventory.md)。

从 Simple 另存新 `PMLSM_PI_FOC_Float_Baseline.slx`。移除 XSI/HDL 子系统与四个后端选择器，保留 dq PI、前拍 AW、限幅/复位、Reference Manager、三环 scheduler、S 曲线、一个平均逆变器和一个自由运动 plant。旧 FPGA 专用监视输入接显式零，仅保留监视布局兼容接口。

新初始化脚本每次显式写 Base Workspace，Model Workspace 为空；InitFcn 仅调用只读参数检查。四路场景 timeseries 文本生成、零阶保持；不使用旧 MAT/prepare。电机/PI/时基与来源对应，不重新整定。Kp/Ki_ACR=8.725/11850，Kaw_d/q=0.1358166189111748；速度约 0.0180334748526811/1.44267798821449，Kaw_s=0.08，位置 Kp=22。

保留 SVPWM 扇区/时间算法，将原三路时间量换成 `1-2*t/T_pwm`，去掉 CPU counts 主链与转换子系统。命令端口为归一化死区前/应用更新前上管 duty。半周期延迟初值由 5000 counts 等价为 0.5；只有一次 50 us 更新、一处 1 us 平均死区。角度/速度仍按 2*pi*x/0.06 与 2*pi*v/0.06。电气和机械基线值详见[用户指南](../../docs/PMLSM_FLOAT_BASELINE_GUIDE_ZH.md)。

工具偏离：连接器仍指向不存在的 R2026b_Prerelease，实际使用 `D:/Program Files/MATLAB/R2026b/bin/matlab.exe`（26.2.0.3386108）。Toolkit 增量编辑的后台监听器仍递归进入 MCB 库布局，关闭开关后也复现；两次在保存前终止自有进程。按任务书禁止全局布局的边界，最终使用原生 MATLAB 按 SID 局部编辑、检查连接；未改工具/厂商库配置。详细失败保留，未把中断尝试标为通过。

## 真实验收证据

| 检查 | 实际结果 |
|---|---|
| 结构 | 先见 M1A_MODEL_MISSING，再通过结构/端口检查；检查后 Dirty=off |
| 初始化负例 | 旧 Kp/Udc 不绕过 marker，提示专用初始化脚本 |
| 参数/工况生效 | 外部文本副本的负位置、独立负载实际改变响应，默认恢复后复现；Model Workspace 无遮蔽 |
| 初始化双进程 | PID45492/45496 的五组 logsout 全部逐样本相同，见 init_acceptance.json；属于归一化前的参数组织检查 |
| 实际 SVPWM 块 | 115 点，覆盖零矢量、六扇区、边界两侧和线性限幅附近；max duty 对照误差 1.11e-16，独立 alpha/beta 重构 max 0.000727477 V |
| 实际变换块 | 32 点，含平衡电流、公共分量及各象限/周期边界角度；Clarke 误差 0，Park max 6.86e-6 A，往返 max 1.583e-5 A，低于首次探针前设定的 1e-4 A 门槛 |
| 实际 PI/限幅块 | old-state/AW/复位的输出与积分状态误差均 0，延迟记忆按原合同保留 |
| 实测时序 | 首速度/位置 tick 0.9/9.9 ms，command 首变 0 s、applied 首变 50 us；PWM 关闭后平均 vd/vq 为零 |
| 源 backend0 迁移 | 正负电流、正负速度、正负 1 mm 位置、理想、负载阶跃、stop/reset 九场景，24 路/场景，全部通过 |
| 步长 | 正电流自由运动工况 1 us vs 0.5 us，控制 tick/模式事件一致，24 路指标通过 |
| 最终独立 fresh | 最终副本 PID43908/45864，只含新 SLX 与四个必要 .m，排除其他仓库路径并检查辅助函数位置；无旧 MAT/legacy 变量，完整 1.2 s 默认工况的 11 路记录逐样本一致 |

默认最终位置 0.9849676863605962 mm，给定 1 mm，误差 0.0150323 mm，符合来源 0.02 mm 位置死区；不声称无静差。最终线段检查清理了 21 段删除旧分支后留下的悬空线，清理前后全部有效输入连接完全相同；随后组合入口与两次 fresh 又通过。见 fresh_acceptance.json / connectivity_acceptance.json。

[冻结阈值](../../docs/reports/m1a_float_baseline/acceptance_config.json)在闭环前提交，未根据误差放宽。迁移逐路比较 max-abs/RMSE；采样/事件时间相差须 <1e-12 s，模式/计数完全一致。

迁移最大误差：id/iq 约 8.13e-16/9.05e-16 A，vd/vq 约 6.49e-15/7.55e-15 V，三相 command duty ≤3.34e-16，位置 ≤6.67e-16 mm，速度 ≤5.69e-14 mm/s；PI/AW 状态也在冻结门槛内。

步长差最大：id/iq 0.000136/0.000160 A，vd/vq 0.00328/0.00140 V，位置 0.0000714 mm，速度 0.00128 mm/s；控制 tick、计数、使能/复位事件完全一致。完整 240 行数据见 [closedloop_metrics.csv](../../docs/reports/m1a_float_baseline/closedloop_metrics.csv)，含单位、样本数、最大误差、RMSE、门槛和 pass。

记录物理量按 100 us 公共网格，控制/状态按自身采样，应用 duty 保留 50 us 网格。迁移不插值或移动事件来凑一致。只读源侧使用原 Model Workspace 和其专用瞬态 init 状态，CONTROL_BACKEND=0；new 侧独立外部参数。源侧关闭 save=0，未保存回原文件。

## 执行入口与交付边界

最终实际命令为 `matlab -batch "addpath('D:/Project/FPGA_XC7A200T/scripts'); m1a_verify_float_baseline('all')"`，输出 M1A_ALL_PASS（含追加变换检查的 job_25.log）；两次新进程 `m1a_fresh_float_baseline` 输出 M1A_FRESH_PASS，配对输出 M1A_FRESH_PAIR_PASS（job_27.log）。早期数学 harness 的保持参数、位置观察窗口和 fresh 输出时间字段问题均作为测试修复记录，没有改变 PI、物理语义或放宽阈值。八个 MATLAB 文件 Code Analyzer 均 0 条诊断，结果另存 code_analyzer.json；PID 记录改用 R2026b 支持的 matlabProcessID，并在本机验证与旧 API 数值一致。

直接运行与复现命令见[中文指南](../../docs/PMLSM_FLOAT_BASELINE_GUIDE_ZH.md)。全量运行日志、模型副本和完整 MAT 不入库，精简索引/指标入库。

保护检查：原 34 项 tracked 修改对应的 Git binary patch 逐字节不变，原 666 项 untracked 路径仍存在，七份受保护源快照逐字节一致；最终 SLX 与隔离副本逐字节相同。Code Analyzer 与变更范围 `git diff --check` 结果入库。阶段提交 c943b1b（结构）、c58fa1e（初始化）、e9a5f24（调制/时序）、ed7e8f8（迁移/交付）；Review 补充独立变换点与更严格的 fresh 路径隔离。

独立只读审查未发现模型回归，指出数学入口缺少独立变换点，以及原 fresh 测试没有排除其他仓库搜索路径。已补充实际块的解析式/往返测试、将其纳入 math/all，且 fresh 测试显式移除其他仓库路径并检查四个辅助 .m 的解析位置。保留原有限工况和全部既有阈值，不扩展到审查明确留给 M1B/HDL/实机的范围。

本阶段没有定点化、HDL/C 生成、Vivado 构建、bitstream、硬件或实机验证；没有重跑历史全套 Step6/7/StudyL1。原有完整运行管理、真实反馈滤波、行程/故障恢复尚未验收。完成交付后停在开放实现 PR，等待 Review；不自动合并或进入 M1B/M2。
