# Step 6C4：本地 PI-FOC 电流计算链

`mc_foc_current_core` 在一次握手时捕获三相电流、电角度、电角速度、dq 参考、母线电压和控制命令，连接已验收的 C1 电流变换、C2 PI/圆限幅、C1 逆 Park、C3 Sector/XYZ SVPWM。数学子模块和 ROM 没有改动；逆 Park 使用该笔电流变换保存的同一对 sin/cos，C2/C3 使用同一份母线电压。

## 打开主目录工程

本次实际工程：`D:/Project/FPGA_XC7A200T/FOC_Current/FOC_Current.xpr`。

用 Vivado 2026.1 打开它，选择 **Run Simulation → Run Behavioral Simulation**。在 Tcl Console 中执行：

```tcl
source D:/Project/FPGA_XC7A200T/FOC_Current/wave_step6c4.tcl
run all
```

默认设计与 TB 均为 `PI_PROFILE=0`。仿真运行时间设置为 0 ns，方便先加载波形再 `run all`；完整 TB 约 33.744 ms 仿真时间。波形含捕获输入、四级 valid、变换量、PI OLD/NEXT 状态、逆 Park 电压和最终 duty。成功标记为 `ALL STEP 6C4 FOC CURRENT TESTS PASSED profile=0`。

切换 profile 1 的行为仿真：先关闭当前仿真，在 Tcl Console 设置 `set_property generic {PI_PROFILE=1} [get_filesets sim_1]`，重新 `launch_simulation`、加载波形并 `run all`。完成后将仿真 generic 恢复为 `PI_PROFILE=0`。综合默认参数始终为 0；本轮没有 profile 1 的整核时序验收。

综合与实现结果在本工程 `synth_1` / `impl_1`，可通过 **Open Synthesized Design / Open Implemented Design** 查看。本地 `.sim`、`.runs`、WDB/DCP 保留，生成物不整体提交 Git。

## 调度和控制状态

接受边沿为 N，四个子核依次在 N+1、N+8、N+266、N+270 接受；顶层统一在 **N+512** 返回，即 50 MHz 下 **10.24 us**。最早 N+513 接受下一笔。PI 参数仍对应 **100 us / 5000 clocks 控制采样周期**，不能按计算延迟修改积分周期。

`enable=0` 只阻止新握手，已接受事务仍完成，空闲不积分。C2 独自管理状态，在 N+264 成功提交；下游报错不会回滚积分。无效母线不启动子核，返回错误和全零 duty；时序内部错误要求硬件复位后恢复。`pi_reset`、`uq_zero_en` 都是随样本捕获的命令，后者令 dq 中的 q 电压为零，在非零角度下并不代表 v_beta 为零。

输出 signed F24 duty 沿用 C3，不增加 clamp。`command_valid` 仅指示一次有效计算结果。本任务没有接入 PWM、ADC、编码器、电机或功率级；enable 不是急停信号。

## 可复现验证

在仓库根目录运行：

```text
python scripts/step6c4_foc_reference_test.py
python scripts/step6c4_foc_reference.py --check
vivado -mode batch -nojournal -nolog -source scripts/step6c4_foc_build.tcl -tclargs UNIQUE_LABEL
```

验收只检查已提交的向量。需要有意更新 C4 向量时才单独运行 `--generate`，它不修改 C1/C2/C3 参考文件。完整 build 检查六项 Python 验证、两个 profile 的 C4 整链 TB、已有 Step 6B PWM TB，并在本工程执行默认参数综合/route。最后必须出现 `STEP6C4_BUILD_PASS`；详细证据在 `docs/reports/step6c4/UNIQUE_LABEL/`。

基础向量 672 行：每 profile 连续 80 行实际 Step 6A 原始输入，再接 256 行固定种子样本。所有中间量、OLD/NEXT 状态和最终输出逐位比较。历史浮点比较见 `coordination/reports/step6c4_foc_fixed_vectors.csv` 和执行报告；不把 C3 独立比较的容差或 sector 白名单外推为 C4 门槛。
