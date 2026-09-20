# Step 6E — 六路互补 PWM、死区与统一关断：本地任务及实施计划

> 给 Codex：使用 executing-plans 顺序实施；仅在用户原始本地主目录工作，不创建 worktree、额外 clone 或云端实施副本。先跑通一个桥臂，再复用三次，不建设产品级验证平台。

**日期：** 2026-09-20。
**目标：** 在已通过的 FOC→三路逻辑 PWM 后增加六路互补输出处理，清楚展示互锁、死区、首次有效命令使能、停止和 trip。
**架构：** 新增一个单桥臂模块 `mc_pwm_deadtime_leg` 和一个整合顶层 `mc_foc_gate_top`。复用既有 `mc_foc_pwm_top`，不复制 FOC、调制适配或载波状态机。
**技术：** SystemVerilog、Vivado/XSim 2026.1、Tcl/XDC；物理单位显示只在测试台使用 real。
**依据：** 用户已认可的 Step 6E 方案；本文件同时给出接口契约和实施顺序，不另拆重复规格/计划。
**基线：** PR #21 已合并，main 为 `2f3461f5716496e323f2aa91debe6e6df1409bd1`。本文档不是 RTL 已实现或本地任务已启动的证据。

## 1. 工作目录与不做的事情

MAIN 上次确认为 `D:/Project/FPGA_XC7A200T`。实施前实际检查当前目录、`git rev-parse --show-toplevel`、`git worktree list --porcelain`、`git remote -v`、分支与 `git status --short`，确认有权访问该原始主项目，远端为 `kazecode666/FPGA_XC7A200T_Study`。

fetch 最新已接受主线，检查上游变更与用户修改无冲突后，在同一 MAIN 使用 `step6e-complementary-pwm` 分支。保留用户 tracked/untracked 内容、硬件资料、旧 worktree、`FOC_Current` 与 `FOC_PWM` 的仿真/实现结果。不使用 reset --hard、clean -fd、强制切分支、自动 stash、整体复制覆盖或自动清理。不能访问 MAIN 或同步会覆盖用户内容时，报告真实路径并停止相关写入。

新增 `FOC_Gates/FOC_Gates.xpr`，引用 MAIN 源码。已完成的工程保持原位，不把结果只留在另一个工作树。本轮不生成 bitstream，不约束真实引脚，不接功率级、电机、ADC、编码器或外部异步故障电路。

不做高分辨率 PWM、动态变频、双边更新、死区补偿、自适应死区、自动重试或运行时参数总线。既有 50 MHz、10 kHz、TBPRD=2500，以及 6D 的极性适配和 ZERO 装载规则保持不变。

## 2. 输出含义与参数

六路输出命名 `gate_uh/gate_ul/gate_vh/gate_vl/gate_wh/gate_wl`；1 表示相应上管/下管的逻辑导通请求。真实驱动器是否高电平有效不在本轮确认。输出不是可以直接接功率器件的门极驱动。

| 状态 | 上管请求 | 下管请求 |
|---|---:|---:|
| 已使能、期望上管导通，死区已结束 | 1 | 0 |
| 已使能、期望下管导通，死区已结束 | 0 | 1 |
| 死区、未使能、首次有效命令之前、停止、trip 或复位 | 0 | 0 |

不能始终使用 `gate_l = !gate_h`，也不能通过把停机时的原始 PWM=0 取反来打开下管。运行中的 0% 上管占空比与整个桥臂关闭是不同状态。

`DEADTIME_CYCLES` 为编译期整数参数，默认 **25**；本版支持 **1..2500**，非法值在 elaboration 明确报错。计数宽度使用至少 1 位的 `$clog2(DEADTIME_CYCLES+1)`，不写死为 5 位。单元测试取 1、25、50，集成默认 25；不实现零死区旁路。

50 MHz 下默认死区为 25×20 ns=500 ns。这只是学习仿真的设定，不是对实际器件安全死区的推荐；真实驱动器、器件关断与传播延迟确定后另行设计。

## 3. 单桥臂接口与精确边沿行为

```text
mc_pwm_deadtime_leg #(DEADTIME_CYCLES=25)
inputs : clk, reset_n, gate_enable, pwm_req
outputs: gate_h, gate_l
```

`pwm_req=1` 请求上管，0 请求下管。门极输出必须由寄存器驱动，禁止用 LUT 组合 AND/NOT 直接在最终输出端做关断或互补。正常请求和 gate_enable 由本时钟域提供；reset_n 异步断言，系统负责同步释放。

