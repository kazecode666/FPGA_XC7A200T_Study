# ChatGPT ↔ Codex Project Handoff

GitHub 保存 ChatGPT 设计/Review 与 Codex 本地实现之间的交接；用户主项目目录保存可直接使用的工程成果。

## 当前用户要求：本地主目录实施，功能优先

- 这是学习项目。先把框架与主功能跑通，再做必要的数值、协议和实现时序检查；不建设产品级测试平台。
- **从 Step 6C4 起，实际整合必须在用户原本的本地项目目录进行，不再创建 linked worktree、额外 clone 或云端实施副本。** 这个明确要求覆盖旧任务/技能中的默认隔离建议。
- 可以在同一个本地主目录建立功能分支。分支不等于另一个文件夹。结束时该目录仍保留 C4 文件和可用 Vivado 工程，不能只返回 worktree 路径。
- ChatGPT 负责接口约定、任务交接、设计决定及 PR Review；Codex 负责本地主目录同步、授权 RTL/TB/Tcl/XDC 实现、Python/Vivado 运行、报告和实现 PR。
- 保留用户未提交/未跟踪文件以及旧 worktree；不使用 reset --hard、clean -fd、强制切分支、自动 stash、整体目录覆盖或自动清理。
- 不使用 SHA-256/文件哈希验收。使用 Git 状态/差异、真实源码路径、测试和工具报告。
- 不猜引脚、时钟、数值尺度、极性、状态更新和事务时序。遇到阻塞同步的本地冲突，列出实际路径，不以删除用户内容解决。
- 实现完成停在开放 PR；不自动合并、不自动开始下一阶段、不生成 bitstream 或操作硬件。

## 已接受基线

| 阶段 | 状态 |
|---|---|
| Steps 1–4 | PWM 学习、综合、50 MHz 路由/时序基线 |
| Steps 5A/5B | LED blink/breathing，已做板级演示 |
| Step 6A | Simulink PI-FOC 算法审计，PR #10 已合并 |
| Step 6B | 三相 motor PWM，PR #11 已合并 |
| Step 6C1 | 定点变换，PR #12 已合并 |
| Step 6C2 | dq PI、前馈、圆形限幅，PR #14 已合并 |
| Step 6C3 | Sector SVPWM，PR #17 已合并 |
| Step 6C4 | 当前：本地主项目整合任务 |
| Step 6D | 后续：duty_to_cmp / PWM 时间集成 |

C3 接受提交：`4eb050bd62f6ac7c80ecf3f0a4a017d62f07d1ef`。C1/C2/C3 已合并，先从 Git 主线同步到本地主目录，不从各个旧 worktree 分别拼接代码。

## 依据与保护范围

读取当前任务及 `coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`，再查看已验收的阶段规格和真实接口。数学参考来自 Step 6A audit/golden；历史 DSP/MIL 原始计数不能替代 FPGA 归一化 duty 契约。

本轮 C1/C2/C3 已验收 RTL/TB/ROM/fixtures/projects/scripts/reports、PWM、Simulink、Step 6A source/golden/verifier 全部只读。同步已合并文件不授权改写其内容。旧非阻塞建议不混进本任务。

## 当前唯一 C4 任务书

```text
coordination/tasks/step6c4_foc_local_integration.md
```

此文件合并了接口契约、主目录操作规则、测试范围和实施计划，不再要求另一份重复的规划 PR。本文档变更不是 RTL 实现完成的声明。

核心范围：

```text
mc_current_transform -> mc_pi_dq_core -> mc_inv_park -> mc_sector_svpwm
                           |
                    仅 C2 管理 PI 状态

输入：完整三相电流/角度/速度/参考/母线/PI命令样本
输出：S26/F24 duty + result_valid/error_code + command_valid
顶层：mc_foc_current_core，PI_PROFILE=0/1，固定 N+512
本地工程：FOC_Current/FOC_Current.xpr
```

保存同一笔 sin/cos 和 vdc；错误不作为有效 duty。enable 只控制接受，不是急停。C2 成功就更新状态，不假装可以在后级错误时自动回滚。内部时序故障报告后需硬件复位恢复。

两套参数做整链仿真，默认 profile 0 做整核 50 MHz route；不把独立 C3 的浮点误差门槛/扇区例外外推为 C4 指标。整链 RTL 对组合整数参考逐位一致；原 Step 6A 浮点误差单独如实报告。

## Codex 启动指令

用户已要求推进 Step 6C4，并指定本地主项目实施。接受本交接 PR 后，在 Codex 的本地主项目会话中执行：

```text
开始 Step 6C4，读取 coordination/HANDOFF.md 和
coordination/tasks/step6c4_foc_local_integration.md。

先检查当前目录、git rev-parse --show-toplevel、git worktree list --porcelain、
远端与本地修改，确定用户原本的主项目绝对路径 MAIN。
把已经合并的 C1/C2/C3 非破坏性地同步到 MAIN。
所有新源码、FOC_Current 工程、仿真和综合都在 MAIN 进行。
不要新建 worktree，不要复制整个旧 worktree，不删除用户原有文件。
在 MAIN 内使用 step6c4-foc-current 分支。

按任务书跑通四个模块的完整主链，完成 512 拍调度、两套参数整链仿真、
实际 Step 6A 原始输入回放、默认参数的 Vivado 50 MHz 综合/路由。
保留 FOC_Current.xpr 的本地实际运行结果，并实际启动该工程的默认仿真。
按任务书生成简短报告与学习波形；不用额外搭建大型失败测试框架。

最后提交实现 PR：Step 6C4: Integrate PI-FOC in the main local project。
向用户返回 MAIN 和 FOC_Current.xpr 的真实绝对路径；不要只给 worktree 路径。
停在开放 PR 等待 Review，不自动合并，不进入 Step 6D，不生成 bitstream。
```

如果当前会话不能访问 MAIN，明确报告而不是换目录继续实施。ADC、编码器、PWM 连接、互补门极/死区/保护、MPSoC 均不在 C4 范围内。
