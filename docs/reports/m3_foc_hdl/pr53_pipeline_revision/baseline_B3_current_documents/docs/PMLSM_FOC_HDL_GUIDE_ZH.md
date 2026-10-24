# FOC SystemVerilog 开发与复验

本轮以最新本地 `PMLSM_FOC_FixedPoint.slx/FOC_DUT` 为源，在隔离副本生成实际 SystemVerilog。正常共享主模型仍只执行原来的 `init_PMLSM_PI_FOC_Float_Baseline` → Run，不调用 M3，也不需要 HDL 工具。没有增加 RTL 电机联合仿真后端。

**当前限制：首轮宽类型 OOC 综合完成、容量满足，但 20 ns 时序估算失败，WNS −58.833 ns。M3 不能作为全部验收通过或可上板的实现。** 具体结果见[整合报告](../coordination/reports/m3_foc_systemverilog_rtl_verification.md)和[综合报告](reports/m3_foc_hdl/ooc/analysis_zh.md)。

## 一条开发入口

使用独立 MATLAB `-batch`，不要在用户正在操作的 MATLAB Base Workspace 执行整套生成。模型阶段会拒绝交互会话及已加载同名模型，避免覆盖未保存内容。普通主模型的初始化入口保持原样。

在原工程 PowerShell 中：

```powershell
& 'D:\Program Files\MATLAB\R2026b\bin\matlab.exe' -batch "addpath('D:/Project/FPGA_XC7A200T/scripts'); m3_foc_hdl('all');"
```

省略 runDir 会创建 `.runtime/m3_<唯一标识>/`。不要复用旧输出名做新生成；已有证据不会被删除。`all` 继续执行独立可做的检查，最后只要有 FAIL/BLOCKED/关键 NOT_RUN 就非零退出。目前会因综合时序失败而非零，这个失败必须保留。

阶段为 `preflight / generate / model / rtl / synth / repro / all`。阶段函数返回 `stage/status/run_dir/evidence/failures`。逐阶段复验使用同一 runDir；模型相关阶段仍须从 `-batch` 调用，例如：

```powershell
& 'D:\Program Files\MATLAB\R2026b\bin\matlab.exe' -batch "addpath('D:/Project/FPGA_XC7A200T/scripts'); r=m3_foc_hdl('model','D:/Project/FPGA_XC7A200T/.runtime/你的新运行目录'); assert(strcmp(r.status,'PASS'));"
```