定义 **E 为单桥臂在 clk 上升沿实际采到新请求的边沿**，D=DEADTIME_CYCLES。

- gate_enable=0：在该边沿两路立即写 0，取消目标和等待计数。不在后台累计死区，不保留待开启动作。
- gate_enable 从禁用状态变成可用：E 两路保持 0，捕获当前请求，开始完整 D 拍等待；请求持续不变时 E+D 才允许目标侧开启。
- 请求与当前目标不同时：E 关闭原导通侧，两路均为 0，登记新目标，重新开始 D 拍等待。关闭不等死区结束。
- 等待过程中请求再次改变：优先取消旧目标，从这次变化的边沿重新等待完整 D 拍。哪怕旧目标从未开启，也采用同样规则，不优化剩余时间。
- 请求稳定时，两路在 E 到 E+D-1 的边沿后均为 0；E+D 边沿后只开启目标侧。不是 E+D-1，也不是 E+D+1。
- 请求恰好在 E+D 改变，或 gate_enable 恰好在 E+D 取消：取消优先，旧目标不能产生一拍毛刺。持续宽度 <=D 的请求脉冲不会被补发；宽度 D+1 且无其他关断时可得到一拍目标脉冲。
- 目标已经导通且请求稳定：维持，不在每个载波 ZERO 重新插入死区。恒定 0%/100% 请求在启动等待后维持相应一路。
- 任意时候都不得同时出现 gate_h=1、gate_l=1。异步 reset_n=0 清空输出、目标及计数，即使当前没有 clk 边沿也清零。

简洁实现可以用目标位、有效位和倒计数器：新目标时装 D；稳定时逐拍减 1，旧计数为 1 且所有允许条件成立时开启目标侧。关断/请求变化必须优先于终点开启。测试参考不要照抄这个计数器，可独立记住最近请求变化的绝对边沿号，使用 `current_edge - target_since >= D` 判断。

**注册延迟要如实区分：** 现有 motor_pwm_core 在 B 边沿更新原始 pwm，单桥臂在 B+1 才采到新值，所以 E=B+1。普通切换的关断发生在 B+1，另一侧在 B+1+D 开启；两侧均关闭的实际逻辑死区仍是 D 拍。不要将这一拍输入采样延迟误计入死区，也不要通过下降沿时钟或组合旁路消除它。

## 4. 三相整合、首次装载与 trip

```text
mc_foc_gate_top #(PI_PROFILE=0, DEADTIME_CYCLES=25)
    control : mc_foc_pwm_top
    leg_u   : mc_pwm_deadtime_leg
    leg_v   : mc_pwm_deadtime_leg
    leg_w   : mc_pwm_deadtime_leg
```

顶层输入是 6D 原有的 clk/reset_n/run_enable/sample_valid 和全部电流、角度、速度、参考、vdc、PI 命令，另加 **trip_req**。输入数值格式不变。输出是 sample_request/sample_ready、六路 gate、needs_reset、trip_latched、fault_code[2:0]。原始 pwm_u/v/w、gate_enable、armed 等内部量经层次访问供仿真，不增加很多调试引脚。

### 4.1 本轮 trip 是同步请求，不冒充异步硬件保护

trip_req 为高有效、满足 clk 建立保持要求的测试台/本时钟域关断请求。它在被采到的那个上升沿就必须使六路输出清零，优先于正常 PWM 和死区结束，不等 FOC、下一个 ZERO 或另一个控制周期。

**不保证捕获未跨越采样边沿的窄异步脉冲，不把它直接连接真实比较器引脚。** 外部异步 trip、失钟时关断、独立驱动器 disable 和器件安全链另行设计；不能仅加两级同步器就宣称满足未知的硬件保护延迟。本轮只完成同步数字请求与锁定恢复契约。

trip_req 被采到后 trip_latched 保持 1，只有 reset_n 清除；trip_req 自行回到 0 不恢复。若 reset 释放后 trip_req 仍高，首个时钟重新锁存，期间六路不得开启。禁止自动重试。

### 4.2 统一允许条件

建议按以下逻辑组织（信号是模块连线，不是组合门极输出）：

```text
control_run = run_enable && !trip_req && !trip_latched
needs_reset = control_needs_reset || trip_latched
gate_enable = reset_n && run_enable && armed
              && !trip_req && !trip_latched && !control_needs_reset
```

control_run 连接旧 control.run_enable。trip_req 必须直接参加门极允许条件，不能仅依赖同一 always_ff 刚写入的 trip_latched，导致关断额外晚一拍。门极最终由单桥臂 always_ff 写零。

