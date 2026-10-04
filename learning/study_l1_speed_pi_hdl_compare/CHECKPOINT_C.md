# Study-L1 Checkpoint C

入口：[最终比较报告](reports/checkpoint_c/final_rtl_comparison.md)、
[共同数值/RTL contract](reports/checkpoint_c/rtl_contract.md)、
[machine-readable summary](reports/checkpoint_c/summary.json)。

只完成 C1–C5。手写、Coder baseline、仅AW CSD三个版本全部14项raw bit-exact。
实际50 MHz OOC WNS分别为-1.957、+0.331、+0.862 ns：**手写setup未通过**。
没有Checkpoint D、整机cosimulation、bitstream或硬件操作。

## 目录

| 文件 | 用途 |
|---|---|
| models/speed_pi_fixed.slx | 冻结B1，唯一numerical oracle |
| models/speed_pi_hdl.slx | 冻结Checkpoint B carrier |
| handwritten/speed_pi_sv.sv | 独立手写B1等价核 |
| handwritten/speed_pi_compare.sv | 共用CE/valid适配器，无PI运算 |
| generated_hdl/baseline/ | 冻结原生Coder RTL，未修改 |
| generated_hdl/aw_csd/ | 单项AW CSD原生输出及manifest |
| models/checkpoint_c_aw_csd/speed_pi_hdl.slx | 独立保存的单项配置模型，B carrier未覆盖 |
| reports/checkpoint_c/verification/{baseline,hand,csd}/ | 每版XSim trace/log及synth/route/coverage报告 |
| reports/checkpoint_c/codegen/ | native生成状态/报告、单项配置与functional diff |

## 在原始工作树复现

PowerShell，在 `D:/Project/FPGA_XC7A200T` 执行。以下使用独立fresh runtime目录；
不删除旧运行、不创建worktree/clone、不stash/reset/clean，不保存或覆盖golden/用户SLX。
MATLAB必须使用已验证的R2026b GA和HDL Coder26.2；Vivado脚本固定实际part及2026.1工具路径。

```powershell
$ErrorActionPreference='Stop'
$study='D:/Project/FPGA_XC7A200T/learning/study_l1_speed_pi_hdl_compare'
$run="$study/.runtime/c_reproduce_"+(Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Path $run | Out-Null
& 'D:/Program Files/MATLAB/R2026b/bin/matlab.exe' -batch "addpath('$study/scripts'); study_l1_c_golden('$run/golden')" -logfile "$run/golden_console.txt"
if ($LASTEXITCODE -ne 0) { throw 'B1 exporter failed' }

# 先证明手写RTL等于实际B1，再进入资源比较。
& "$study/scripts/study_l1_c_xsim.ps1" -Variant hand -GoldenDirectory "$run/golden" -RunDirectory "$run/sim_hand"
& "$study/scripts/study_l1_c_xsim.ps1" -Variant baseline -GoldenDirectory "$run/golden" -RunDirectory "$run/sim_baseline"

# 唯一优化实验：AW block的ConstMultiplierOptimization，none -> csd。
& 'D:/Program Files/MATLAB/R2026b/bin/matlab.exe' -batch "addpath('$study/scripts'); study_l1_c_csd('$run/coder')" -logfile "$run/coder_console.txt"
if ($LASTEXITCODE -ne 0) { throw 'Single-option Coder generation failed' }
& "$study/scripts/study_l1_c_xsim.ps1" -Variant csd -CoderDirectory "$run/coder/generated/speed_pi_hdl" -GoldenDirectory "$run/golden" -RunDirectory "$run/sim_csd"

& "$study/scripts/study_l1_c_impl.ps1" -Variant hand -RunDirectory "$run/impl_hand"
& "$study/scripts/study_l1_c_impl.ps1" -Variant baseline -RunDirectory "$run/impl_baseline"
& "$study/scripts/study_l1_c_impl.ps1" -Variant csd -CoderDirectory "$run/coder/generated/speed_pi_hdl" -RunDirectory "$run/impl_csd"
python "$study/scripts/study_l1_c_coverage.py" "$run/golden" "$run/sim_baseline/trace.csv" "$run/sim_hand/trace.csv" "$run/sim_csd/trace.csv"
```

每个脚本拒绝已有run目录。普通golden向量应与B的2580行逐行一致。
XSim gate必须有`STUDY_L1_C_XSIM_PASS ... raw_mismatches=0`，不允许Fatal/Error。
Synthesis/implementation gate检查单一clock、完整input/output/internal约束与无loops，
`metrics.json`中的负WNS仍会保存：**implementation完成 ≠ timing通过**。
检查`route_utilization.rpt`的LUT/Slice FF和`metrics.json`的DSP/BRAM/WNS/WHS。
不生成bitstream。OOC未绑定外部partition pin的告警不能当作board I/O路由签核。

`study_l1_c_publish.py`是本次交付的证据收集器，校验保护快照、三个trace相同、
实际part/coverage/routing、单项RTL diff和native byte hash。它拒绝覆盖已存在且不同的交付文件；
复现结果留在fresh `.runtime`中，不用publisher覆盖本次报告。
`study_l1_c_workspace.py verify`核对本次288项用户内容和88项冻结A/B内容；
若用户此后合理编辑这些文件，快照会报告变化，不能为此恢复或覆盖用户文件。

## 21列向量与时间定义

```
ref_raw meas_raw enable pi_reset sample_tick angle_init test_mode
iq_ref u x_old saturated x_next d_old d_next hard int_reset limited error P KiTs AW
```

每一行来自实际B1仿真；normal是100 us逻辑步长，第一tick在第9行/t=0.9 ms，随后每10行。
stress也是同一个B1模型和KiTs，但RTL按高低交替的每clock输入加速验证事件排序。
持续高tick不形成连续有效事件。

共用RTL有2个边界pipeline阶段，事件接受后1个clock提交。TB在negedge驱动，30 ns后输出，
再#1检查；trace中的time_ps因此是drive+31000 ps。若源在posedge后launch则是40 ns。
scoreboard按accepted event排队，不通过任意平移寻找匹配。

**STOP：等待本Checkpoint C的ChatGPT Review，不进入系统联合仿真。**
