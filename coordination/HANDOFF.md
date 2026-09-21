# ChatGPT ↔ Codex Project Handoff

GitHub 保存设计、任务书和 Review；用户原始本地主项目保存可直接打开的 Vivado/Simulink 工程与真实运行结果。

## 工作约定

- 这是学习项目。先把主链和工具联动跑通，再做必要验证，不建设产品级基础设施。
- 实际实施仅在用户原始主目录 `D:/Project/FPGA_XC7A200T`，不新建 linked worktree、额外 clone 或云端实施副本。
- ChatGPT 负责架构、任务交接和 PR Review；Codex 负责本地非破坏性同步、MATLAB/Vivado 执行、授权 RTL/SLX/script 修改、报告和开放实现 PR。
- 保留用户 tracked/untracked 内容、硬件资料、旧 worktree、`FOC_Current`、`FOC_PWM`、`FOC_Gates` 和本地仿真/实现结果。
- 不使用 `reset --hard`、`clean -fd`、强制切分支、自动 stash、整体覆盖或自动清理。
- 不使用文件哈希作为验收；使用 Git 状态/差异、真实工具输出和可复现实验。
- 实现完成停在开放 PR；不自动合并、不开始下一阶段、不生成 bitstream、不操作硬件。

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
| Step 7A | MATLAB R2026b / Vivado 2026.1 最小 HDL co-sim 环境审计，PR #25 已合并 |
| Step 7B | 本地实现及完整验收完成，等待开放实现 PR 的 ChatGPT Review |

## Step 7B 实现交付（2026-09-21）

- 报告：`coordination/reports/step7b_codex_report.md`；复现：`docs/reports/step7b/README.md`。
- Simple as-found baseline 独立提交 `6774035`，用户补齐原始依赖后才开始 co-sim 修改。
- 主集成骨架为 `simulink模型/PMLSM_ThreeLoop_Simple.slx`；新增 `FPGA_HDL_Cosim` 仅并联 smoke/monitor、没有输出端口。原 `Control_Task_10kHz -> Inverter_DeadTime -> PMLSM_Plant_Model` 保持。
- 真实 Simulink HDL block/XSI 最小六值、完整 FOC smoke 首笔 active CMP `1165/1335/1335`、6D profile0/profile1、6E profile0、legacy 短仿真全部通过。
- 边界仍冻结为 `D_high = CMP_active / 2500`，7B 中这些 duty 只用于记录。
- 50 us 通信、20 ns HDL 时钟、200 ns 复位、prerun=0：50 us 更新的 NEW B 被 accepted ID1 使用；通信网格上 100 us 观察到 accepted ID1，150 us 观察到 active ID1。三次独立运行一致。首个 peak 稍晚于 50 us；改变复位/预运行设置必须重验。
- AMD support package 26.2.2 被 R2026b 识别；Vivado 2026.1 仍有 not fully tested 警告，但本机实际运行通过。
- **Step 7C 未开始**。首次 FPGA plant 电流闭环留到 Step 7C；本 PR 不合并、不生成 bitstream、不操作硬件。

当前 main（任务书编写时）：
```text
ce9a875449b933cba0bf6d3f2e68b7dc30159280
```

Step 7A 已实测：
- R2026b Prerelease Update 3 + HDL Verifier + Vivado Simulator 2026.1 可以通过 XSI 完成真实 MATLAB System Object ↔ HDL 数据交换；
- Vivado 2026.1 会给“未 fully tested”警告但本机没有 hard reject；
- 用户在 Step 7A 合并后又安装了 SoC Blockset Support Package for AMD FPGA and SoC Devices，Step 7B 启动时只需重新确认当前 R2026b 是否识别它。

## Step 7B 已批准设计

规格：

```text
coordination/specs/step7b_simulink_hdl_cosim_interface_design.md
```

用户已批准并合并 PR #26。

核心冻结点：

1. **长期 Simulink↔HDL 边界采用方案 B：**
   ```text
   D_high = CMP_active / 2500
   ```
   FPGA/RTL 负责 FOC、SVPWM、极性适配、CMP 量化、shadow 和 ZERO 装载；Simulink 看到真正已经生效的 active compare。

2. **主 Simulink 集成骨架改为：**
   ```text
   simulink模型/PMLSM_ThreeLoop_Simple.slx
   ```
   它是用户此前做过功能简化的三闭环副本，保留核心控制、平均值逆变器/死区和 PMLSM plant。

3. **当前 GitHub main 尚未包含该 Simple 模型。**
   Codex 实施时必须先读取用户本地 as-found 文件，并在任何功能修改之前先做独立 baseline commit，把原始 Simple 模型同步到 GitHub。

