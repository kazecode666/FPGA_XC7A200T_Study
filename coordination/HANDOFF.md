# ChatGPT ↔ Codex Project Handoff

GitHub 保存 ChatGPT 设计/Review 与 Codex 本地实现之间的交接；用户主项目目录保存可直接使用的工程成果。

## 当前用户要求：本地主目录实施，功能优先

- 这是学习项目。先把框架与主功能跑通，再做必要数值、握手和实现时序检查；不建设产品级失败测试平台。
- **从 Step 6C4 起，实际整合必须在用户原本的本地项目目录进行，不再创建 linked worktree、额外 clone 或云端实施副本。** 这个要求覆盖旧任务/技能中的默认隔离建议。
- 上次确认的 MAIN 为 `D:/Project/FPGA_XC7A200T`；每次仍须核对 Git 主工作树、远端、当前分支和本地修改。可以在同一个 MAIN 建立功能分支，不另建文件夹。
- ChatGPT 负责接口约定、任务交接、设计决定及 PR Review；Codex 负责本地主目录同步、授权 RTL/TB/Tcl/XDC 实现、Python/Vivado 运行、报告和实现 PR。
- 保留用户未提交/未跟踪文件、硬件资料、旧 worktree 和已完成的本地仿真/实现结果；禁止 reset --hard、clean -fd、强制切分支、自动 stash、整体目录覆盖或自动清理。
- 不使用 SHA-256/文件哈希验收。使用 Git 状态/差异、真实源码路径、测试和工具报告。
- 不猜引脚、时钟、数值尺度、极性或边沿时序。本地目录不可访问或同步有冲突时，报告具体问题，不换 worktree 继续。
- 实现完成停在开放 PR；不自动合并、不开始下一阶段、不生成 bitstream、不操作硬件。

## 已接受基线

| 阶段 | 状态 |
|---|---|
| Steps 1–4 | PWM 学习、综合、50 MHz 路由/时序基线 |
| Steps 5A/5B | LED blink/breathing，已做板级演示 |
| Step 6A | Simulink PI-FOC 审计，PR #10 已合并 |
| Step 6B | 三相 motor PWM，PR #11 已合并 |
| Step 6C1 | 定点变换，PR #12 已合并 |
| Step 6C2 | dq PI、前馈、圆形限幅，PR #14 已合并 |
| Step 6C3 | Sector SVPWM，PR #17 已合并 |
| Step 6C4 | 完整 FOC 电流算法核、本地主目录工程，PR #19 已合并 |
| Step 6D | 当前：本地主目录 FOC→PWM 任务交接 |

C4 合并提交：`a2f4d1eb63c4cabd5e938d428e4fa436936690d2`。完整算法核为 `mc_foc_current_core`，S26/F24 原始调制量输出，N+512 完成；两套 PI 参数功能仿真通过，只有默认 profile 0 做过整核 route。原本地工程 `FOC_Current/FOC_Current.xpr` 必须保留。

## 当前唯一 Step 6D 任务书

```text
coordination/tasks/step6d_foc_pwm_local_integration.md
```

该文件合并接口修订、工作目录规则和四步实施计划；不需要再开一轮重复规格/计划 PR。本交接 PR 仅有文档，不代表 6D RTL、仿真或本地操作已完成。

读取任务、`coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`、C4 RTL/README 和 `motor_control_ip/pwm/rtl/motor_pwm_core.sv` 的真实接口。

**极性修订优先级：** 6D 任务第 2 节明确区分旧 C3/C4 原始调制量 `d_foc` 与上管 HIGH 比例 `D_high`，并覆盖旧文档将二者直接等同的表述：

```text
D_high = clamp(1 - d_foc, 0, 1)
CMP = round(D_high * 2500)
```

C4 数学值及 Step 6A golden 不变；Step 6B 仍是 HIGH duty=CMP/TBPRD，不翻转 pwm 引脚、不交换相序。本次只是定义仿真中的上管逻辑请求，不确认真实门极驱动器极性。其余已验收契约不变。

C1–C4/PWM 的 RTL、TB、ROM、参考、向量、旧项目及报告，Simulink 和 Step 6A 全部只读。本轮仅增加任务书授权的 integration、FOC_PWM、6D 脚本和报告文件；不修旧模块、不把旧 worktree 复制回来。

## 本轮核心范围

```text
mc_foc_current_core -> mc_duty_to_cmp -> motor_pwm_core
        已有               新增              已有

新增 mc_foc_pwm_top：峰值后固定一拍供数窗口、命令位置预留、目标 ZERO 归属、启停
时钟 50 MHz；载波 TBPRD=2500；PWM 10 kHz
C4 N+512；适配与无反压命令握手预计到 N+516，必须实际测量
三相 shadow 同拍接收，下一 ZERO 原子装载；不能丢失或应用过期命令
```

默认 GUI 是干净的 DEMO=1：峰值供数后输入保持，不每拍毒化输入，约 24 个周期足以观察主链。DEMO=0 运行两套参数的历史输入集成自检与少量关键边界。默认 profile 0 做完整 6D 顶层 50 MHz route，profile 1 仅仿真则如实声明。

新增本地 `FOC_PWM/FOC_PWM.xpr`，引用 MAIN 里的源码、ROM/向量；保留本地 .sim/.runs/WDB/DCP，真正打开默认演示。只返回远端 PR 或 worktree 路径不算完成。

## Codex 启动指令

接受本交接 PR 后，由用户在本地 Codex 项目会话执行：

```text
开始 Step 6D。先读取 coordination/HANDOFF.md 和
coordination/tasks/step6d_foc_pwm_local_integration.md。

确认 MAIN 是我的原始本地主项目 D:/Project/FPGA_XC7A200T，核对 Git 远端、
主工作树和用户修改，安全同步已合并 main，在同目录使用 step6d-foc-pwm 分支。
不要创建 worktree/额外 clone，不覆盖我的修改，不清理旧工程。

先实现 d_foc -> D_high -> CMP 的显式极性适配和单笔握手保持，
再连接已有 C4 与 PWM，跑通峰值供数、FOC 计算、下一 ZERO 三相装载。
保留 C4/PWM/参考文件不变，不用 NOT 输出或相序交换掩盖极性。

默认演示输入保持稳定，让我能直接看懂占空比和 PWM；
必要的自动检查另用 DEMO=0，不搭产品级失败测试框架。
完成两套参数集成仿真、关键原 C4/PWM 回归及默认参数 50 MHz 综合/route。

在 MAIN 留下 FOC_PWM/FOC_PWM.xpr 和真实仿真/实现结果，
实际打开并运行默认 PI_PROFILE=0、DEMO=1 演示，加载 wave_step6d.tcl。
写 coordination/reports/step6d_codex_report.md 和 docs/reports/step6d/ 证据。

提交实现 PR：Step 6D: Integrate FOC duty adapter and motor PWM。
返回本地 XPR 绝对路径和演示打开步骤，停在开放 PR 等待 Review。
不自动合并，不生成 bitstream，不接电机/功率级，不进入下一阶段。
```

本轮没有电机模型闭环、ADC/编码器、六路互补门极、死区/过流保护、AXI/MPSoC、板级引脚或硬件验证。停止/故障后的复位恢复只是数字接口约定，不是硬件安全认证。