旧 control 的 fault_code 0/1/2/3 原样透传；新增 trip 原因用 trip_latched 观测，不把 trip 伪装成某个旧错误码。用户停止可保持 fault_code=0，但既有 control 会要求 reset 才能重新运行。

### 4.3 只在第一笔命令实际装载后允许六路输出

仅有 run_enable 或 FOC command_valid 不足以 armed。必须等待三相比较值真正装载到 active 的事件。

设 S 为第一次成功 ZERO 装载边沿：PWM 在 S 更新 active 与装载事件；新顶层在 S+1 读取事件并置 armed；单桥臂在 S+2 采到 gate_enable 并开始 D 拍启动等待。请求不改变时，首次门极最早 S+2+D 开启（默认 S+27）。在此之前包括所有下管在内六路均为 0。

armed 只在首次成功装载后置位，之后保持，不在每个 ZERO 清零。停止、trip、旧 control_needs_reset 或硬件复位清掉 armed，并取消三相待开启计数。若 S+1 旧 control 的装载校验失败、needs_reset 置位，gate_enable 必须被阻止，不能错误开启。

run_enable 在边沿拉低时，六路在该边沿清零；不能等旧 PWM 已变 LOW 再依靠互补逻辑关闭。旧 control_needs_reset 在 F 边沿输出置位时，单桥臂在 F+1 清零；明确这一拍层间传播界限，不虚称异步立即关断。已有 FOC 在停止后可以算完，但其旧结果不得恢复 gate_enable。重新运行先对整链 reset，然后等待新的首次有效装载和完整启动死区。

## 5. 唯一的旧 RTL 接口扩展：导出装载事件

实际读取的 6D 顶层目前没有公开 compare_load_event。不要用可综合的跨层引用 `control.pwm.compare_load_event`，也不要复制旧调度器，或仅根据 FOC command_valid 猜测装载成功。

**本任务只授权以下小范围兼容修改，覆盖旧文档相应文件完全只读的要求：**

1. `motor_control_ip/integration/rtl/mc_foc_pwm_top.sv`：新增一个只读输出端口 `pwm_command_loaded`，直接连接已有事件，不增加寄存器、不改变旧控制和数据路径：

```systemverilog
// Add to the port list:
output logic pwm_command_loaded
// Add one continuous assignment:
assign pwm_command_loaded = compare_load_event;
```

2. `motor_control_ip/integration/tb/mc_foc_pwm_top_tb.sv`：原实例使用 `dut(.*)`，增加同名 `logic pwm_command_loaded;`，避免 wildcard 端口找不到信号。旧断言、用例、计数和 PASS 标记不变。

新 wrapper 以命名端口接收这个事件。若本地存在其他实例，先查明；只能做保持行为不变的端口连接调整，发现超出上述两文件的仓库修改需要报告，不私自扩大范围。

C1–C4 数学 RTL、mc_duty_to_cmp、motor_pwm_core、ROM、参考脚本、向量、Simulink 和历史报告不变。原 XPR 不覆盖、不改写历史验收结果。新增端口后旧 FOC_PWM 的实现可能被 Vivado 标记需要刷新，要如实说明；不删除其 .runs 结果，也不声称旧检查点仍代表新接口的时序。本轮在新 FOC_Gates 项目做完整综合/route。

## 6. 文件范围

新增：

```text
motor_control_ip/pwm/rtl/mc_pwm_deadtime_leg.sv
motor_control_ip/pwm/tb/mc_pwm_deadtime_leg_tb.sv
motor_control_ip/integration/rtl/mc_foc_gate_top.sv
motor_control_ip/integration/tb/mc_foc_gate_top_tb.sv
motor_control_ip/integration/README_step6e.md
scripts/step6e_gate_build.tcl
FOC_Gates/FOC_Gates.xpr
FOC_Gates/FOC_Gates.srcs/constrs_1/new/foc_gates_clock.xdc
FOC_Gates/wave_step6e.tcl
coordination/reports/step6e_codex_report.md
docs/reports/step6e/
```

允许修改仅第 5 节两个旧文件。既有 6D 的 197 行向量与 Python 组合参考直接复用；无需再造一套数学参考或生成大型新向量集。新测试台的小型事件时间参考直接写在 TB 内。

## 7. 四步实施与最小测试

### A. 单桥臂先跑起来

**接口：** pwm_req/gate_enable → gate_h/gate_l；文件为第 6 节单桥臂 RTL/TB。