4. Step 7B 新增并联：
   ```text
   PMLSM_ThreeLoop_Simple/FPGA_HDL_Cosim
   ```
   但本阶段只做 smoke/monitor，不允许接管：
   ```text
   Control_Task_10kHz -> Inverter_DeadTime -> PMLSM_Plant_Model
   ```

5. 第一个完整 FOC Simulink smoke 必须使用历史 d_current 输入，并得到真实 active CMP：
   ```text
   1165,1335,1335
   ```

6. HDL 50 MHz / 20 ns；初始 Simulink↔HDL 通信目标 50 us。必须实测并冻结 50 us 数据更新与 carrier peak 的 scheduler 顺序，不能带 race 进入 Step 7C。

7. 平均值逆变器 deadtime 继续由 Simulink plant 侧负责；Step 6E 六路 gate/deadtime 不进入当前 plant 主链，避免重复 deadtime。

8. 旧 MIL/Simple 的 PWM update-delay 近似在未来 FPGA backend 下旁路，因为 RTL 已真实完成 shadow/next-ZERO 装载。

## 当前唯一 Step 7B Codex 任务书

```text
coordination/tasks/step7b_simulink_hdl_cosim_local_integration.md
```

这份文件已经把正式 implementation plan 和 Codex 启动提示合并在一起，不再另开重复任务文档。

实施顺序：

```text
Task 1  读取/提交 as-found PMLSM_ThreeLoop_Simple baseline
Task 2  最小 Simulink HDL Cosimulation Block ↔ Vivado 2026.1
Task 3  active CMP 只读端口 + mc_foc_cosim_top + XSim 回归
Task 4  Simple 模型并联 FPGA_HDL_Cosim + FOC smoke
Task 5  冻结 50 us scheduler/transaction contract
Task 6  最终回归、报告、GitHub 实现 PR
```

## Codex 启动指令

用户在本地 Codex 会话执行：

```text
开始 Step 7B，严格按 executing-plans 顺序执行。

先读取：
coordination/HANDOFF.md
coordination/specs/step7b_simulink_hdl_cosim_interface_design.md
coordination/tasks/step7b_simulink_hdl_cosim_local_integration.md

只在我的原始主项目：
D:/Project/FPGA_XC7A200T
中工作。

先核对 Git 主工作树、远端、当前修改和已合并 main。
不要创建 worktree/额外 clone，不 stash，不 reset/clean，不覆盖我的文件。

非常重要：
simulink模型/PMLSM_ThreeLoop_Simple.slx 是我本地已有但之前未同步 GitHub 的模型。
先用 MATLAB/Simulink API 只读检查真实结构，在任何功能修改前，
把 as-found 的 Simple 模型和 baseline inventory 作为第一笔实现 commit 纳入分支。
之后再开始修改，并把所有授权的 SLX/RTL/scripts/reports 继续同步到 GitHub。
不要只改本地模型。

按任务书先做最小 Simulink HDL Cosimulation Block + Vivado 2026.1 联通；
再做 mc_foc_cosim_top 和 active CMP 只读端口；
然后在 PMLSM_ThreeLoop_Simple.slx 中新增并联 FPGA_HDL_Cosim branch。

Step 7B 中 FPGA branch 只能 smoke/monitor，
不得接管 Control_Task_10kHz -> Inverter_DeadTime -> PMLSM_Plant_Model 主链。
第一笔 d_current 的真实 active CMP 必须检查为 1165/1335/1335。

把 50 us Simulink 数据更新与 HDL carrier peak 的 scheduler 顺序实际测出来，
连续三次新鲜仿真一致后冻结 timing contract，不凭假设。

确认新安装的 SoC Blockset Support Package for AMD 是否被 R2026b 识别；
这不是重新做 Step 7A，也不要因为 support package 问题去 patch MATLAB。
HDL simulator 仍使用现有 Vivado 2026.1。

完整重跑任务书列出的 Step 7B 验收和原 6D/6E必要回归。
不跑 bitstream、不操作硬件、不开始电机闭环、不进入 Step 7C。

最后写：
coordination/reports/step7b_codex_report.md
docs/reports/step7b/

推送实现分支并创建 PR：
Step 7B: Add Simulink HDL co-simulation interface

返回 PR、本地模型路径和复现步骤，停在开放 PR 等待 ChatGPT Review。
```

## 后续边界

Step 7B 结束时，只证明：

```text
Simulink HDL Cosimulation Block
        ↕
Vivado 2026.1 / XSI
        ↕
existing FOC/PWM HDL
        ↓
real CMP_active
```

并且这些结果已经挂进 Simple 模型的并联 branch。

Step 7C 才正式把：

```text
CMP_active / 2500
```

接入 `Inverter_DeadTime`，闭合静止电流环。

Step 7D 再恢复/拆分速度环和位置环，形成完整三闭环联合仿真。