开工先通过 MATLAB MCP 核对正在加载的模型 FileName/Dirty。该次入口检查没有已加载模型，因此冻结磁盘上的最新本地文件；未提交的主模型布局、硬件资料移动及其它内容保留。以后如存在未保存内容，应先导出受控快照再构建，不能用远端模型替换。`-batch` 检测使用 MathWorks 的 [batchStartupOptionUsed](https://www.mathworks.com/help/matlab/ref/batchstartupoptionused.html)。

## 文件和查看位置

- `generated/m3_foc/manifest.json`：受审发布包，设计、普通 TB、数据文件、编译顺序及 SHA256。生成的 SV 原样复制，未手改公式。
- `scripts/m3_foc_codegen_config.m`：语言、器件、20 ns、手动倍率5000、同步高有效 reset、CRP 配置。数值类型和 PI 仍来自原 init/type 配置。
- `.runtime/m3_20261024_001/final_build.json`：本次最终 B3 工作目录。其中 `rtl/PMLSM_FOC_FixedPoint/` 保存 `gm_PMLSM_FOC_FixedPoint.slx`、`gm_PMLSM_FOC_FixedPoint_vnl.slx`、映射及完整生成报告。按需打开一个派生模型查看，结束后关闭该副本；不要把 gm 当成另一套手工维护的算法。
- `docs/FOC_HDL_TIMING_CONTRACT.md`：数据端口、状态提交、有效相位及 PWM 预算。
- `docs/reports/m3_foc_hdl/`：小型位比较、xsim、工具回归和综合证据；大 MAT、波形、DCP、缓存留在唯一 runtime。

原定点源在本轮没有保存修改；其 SLX 解包成员与基线相同，字节差异来自 ZIP 容器。六份初始化/类型/轨迹脚本与基线仅有换行编码差异或完全相同。共享 Float 主模型的本地内容差异保留，未提交进本轮实现。

## 单独运行已发布 RTL

需要 PowerShell 7、Python 标准库、Vivado 2026.1。默认 Vivado bin 为 `E:/AMDDesignTools/2026.1/Vivado/bin`，可用 `-VivadoBin` 明确指定其它已验证安装。每个 RunDir 必须是工程 `.runtime` 下尚不存在的目录。

普通 HDL Coder TB，不需要 MATLAB、旧 MAT 或旧实验路径：

```powershell
pwsh -NoProfile -File scripts/m3_run_xsim.ps1 -Manifest generated/m3_foc/manifest.json -RunDir .runtime/m3_public_ordinary_新标识
```

普通 TB 仅报告工具生成的通过标记，明确 `counted_scoreboard=false`；它不能代替独立计数比较。完整独立边界测试使用入库的原定点 hex：

```powershell
python scripts/m3_build_scoreboard.py --manifest generated/m3_foc/manifest.json --golden verification/m3_foc/vectors/boundary_random_source_hex.csv --out .runtime/m3_boundary_stage_新标识/manifest.json --case boundary_random --mode normal
pwsh -NoProfile -File scripts/m3_run_xsim.ps1 -Manifest .runtime/m3_boundary_stage_新标识/manifest.json -RunDir .runtime/m3_boundary_run_新标识
```

实际输入重放使用 `actual_prefix_source_hex.csv`。`ce/reset/bit_negative/cycle_negative` 使用17帧 `directed_probe_source_hex.csv`；两个 negative 模式必须使严格运行脚本非零并记录真实位差，不能把负例自身的 FAIL 改成工具 PASS。Vivado 2026.1 的原生 xsim 在本次 `$fatal` 后仍返回0，因此运行器还检查日志、计数及失败标记；`m3_verify_rtl.py` 记录 wrapper 的实际非零返回，把“负例被拒绝”归为检查成功，并保留其原始失败结果。

真实输入 fixture 为0–0.1535 s 的1536帧，保留零初态至开始运动的完整前缀；首次非零参考为 sample1199。普通复验仅依赖紧凑 CSV，不读取历史大 MAT。若重新提取来源，单独运行 `m3_extract_recorded_inputs`，需要明确传入原录制文件，不能默认截峰值窗口。

## 接口接线与有效时刻

HDL 增加 `clk/reset/reset_FOC_DUT_tc/clk_enable/ce_out`，原九数据输入、三 duty 类型不变。驱动两个 reset 为确定值；本轮 TB 将额外 `reset_FOC_DUT_tc` 置0，全局 reset 内部会复位调度。`ce_out=clk_enable` 是快时钟 CE，**不能用于计数控制帧**。

正常50 MHz连续运行，同帧九输入完整保持5000个有效时钟，三相在固定第274拍一起检查。外部有效性由帧相位和 reset 掩码定义；没有原生AXI/valid握手。PI在帧末提交，AW另有后续相位与旁路选择，不能把所有延迟当成同一拍。详见合同中的事件表。

全局 reset 恢复流水线/状态/调度；`PI_Reset_EN` 仍是算法采样输入，保持旧积分/前拍 AW 语义。CE 暂停只作协议诊断，暂停时保持输入并按有效时钟恢复；墙钟延长不能当成正常截止时间证明，也不能把 PWM 禁止改接全局 CE。

输出须在原采样后50 µs应用边界前准备好。行为仿真核心274拍，另预算1拍输出提交寄存器，保留至少1拍余量；按目标20 ns换算剩余2225拍/44.50 µs。由于器件STA未通过20 ns，这不证明物理硬件已满足50 µs截止时间。这里没有把核心延迟机械叠加到原50 µs之后。

## 综合与后续

```powershell
pwsh -NoProfile -File scripts/m3_run_xsim.ps1 -Manifest generated/m3_foc/manifest.json -RunDir .runtime/m3_public_ooc_新标识 -Mode synth
```

只做 `synth_design -mode out_of_context`，实际数据端口保持变量。输出 utilization、时钟、内部时序和未约束分类；不执行 place/route/bitstream。当前 WNS 为负，脚本必须 FAIL，即使 Vivado 原生综合进程正常退出。外部 I/O、上层时钟偏斜、配置电压及最终布线均未签核。

重复构建由 `repro` 强制启动新 MATLAB `-batch` 子进程，核对首次生成/调用者/重复生成 PID，再逐文件比较原始 SHA256；不忽略功能 token、常量或数据差异。子进程失败则F失败。使用短的 `repeat/` 子目录避免Windows Stateflow缓存260字符限制；目录已存在或旧构建缺首次PID时明确拒绝，使用新runDir重建，不补写PID。重复包和另一发布目录实际编译/展开/smoke均须执行。

PWM前检会自动检查三相实际100us/50us事件周期、33个同拍command/ZOH值及30个applied(t+50us)配对；任何相位/数值/数量变化都使A失败。M2 的受限闭环例外不适用于任何 M3 位差、状态错位或时序失败。停在开放实现 PR 等待 Review，后续流水线候选必须重新验证，不自动进入 M4。