- [ ] 完成本地主目录/修改/基线检查，读取本任务和现有 6D 的实际接口。
- [ ] 先写最小 TB：复位后在下降沿放好 enable 与请求，以下一上升沿为 E，检查 E..E+D-1 全关、E+D 只开目标侧；先观察缺模块/功能失败，再实现目标位和计数器。
- [ ] TB 在边沿前保存 enable/request，NBA 后比较；不能将父模块同边沿更新的新 PWM 当作桥臂已采到。参考记录最近启用或请求变化的绝对边沿，独立于 DUT 的计数器。
- [ ] 参数 D=1、25、50 分别运行。同一组定向测试覆盖 H→L、L→H、恒定请求、0/25/50/75/100% 请求、D-1/D/D+1 短脉冲、等待中再次反向、精确终点取消、等待中 disable、异步 reset。已完成的正常 H/L 切换必须非零计数，防止永远全关的假通过。

至少加入如下直接断言；具体期望值由上面的事件参考给出：

```systemverilog
// Check after NBA; gate values must be known and mutually exclusive.
assert (!$isunknown({gate_h,gate_l}) && !(gate_h && gate_l))
  else $fatal(1,"STEP6E_LEG_FAIL overlap/unknown");
assert ({gate_h,gate_l} === {expected_h,expected_l})
  else $fatal(1,"STEP6E_LEG_FAIL edge contract");
```

边沿号与 expected_h/expected_l 在 TB 内明确定义。不要只检查不重叠而不检查开启时刻。

### B. 加入三相、装载使能和统一关断

**接口：** 旧 control 输出原始 PWM 与装载事件，新 wrapper 输出六路及故障状态。

- [ ] 先做第 5 节只读端口与 wildcard 声明修改，编译并运行原 6D 顶层测试确认接口兼容；不改旧断言来迁就新模块。
- [ ] 新 wrapper 复用 control 与三个独立 leg；实现首次装载 armed、同步 trip 锁存、统一 gate_enable；不通过内部层次引用或复制 FSM 规避端口。
- [ ] 第一组全零 FOC 样本跑通：首次 active 装载前六路全关，装载后每相都能出现正常 H/L 脉冲和默认 25 拍死区。不能把上下管全关当作测试成功。
- [ ] trip 定向用例覆盖 H 导通、L 导通、死区等待以及正好预期开启的边沿；停止/旧 6D 故障也各检查一次。请求在合法采样沿前建立，六路按第 4 节时限清零；取消 trip 或重新 run 不得自动恢复。
- [ ] 检查 reset 后新鲜恢复；trip 保持高穿越 reset 释放时仍不开启；尚未首次装载就停止/trip 也不得启动下管。无需每拍故障扫描、复杂故障注入或硬件异步脉冲测试。

### C. 稳定输入演示与精简回归

**接口：** 复用 `motor_control_ip/integration/tb/vectors/step6d_pwm_vectors.txt` 的原始样本，保持当前 6D 的峰值供数规则。

- [ ] 同一个 `mc_foc_gate_top_tb` 提供 `PI_PROFILE`、`DEMO`、`DEADTIME_CYCLES` 参数；默认 0/1/25。DEMO=1 复用 6D 的 24 笔稳定输入加 1 笔明确 tail，无故障注入，最后正常停止。各字段在采样间保持，启动 blank 与正常死区直观看得见。
- [ ] DEMO=0 两套 PI 参数各使用原 80 笔历史输入加 1 tail；逐位检查新输出之前的 FOC duty、CMP/active 与既有期望，并逐拍检查三相门极与事件参考一致。最后一个基础命令的完整应用周期必须观察完，tail 单独计数。
- [ ] 死区前原始 PWM 继续满足 HIGH=2×CMP、5000 拍周期及 N+516 shadow、N+2499 ZERO 装载。死区后的 gate HIGH 数不套用旧等式：开启延迟与短脉冲取消属于新规则。对 gate 使用逐边沿模型和实际死区测量，不补脉冲来凑旧计数。
- [ ] 方向适配保持 `D_high=clamp(1-d_foc,0,1)`，不再反相一次、不交换相序。门极低电平区不是可以仅根据 H/L 反推确定电机端电压的完整器件模型；本轮不声称验证死区电压误差或闭环电流响应。
- [ ] 原 6D 顶层 DEMO=0 的 profile 0/1 各跑一次，确认只读端口没有改变基线。无需重跑全部 C1/C2/C3/C4 单元或它们的综合/route；没有新 Python 数学模型需要验收。

### D. 本地工程、实现时序与交付

