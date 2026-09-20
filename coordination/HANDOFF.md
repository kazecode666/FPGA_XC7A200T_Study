# ChatGPT ↔ Codex Project Handoff

GitHub 保存设计、任务书和 Review；用户原始本地主项目保存可以直接打开的 Vivado 工程及实际运行结果。

## 工作约定：本地主目录实施，学习和功能优先

- 这是学习项目。先把主链做出来，再完成必要边沿/数值/时序验证，不建设产品级失败测试平台。
- **实际实施仅在用户原始主目录，不新建 linked worktree、额外 clone 或云端实施副本。** 上次确认 MAIN 为 `D:/Project/FPGA_XC7A200T`；每次都核对实际 Git 主工作树、远端、分支、权限和用户修改。功能分支仍在同一目录。
- ChatGPT 负责接口设计、任务交接和 PR Review；Codex 负责本地非破坏性同步、授权实现、Python/Vivado 仿真和实现、报告以及开放实现 PR。
- 保留用户 tracked/untracked 内容、硬件资料、旧 worktree、`FOC_Current` 和 `FOC_PWM` 的本地成果。不使用 reset --hard、clean -fd、强制切分支、自动 stash、整体覆盖或自动清理。
- 不使用 SHA-256/文件哈希验收；用 Git 状态/差异、实际源码路径、执行结果和工具报告。
- MAIN 不可访问或存在覆盖风险时，报告实际阻塞，不换一个 worktree 继续，不删除用户内容解决。
- 实现完成停在开放 PR；不自动合并、不开始下一阶段、不生成 bitstream、不操作功率级或硬件。

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
| Step 6C4 | 完整 FOC 电流算法核，PR #19 已合并 |
| Step 6D | FOC→CMP→三相 PWM，本地主项目整合，PR #21 已合并 |
| Step 6E | 当前：六路互补 PWM、死区和统一关断任务交接 |

6D 接受提交为 `2f3461f5716496e323f2aa91debe6e6df1409bd1`。本地已有 `FOC_PWM/FOC_PWM.xpr`，默认 PI_PROFILE=0、DEMO=1。正常采样后 C4 在 N+512 完成，PWM 在 N+516 接受 shadow、N+2499 目标 ZERO 装载；默认 profile 0 已做整核 route，profile 1 仅仿真。

保持 6D 的极性修订：C4 原始调制量 d_foc 与上管 HIGH 比例不同，`D_high=clamp(1-d_foc,0,1)`，`CMP=round(D_high*2500)`。不在门极层再次反相、不交换相序，不改写数学/golden。

## 当前唯一 Step 6E 任务书

```text
coordination/tasks/step6e_complementary_pwm_local_integration.md
```

它合并接口契约、允许变更和四步实施计划；不再另写重复的任务/计划 PR。本交接只有文档，不代表已启动 Codex 或完成 6E RTL。

读取此任务，再读取 6D 任务、现有 `mc_foc_pwm_top`、`motor_pwm_core` 与旧顶层 TB 的真实接口。

本轮结构：

```text
mc_foc_gate_top
  control : 现有 mc_foc_pwm_top
  leg_u / leg_v / leg_w : 三次复用新增 mc_pwm_deadtime_leg

原始三路 pwm → 互锁、死区、使能 → gate_uh/ul/vh/vl/wh/wl
```

关键冻结点：

- 默认 DEADTIME_CYCLES=25（50 MHz 下500 ns，仅仿真演示），本版参数范围1..2500。单元仿真1/25/50，不实现零死区旁路。
- 关闭不延迟；新目标从单桥臂实际采到请求的 E 开始等待，到 E+D 才开启。等待中反向/禁用/故障取消优先，短脉冲不迟到补发。原 PWM 在 B 更新、桥臂在 B+1 采到，区分这一拍与死区长度。
- 六路始终不能同桥臂同时为1。未使能、首次命令之前、停止、trip、复位均全关；不是下管始终等于上管取反。
- 首次真实 active 装载 S 后，S+1 置 armed，S+2 桥臂开始启动等待；稳定请求时最早 S+2+D 开启。armed 不在每次 ZERO 重置。
- **trip_req 本轮为同步数字请求**，在采到的时钟边沿六路清零并锁存。没有外部异步窄脉冲捕获/失钟保护保证；不冒充真实硬件过流保护。只有 reset 清除 trip_latched。
- 停止/trip/旧控制器故障必须取消待开启状态，旧 FOC 结果不能重新使能门极。恢复需 reset、新鲜命令装载和完整启动等待。
- 默认学习演示保持输入稳定，展示六路及死区；必要故障测试只在自检模式。死区后 gate HIGH 不再强制等于2×CMP，死区前 PWM 的既有等式仍保留。

