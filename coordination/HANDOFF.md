# ChatGPT ↔ Codex Project Handoff

GitHub 保存设计、任务书和 Review；用户原始本地主项目保存可以直接打开的 Vivado/MATLAB 工程及真实运行结果。

## 工作约定

- 这是学习项目。先验证主链与工具联动，再做必要检查，不建设产品级基础设施。
- 实际实施仅在用户原始主目录 `D:/Project/FPGA_XC7A200T`，不新建 linked worktree、额外 clone 或云端实施副本。
- ChatGPT 负责接口设计、任务交接和 PR Review；Codex 负责本地环境审计、授权实现、MATLAB/Vivado 执行、报告和开放 PR。
- 保留用户 tracked/untracked 内容、硬件资料、旧 worktree、`FOC_Current`、`FOC_PWM`、`FOC_Gates` 的本地结果。
- 不使用 reset --hard、clean -fd、强制切分支、自动 stash、整体覆盖或自动清理。
- 不使用文件哈希作为验收；使用 Git 差异、真实工具输出和可复现实验。
- 实现/审计完成停在开放 PR；不自动合并、不自动开始下一阶段。

## 已接受基线

| 阶段 | 状态 |
|---|---|
| Step 6A | Simulink PI-FOC 审计，PR #10 已合并 |
| Step 6B | 三相 motor PWM，PR #11 已合并 |
| Step 6C1 | 定点变换，PR #12 已合并 |
| Step 6C2 | dq PI、前馈、圆形限幅，PR #14 已合并 |
| Step 6C3 | Sector SVPWM，PR #17 已合并 |
| Step 6C4 | 完整 FOC 电流算法核，PR #19 已合并 |
| Step 6D | FOC→CMP→三相 PWM，PR #21 已合并 |
| Step 6E | 六路互补 PWM、死区、同步关断，PR #23 已合并 |
| Step 7A | 当前：MATLAB R2026b / AMD HDL co-simulation 环境审计 |

Step 6E 合并提交：`dcbbd6f5744f5282cb00d38a301298dacb3007fe`。

当前数字控制器基线已经具备：

```text
三相电流/角度/参考
 -> FOC
 -> d_foc
 -> D_high / CMP
 -> 三相 center-aligned PWM
 -> 六路互补逻辑 + 参数化死区
```

本地主工程：

```text
FOC_Current/FOC_Current.xpr
FOC_PWM/FOC_PWM.xpr
FOC_Gates/FOC_Gates.xpr
```

后续用户路线已经确定：优先复用已有 Simulink 平均值逆变器（含死区效应）和电机模型，与当前 HDL 控制器做联合仿真；以后再研究 JMAG/Maxwell 电磁模型联动。不要主动重写一套 SystemVerilog 电机模型。

## 当前 Step 7A 任务

唯一任务书：

```text
coordination/tasks/step7a_matlab_hdl_cosim_environment_audit.md
```

这是**环境审计 + 最小联合仿真可行性试验**，不是完整 FOC/Simulink 集成。

用户当前环境已知：

- MATLAB/Simulink：R2026b；
- 已更新 SoC Blockset Support Package for AMD FPGA and SoC Devices；
- Vivado：当前工程使用 2026.1；
- 操作系统：Windows；
- 当前 HDL 开发与 route 基线继续使用 Vivado 2026.1。

官方当前基线需在报告中对照：

- R2026b 起，AMD HDL Coder/HDL Verifier 等旧 support package 功能合并到 SoC Blockset Support Package for AMD FPGA and SoC Devices；
- support-package 合并不自动等于 HDL Verifier 产品许可；
- HDL co-simulation 属于 HDL Verifier；
- MathWorks 当前公开的 Vivado Simulator 推荐/完整测试版本仍为 2024.1。

因此 Step 7A 必须用本机证据判断 **R2026b + Vivado 2026.1** 是否实际可用，而不是凭版本名称推断。

## Codex 启动指令

在用户本地 Codex 会话执行：

```text
开始 Step 7A 环境审计。

先读取：
coordination/HANDOFF.md
coordination/tasks/step7a_matlab_hdl_cosim_environment_audit.md

只在原始主目录 D:/Project/FPGA_XC7A200T 工作。
先检查 Git 工作树/远端/本地修改；不要创建 worktree 或额外 clone。
本任务不修改 FOC/PWM RTL，不重建已有工程，不安装或卸载任何软件。

按任务书检查：
1. MATLAB R2026b 的实际版本、ver、addons；
2. Simulink、SoC Blockset、HDL Verifier、HDL Coder、Fixed-Point Designer 的安装与许可可用性；
3. SoC Blockset Support Package for AMD 的实际安装版本；
4. Vivado 2026.1 和机器上其他 Vivado/Vitis 版本；
5. R2026b 本地文档/工具对 Vivado Simulator 的版本识别；
6. 若所需产品/许可齐全，使用系统临时目录做一个最小 HDL co-sim 示例，证明 MATLAB/Simulink 与 Vivado Simulator 真正交换数据。

不要用完整 FOC 当第一个联通例子。
不要 patch MathWorks 版本检测。
不要改 Windows 全局 PATH。
如需临时 MATLAB tool path 配置，先记录旧值、当前会话修改、结束前恢复。

最后给出 A/B/C/D 之一：
A READY_NOW
B READY_WITH_SUPPORTED_VIVADO
C MISSING_COMPONENT_OR_LICENSE
D OTHER_BLOCKER

写：
coordination/reports/step7a_matlab_hdl_cosim_environment_audit.md
docs/reports/step7a/

提交 PR：
Step 7A: Audit MATLAB R2026b HDL co-simulation environment

停在开放 PR 等待 Review。
不要自动安装 Vivado 2024.1，不要开始完整 FOC/Simulink 联合仿真，不要开始 Vitis/SoC 迁移。
```

## 本阶段完成边界

Step 7A 只回答“现有电脑环境是否具备 HDL 联合仿真条件，以及卡在哪里”。

后续如果环境 Ready，再单独设计：

```text
Simulink 平均值逆变器/电机模型
              ⇅
HDL Verifier co-simulation
              ⇅
现有 FOC/PWM HDL
```

联调阶段必须区分：

- Simulink 逆变器接受的是 duty、active CMP、三路 raw PWM 还是六路 gate；
- 死区由哪一侧建模，避免 RTL 与 Simulink 重复计算；
- Simulink solver/sample time 与 50 MHz HDL 时钟、100 us 控制周期、ZERO 更新的映射；
- 定点/浮点边界及角度/电流/母线单位。

这些接口不在 Step 7A 中实现。
