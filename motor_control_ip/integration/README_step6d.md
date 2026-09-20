# Step 6D：FOC 到三相逻辑 PWM

工程的真实主目录路径是 `D:/Project/FPGA_XC7A200T/FOC_PWM/FOC_PWM.xpr`。
源码外部引用同一主目录的 C4、`motor_pwm_core` 和新增 integration 文件；不引用旧 worktree。
默认综合 `PI_PROFILE=0`，默认仿真 `PI_PROFILE=0 DEMO=1`。器件为 xc7a200tfbg484-2。

## 打开默认学习演示

1. 用 Vivado 2026.1 打开上述 XPR，选择 Run Behavioral Simulation。仿真初始停在 0 ns。
2. 在 Vivado Tcl Console 输入：

   ```tcl
   source D:/Project/FPGA_XC7A200T/FOC_PWM/wave_step6d.tcl
   run 300 us
   ```

3. 先观察 2–3 个 100 us 载波周期，再放大峰值采样、ZERO 装载和比较边沿。继续 `run all` 完成演示；预期 `STEP6D_DEMO_PASS samples=24 tail=1 full_cycles=24 stable_inputs=1`。
4. 已运行到终点时，使用 `restart` 回到 0 ns，再 `run 300 us`；无需重建综合或布局布线。

DEMO=1 在请求峰值的下一个下降沿准备样本，下一个上升沿接受；电流、角度、参考值和母线保持到下一组样本，不每拍毒化输入。演示使用固定 48 V，包含零输入、明确 PI reset、d_current、q 轴输入及连续参考阶跃。24 笔演示各观察一个完整应用周期，额外一笔 tail 维持最后观察周期中的合法供数，然后正常停止。tail 不计入 24 笔。这是固定输入驱动，没有电机模型反馈，不代表电流跟踪性能。

波形按 captured 输入、FOC 原始调制量、上管 duty/CMP、shadow/active、载波/PWM、当前 active 对应平均电压分组。电流/电压 real 别名由 F15 除 32768，duty 的 F24 除 16777216；theta_e 是 U16 二进制角度（65536 对应 2π），不是 signed F15。real 只存在测试台。

## 极性和时序

`d_foc` 是既有 C3 的调制量。显式转换为 `D_high = clamp(1 - d_foc, 0, 1)`，再计算 `CMP = floor((D_high_raw * 2500 + 2^23) / 2^24)`。0/25/50/75/100% 上管占空比分别对应 CMP=0/625/1250/1875/2500；不反转 PWM 引脚，不交换相序。

适配器在 Q 接受一笔输入，Q+1 乘法，Q+2 输出 valid，最早 Q+3 握手。valid 与三相 CMP 在背压下保持；仅一笔容量，flush 同步清除未提交结果。

共享载波 0→2500→0，50 MHz 时钟下每周期 5000 拍，即 10 kHz。峰值 P 产生请求，N=P+1 接受样本且 C4 同边沿捕获。正常 C4 在 N+512 给出结果，N+513 适配器接受，N+515 CMP valid，N+516 PWM 接收并写 shadow。目标 ZERO 为 N+2499，三相 active 同边沿更新，下一拍确认后释放事务位置。计算完成、命令接收、命令生效是三个不同事件。

初始 active=0，首个目标 ZERO 前三相 LOW。停止后必须硬件复位才能恢复；FOC 错误、超时或供数协议错误锁存 needs_reset，禁止陈旧结果重新提交。fault_code 为 0 无故障/用户停止、1 FOC 错误、2 deadline/load、3 sample/handshake；底层错误可看 `dut.last_foc_error`。

完整 ZERO→ZERO 周期在 NBA 后计数，包含起始 ZERO、不含下个 ZERO，三相各满足 HIGH=2×CMP。平均电压用当前 active 样本的 Vdc 和实测 HIGH 重建。方向测试在线性区单独比较；限幅、过调制或 clamp 输入不能据此声称复现不可实现的原电压。

这里输出三路 GPIO 逻辑 PWM；实际门极极性未经确认，没有六路互补门极、死区、过流 trip、ADC/编码器或板级约束，不能直接接功率级。

## 自动验收

在主目录运行：

```powershell
python scripts/step6d_foc_pwm_reference.py --generate
python scripts/step6d_foc_pwm_reference.py --check
& 'E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat' -mode batch -source scripts/step6d_foc_pwm_build.tcl
```

`--generate` 仅用于有意生成新 6D 向量；最终 build 只 `--check`。每次 build 使用新时间戳（可传 `-tclargs label`，label 不可复用），保留报告于 `docs/reports/step6d/label`。无 bitstream 或硬件操作。已有同源且 NEEDS_REFRESH=0 的完成运行可复用，陈旧完成运行直接报错保留，不自动清理。

build 包含适配器+真实 PWM、两套参数 DEMO=0 集成、默认 DEMO=1、原 C4 两套功能回归、原 PWM 回归，随后默认参数 50 MHz 综合/route 与时序检查。DEMO=0 每套原始历史输入 80 笔加 1 笔 tail，另做独立故障检查；不将 tail 或故障样本计入 160 笔基础比较。profile 1 只验收仿真。

`.sim`、`.runs`、波形及检查点保留本地，不整体提交 Git。原 `FOC_Current` 工程不修改。执行结果与警告见 `coordination/reports/step6d_codex_report.md`。
