# Step 6E：六路互补逻辑 PWM、死区和统一关断

实际本地工程：`D:/Project/FPGA_XC7A200T/FOC_Gates/FOC_Gates.xpr`。
源文件、ROM 和 6D 原始向量引用同一 MAIN；原 `FOC_Current`、`FOC_PWM` 及其运行结果仍保留。
器件 xc7a200tfbg484-2，时钟 50 MHz，原载波周期 100 us/10 kHz。

## 打开稳定输入演示

1. 在 Vivado 2026.1 打开上述 XPR，选择 Run Behavioral Simulation。默认 `PI_PROFILE=0 DEMO=1 DEADTIME_CYCLES=25`，初始停 0 ns。
2. 在 Tcl Console 输入：

   ```tcl
   source D:/Project/FPGA_XC7A200T/FOC_Gates/wave_step6e.tcl
   run 300 us
   ```

3. 先观察三个载波周期：首次装载前六路全关；之后 U/V/W 各自互补并留双关间隔。把时间轴放大到 1–2 us，查看默认 500 ns 死区。
4. `run all` 完成 24 笔演示和 1 笔明确 tail，预期 `STEP6E_DEMO_PASS`。已运行到终点时先 `restart`，再 `run 300 us`。不必重新综合/route。

演示输入在采样之间保持稳定，包含零输入、d_current、q 轴及参考阶跃；没有故障注入，也没有电机反馈。最后一笔基础命令观察满一个完整周期，tail 单独计数，然后正常停止。DEMO=0 单独运行自动检查，不把故障波形混入默认学习演示。

## 原始 PWM 与六路 gate

`control` 复用已有 FOC→CMP→三相 PWM，`leg_u/v/w` 三次复用同一单桥臂模块。6D 的极性保持：`D_high=clamp(1-d_foc,0,1)`；门极层不再反相或交换相序。

gate_h=1 请求该相上管导通，gate_l=1 请求下管导通。两路都为 0 表示未使能或死区；下管不是始终等于上管取反。运行中 0% 上管 duty 会在启动等待后保持下管请求；停机则上下管都关。

DEADTIME_CYCLES 是编译期整数，支持 1..2500，默认 25（500 ns，仅仿真学习设定）。非法参数在展开时以 `ERROR_DEADTIME_CYCLES_MUST_BE_1_TO_2500` 拒绝。没有零死区旁路。

原 PWM 在 B 上升沿更新，桥臂在 B+1 才采到，此时定义为 E。E 立即关闭旧侧，从 E 到 E+D-1 两路均关，E+D 开启目标侧。B→E 一拍是注册采样延迟，不额外算作死区；真实双关间隔为 D 拍。

等待中反向会取消旧目标，从新的 E 重新等满 D。请求宽度 ≤D 不补发；D+1 可以产生一拍目标脉冲。精确终点遇到反向/禁用/故障，取消优先，不产生一拍迟到脉冲。

第一次真实 active 装载为 S；S+1 wrapper 置 armed，S+2 单桥臂开始启动等待，稳定请求下最早 S+2+D（默认 S+27）开启。armed 随后保持，不在每个 ZERO 重置。FOC 计算完成、shadow 接收、active 装载仍是不同事件：N+512、N+516、N+2499。

## 停止、trip 与恢复

run_enable=0 或同步 trip_req=1 在采到的时钟边沿将六路清零并取消等待。trip_req 直接参与桥臂输入允许条件，trip_latched 只由 reset_n 清除；撤销 trip 或重新 run 不恢复。旧控制器 needs_reset 在 F 置位时，门极在 F+1 清零。fault_code 保持旧 0/1/2/3 含义，trip 用单独 trip_latched 表示。

恢复必须整链 reset，再接受新鲜命令、实际装载并等满启动死区。reset_n 异步断言，系统负责同步释放；trip 若保持高穿越 reset 释放，首个时钟重新锁存且六路始终不开。

trip_req **是同步数字请求**，须满足时钟建立保持；不保证未跨采样边沿的异步窄脉冲捕获或失钟关断。本轮没有真实驱动器极性、独立 disable/过流链、板级 IO 约束或硬件验证，不直接接功率级。

## 自动验收与保留的结果

在 MAIN 运行：

```powershell
& 'E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat' -mode batch -source scripts/step6e_gate_build.tcl
```

可传 `-tclargs label` 使用尚不存在的报告标签。build 运行 D=1/25/50 单桥臂、默认 D=25 的两套新集成自检、默认干净演示、原 6D 两套自检，再完成新工程默认参数综合/route。其他 PI/死区参数仅仿真，不宣称已 route。相同设计 NEEDS_REFRESH=0 才允许复核复用完成运行，并记录是否计算或复用；不自动清理陈旧结果。

门极逐拍参考记录绝对边沿号，与 RTL 倒计数独立；边沿前保存原始请求，NBA 后比较六路。死区前 PWM 仍检查每个 5000 拍周期 HIGH=2×CMP，死区后门极不套用该等式，也不补脉冲。关断期间的实际电机端电压取决于器件/电流路径，本轮不声称验证死区电压误差或闭环性能。

波形按原 PWM、U 相等待/H/L、V/W、使能/关断、sample→loaded 和物理输入分组。real 只在 TB：F15 电流/电压除 32768、F24 duty 除 16777216、theta 为 U16 二进制角度。

旧 RTL 只添加 `mc_foc_pwm_top.pwm_command_loaded=compare_load_event` 只读输出；旧 TB 仅增加同名声明。共享源已变，旧 FOC_PWM 检查点不能作为新接口的时序证据；其 .runs/.sim 保留，不自动刷新。新 FOC_Gates 保存本轮结果。

报告为 `coordination/reports/step6e_codex_report.md`，文本证据为 `docs/reports/step6e/`；.sim/.runs/WDB/DCP 本地保留而不整体提交。既有 RAM 异步控制等警告如实披露，内部 STA 通过不证明异步器件行为或板级安全。无 bitstream、硬件操作或联合仿真。