## 保护范围与唯一旧接口例外

C1–C4 数学模块、mc_duty_to_cmp、motor_pwm_core、ROM、参考与向量、Simulink、旧项目/历史报告只读。

为避免复制 6D 调度器或使用可综合跨层引用，本任务仅明确授权：

1. `motor_control_ip/integration/rtl/mc_foc_pwm_top.sv` 添加只读 `pwm_command_loaded` 输出，直接接已有 `compare_load_event`，不修改控制/数据行为。
2. `motor_control_ip/integration/tb/mc_foc_pwm_top_tb.sv` 添加同名 wire/logic，匹配现有 `dut(.*)`；旧测试和计数不变。

其余只新建任务书列出的单桥臂、wrapper、两个 TB、新工程、脚本、波形和报告。端口增加可能让旧 FOC_PWM 的实现需要刷新，应披露，不自动清除旧结果；新 FOC_Gates 做新的完整默认参数 route。

## Codex 启动指令

接受本交接 PR 后，在用户本地主项目 Codex 会话执行：

```text
开始 Step 6E，读取 coordination/HANDOFF.md 和
coordination/tasks/step6e_complementary_pwm_local_integration.md。

核对 MAIN=D:/Project/FPGA_XC7A200T 的实际主工作树、远端和用户修改，
安全同步已合并 main，在同目录使用 step6e-complementary-pwm 分支。
不新建 worktree/clone，不覆盖我的内容，不清理 FOC_Current/FOC_PWM。

先实现单桥臂互补与参数化死区，按实际边沿验证；
再通过唯一授权的只读装载端口扩展，复用旧 6D 顶层和三个桥臂，
实现首次有效命令使能、同步 trip、统一关断和复位恢复。
禁止简单取反生成停机下管；短脉冲和计数终点取消按任务书执行。

在 MAIN 新建 FOC_Gates/FOC_Gates.xpr，默认 PI_PROFILE=0、DEMO=1、
DEADTIME_CYCLES=25。先跑干净、输入稳定的六路演示，
再做少量单元/两套参数整合测试、原 6D 回归和默认50 MHz综合/route。
实际打开该本地工程，保留 .sim/.runs/WDB/DCP 与学习波形。

写 coordination/reports/step6e_codex_report.md 和 docs/reports/step6e/ 证据，
提交实现 PR：Step 6E: Add complementary PWM deadtime and gate shutdown。
返回本地 XPR 的真实路径和演示步骤，停在开放 PR 等待 Review。
不自动合并，不生成 bitstream，不接电机/功率级，不开始联合仿真。
```

## 后续已选路线（不在本轮执行）

用户已有 Simulink 平均值逆变器，包含死区效应，且已有可复用电机模型。后续优先与现有 HDL 控制器联合仿真，不主动重写一套 SystemVerilog 电机模型；以后再研究接入 JMAG/Maxwell 电磁模型。

联调时单独设计端口、定点格式、采样/计算/ZERO 更新时序和工具版本组合。区分死区前理想 duty 与已包含死区的开关信息，避免 Simulink 等效模型和 RTL 重复计算死区。Vitis/SoC 联动不在当前任务中。

本轮不包含真实驱动器极性确认、外部异步 trip、安全保护链、ADC/编码器、电机闭环、引脚/IOSTANDARD/外部I/O时序或硬件验证。默认内部 STA 通过不能证明器件异步行为、驱动器或功率级安全。
