# Checkpoint B：生成 HDL 与 Vivado baseline

只完成 B1–B5。冻结 golden model 为 PR38 的 `models/speed_pi_fixed.slx`；B1 及 Checkpoint A 的所有文件保持原哈希。新增 `speed_pi_hdl.slx` 是 HDL-facing carrier，生成 top 为 `HDLCore`，数值子模块为 `PI`。

阅读入口：[HDL Coder walkthrough](reports/checkpoint_b/hdl_coder_walkthrough.md)、[manifest](generated_hdl/baseline/MANIFEST.md)、[fresh summary](reports/checkpoint_b/summary.json)。生成 `.sv` 不允许手工编辑；只有 testbench 含手写 SV，未实现 Hand SV speed PI。

## 在原工作树复现

下列命令使用新的 runtime 目录，保留全部已有文件。版本要求为 MATLAB R2026b + HDL Coder/HDL Verifier 26.2、Vivado 2026.1。执行命令后检查退出状态；不要从失败步骤继续。

```powershell
$study='D:/Project/FPGA_XC7A200T/learning/study_l1_speed_pi_hdl_compare'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$modelRun="$study/.runtime/b_model_$stamp"
$simRun="$study/.runtime/b_xsim_$stamp"
$routeRun="$study/.runtime/b_route_$stamp"
$vivado='E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat'
$matlab='D:/Program Files/MATLAB/R2026b/bin/matlab.exe'

# 先确认现有工程 Part 和安装 part database。
& $vivado -mode batch -source "$study/scripts/study_l1_b_preflight.tcl" `
  -log "$study/.runtime/preflight_$stamp.log" `
  -journal "$study/.runtime/preflight_$stamp.jou" `
  -tclargs 'D:/Project/FPGA_XC7A200T' "$study/.runtime/preflight_$stamp.json"

# 独立 batch 进程：冻结 B1 仿真、carrier 参数/连线比对、raw 比对、
# checkhdl 零错误后，才调用 makehdl；不保存原 B1。
& $matlab -batch "addpath('$study/scripts'); study_l1_run_hdlcoder('$modelRun')" `
  -logfile "$study/.runtime/matlab_$stamp.txt"

$generated="$modelRun/generated/speed_pi_hdl"
& "$study/scripts/study_l1_run_xsim.ps1" `
  -GeneratedDirectory $generated -Vectors "$modelRun/vectors.txt" -RunDirectory $simRun

# 非项目 OOC 核级实现；只到 route_design，不生成 bitstream。
& $vivado -mode batch -source "$study/scripts/study_l1_vivado_baseline.tcl" `
  -log "$study/.runtime/vivado_$stamp.log" `
  -journal "$study/.runtime/vivado_$stamp.jou" `
  -tclargs $generated $routeRun 'xc7a200tfbg484-2'

# 原工作树保护记录，仅适用于开始本 Checkpoint 时记录的本地文件状态。
python "$study/scripts/study_l1_b_workspace.py" verify
```

`study_l1_run_hdlcoder` 不读取 base workspace 的控制参数；参数来自冻结 `study_l1_init`。根输入固定为 signed32/20 和 boolean，算法 reset 独立于 HDL `init_reset`。InputPipeline=1、OutputPipeline=1；生成与比较的两级 latency 定义见 walkthrough。实际生成 header 中的 timestamp/path 会随 fresh run 改变；RTL 模块 body 应一致。

HDL Coder 的完整交互报告位于 `$generated/html/index.html`，生成模型为 `gm_speed_pi_hdl.slx`，验证模型为 `gm_speed_pi_hdl_vnl.slx`。仓库保存精选原始 report pages、traceability、全量有效参数及 native latency metadata。默认 EDA sample scripts 已在配置中关闭，Vivado 使用上面的实际器件脚本。

## vectors 与检查字段

`vectors.txt` 每行 21 个有符号十进制 raw code，前 7 列：

```text
v_ref_s32f20 v_meas_s32f20 enable pi_reset sample_tick angle_init test_mode
```

后 14 列来自实际冻结 B1 SLX 仿真，按顺序为：

```text
iq_ref_s25f15 iq_unlimited_s42f30 integrator_old_s32f30 saturation
integrator_next_s32f30 previous_excess_s40f30 excess_next_s40f30
hard_reset int_reset iq_limited_s42f30 error_s33f20 P_s40f30 KiTs_s40f30 AW_s40f30
```

每行是 Checkpoint A 的一个 100 us 输入样本；XSim 用 5000 个 50 MHz clock 表示其间隔，首 tick 为第 10 个样本（zero-based row 9 / 0.9 ms），之后每 10 行一个 tick。输入在 launch edge 后用 NBA 推出，两个后续边沿后检查输出，并在 NBA 完成后再等 1 ns。有效输出和 idle held outputs 都逐字比较，额外检查 global CE idle hold、持续高 tick 单事件。

验收标记：

```text
STUDY_L1_XSIM_PASS rows=2580 ticks=258 fields=14 raw_mismatches=0
first_phase_ns=900000 update_period_ns=1000000 pipeline_cycles=2 launch_to_valid_ns=40
STUDY_L1_IMPLEMENTATION_PASS
```

Vivado Tcl 同时检查单一 20 ns clock、coverage 缺项=0、WNS>=0、WHS>=0。`study_l1_b_publish.py` 在这些门槛通过后只复制生成源码和精简报告，验证 SHA256；发布过程拒绝覆盖已有 deliverable。大型 DCP、WDB、完整 runtime/report assets 都保留在 `.runtime/`，不进入 Git。

STOP：等待 ChatGPT Review；不进入 Checkpoint C，不生成 bitstream，不操作硬件。