- [ ] 创建 FOC_Gates.xpr，顶层 `mc_foc_gate_top`，默认综合 PI_PROFILE=0/DEADTIME_CYCLES=25；默认仿真 PI_PROFILE=0/DEMO=1/DEADTIME_CYCLES=25，启动停 0 ns。源/ROM/向量均实际解析到 MAIN，不引用旧 worktree。
- [ ] 器件 xc7a200tfbg484-2，唯一时钟约束为 `create_clock -name sys_clk -period 20.000 [get_ports clk]`。本轮无引脚、IOSTANDARD 或真实外部 trip 约束，不调用 write_bitstream。
- [ ] 新整核默认配置实际完成 synth_1、impl_1 到 route，保留本地 .runs/.sim/WDB/DCP；WNS/WHS>=0、TNS/THS=0、全部可路由网络完成、零路由错误、无 latch/blackbox/no_clock/内部未约束端点/组合环。记录资源和所有警告，不预设 DSP/LUT 数量。profile 1 和其他死区参数只仿真时如实声明。
- [ ] build 串起三个死区参数的 leg TB、新整合自检两套参数、默认演示、原 6D 整合回归两套参数，再完成默认整核实现。过程退出码、明确 PASS、无 Fatal/Error 与必要计数足够，不搭 parser/failure-probe 平台。
- [ ] 最后一次 RTL/TB/脚本修改后完整再运行。相同设计且 NEEDS_REFRESH=0 的本地结果可复核复用，但记录实际计算和复核时间，不将旧结果冒充不同源码的实现。
- [ ] 默认波形分组：原始 PWM；U 相 H/L 和等待状态；V/W；run/armed/gate_enable/trip_req/trip_latched/needs_reset；sample_request/accept 与 command_loaded。先运行约 300 us 看周期，再放大 1–2 us 看默认 500 ns 双关间隔。整数/逻辑按相应类型显示；物理单位 real 仅在 TB。
- [ ] 从 MAIN 实际打开 FOC_Gates.xpr、加载 wave_step6e.tcl 并运行默认干净演示，保留打开步骤和 PASS 记录。不要最后把 GUI 留在故障注入或非默认参数模式。
- [ ] 中文 README 说明原始 PWM 与六路 gate 的区别、B→E 一拍延迟、默认500 ns、首次 S+27、停止/trip 恢复、真实驱动未验证。同步 trip 不是异步硬件过流保护，已有 RAM 异步控制等警告仍需披露。
- [ ] 执行报告写真实 MAIN/XPR/分支/提交/工具版本；三组 leg 参数和各用例计数；三相启动/关断的实际边沿；两个 profile 与默认演示结果；默认 route、路径/警告/未执行内容；两个旧文件的最小变更及旧工程是否需刷新。
- [ ] git diff --check 并按路径检查暂存内容，保留用户所有文件。只提交授权的新源码/配置/测试/必要文本报告与两处旧文件兼容修改；不整体提交或删除缓存生成物。

命令入口：

```text
vivado -mode batch -source scripts/step6e_gate_build.tcl
```

脚本可接受与 6D 一样的唯一报告标签，但必须提供上述默认入口，不要求用户手动跑几十条命令。标记：

```text
ALL STEP 6E DEADTIME LEG TESTS PASSED deadtime=1/25/50
ALL STEP 6E FOC GATE TESTS PASSED profile=0/1 deadtime=25
STEP6E_DEMO_PASS
STEP6E_BUILD_PASS
```

日志中应输出实际参数值；斜杠表示分别执行，不是一个字面参数。通过标记必须在所有计数/断言检查之后。

## 8. 完成边界与后续路线

实现完成后创建 **Step 6E: Add complementary PWM deadtime and gate shutdown** PR，返回 `D:/Project/FPGA_XC7A200T/FOC_Gates/FOC_Gates.xpr` 的实际确认路径和默认演示步骤，停在开放 PR 等待 Review。不自动合并、不开始下一阶段、不生成 bitstream 或操作硬件。

完成意味着单桥臂与三相六路逻辑在契约内正确互锁、插入死区、首次有效装载后开启、同步停止/trip 取消及复位恢复；不等于真实门极电平、异步保护、功率级直通风险或电机运行已经验证。

后续用户已选择：保留现有 Simulink 平均值逆变器（含死区效应）及电机模型，与现有 HDL 联合仿真；以后再研究 JMAG/Maxwell 电磁模型接口。本轮不重写 SystemVerilog 电机模型、不配置联合仿真或 Vitis。后续接模型时区分死区前理想 duty 与已含死区的开关信息，避免两边重复计算死区；具体数据/时间接口另行设计。
