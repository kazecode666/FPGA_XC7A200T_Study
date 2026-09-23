# ChatGPT ↔ Codex Project Handoff

GitHub 保存设计、任务书和 Review；用户原始本地主项目保存可直接打开的 Vivado/Simulink 工程与真实运行结果。

## 工作约定

- 学习项目：优先把控制主链和联合仿真跑通，再做必要验证，不建设产品级基础设施。
- 实际实施仅在 `D:/Project/FPGA_XC7A200T`，不新建 linked worktree、额外 clone 或云端实施副本。
- ChatGPT 负责架构、任务交接和 PR Review；Codex 负责本地非破坏性同步、MATLAB/Vivado 执行、授权 RTL/SLX/script 修改、报告和开放实现 PR。
- 保留用户 tracked/untracked 内容、硬件资料、旧 worktree、`FOC_Current`、`FOC_PWM`、`FOC_Gates` 和本地仿真/实现结果。
- 不使用 `reset --hard`、`clean -fd`、强制切分支、自动 stash、整体覆盖或自动清理。
- 不使用文件哈希作为验收；使用 Git 状态/差异、真实工具输出和可复现实验。
- 实现完成停在开放 PR；不自动合并、不开始下一阶段、不生成 bitstream、不操作硬件。

## 已接受基线

### 2026-09-23 正式命名与教学说明

PR33 已合并到 `4d1d349`。后续分支 `codex/pmlsm-formal-signals-guide` 基于用户最新本地 R2026b 模型，提交此前 local From/Goto 布局及正式观测命名：`Motor_Control_Monitor`、`motor_control_monitor`、`fpga_interface_monitor`。控制算法和 358 个 Inport/Outport 参数/几何保持；legacy/FPGA 各自 0.2 s 动态段改名前后全采样日志最大差异均为 0。此验证不替代 PR33 完整性能验收。

用户/ChatGPT 教学入口：[模型中文指南](../docs/PMLSM_MODEL_GUIDE_ZH.md)；本次证据：[名称整理报告](../docs/reports/step7d/formal_names_20260923/README.md)。指南解释静态 backend 切换、live 配置、Host 位置参考、观测字段和可运行命令。后续 PR 保持开放等待 Review，不进入下一阶段。

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
| Step 7A | MATLAB R2026b / Vivado 2026.1 最小 HDL co-sim，PR #25 已合并 |
| Step 7B | Simulink HDL Cosimulation block + active-CMP smoke，PR #28 已合并 |
| Step 7C | PR #31 已合并；本地后续布局改动继续保留 |
| Step 7D | PR33 已合并；修订后 Tasks 1–8 完成，`STEP7D_FULL_ACCEPTANCE_PASS`，见 `coordination/reports/step7d_pr33_revision_report.md`。旧 Task4 失败保留为历史事实；后续正式命名/教学文档单独 Review |

## Step 7D PR33 修订交付（2026-09-22）

按 `coordination/tasks/step7d_pr33_revision.md`，profile0 已纠正为 AUM3-S4 ξ=1/√2：Kp=8.725、Ki=11850、KiTs=1.185；profile1、Kaw 和当前 Simple 速度 PI 保持。修订 deadtime 速度接入门槛为 MAE/RMSE≤1.5 mm/s，旧 0.5 门槛失败记录未改写。

独立 R2026b MCP 使用已安装 Toolkit，原 R2026a 配置保留。新鲜验收目录 `docs/reports/step7d/acceptance_20260922_205317_302/`：重建 XSI、代表性电流环、live/canary、速度、正负位置、原 PI 限幅/复位、停止禁止重启、独立 fresh-start、步长收敛和规定回归全部通过；legacy 最大差异为 0。速度 worst-window RMSE：ideal 0.09264、deadtime 0.23609 mm/s；最大位置到位误差 0.02149 mm 以下。

本轮未保存 SLX，测试基于用户最新本地模型；未完成的布局改动保持未提交，详见报告的模型版本与复现限制。未完整重跑 Step6，未引入位置差分/IIR、速度 PI 重整定或新死区补偿；未验证热重启或实机停车。停在开放 PR33，不合并、不开始下一阶段、不操作硬件。

## Step 7D Task 1 初始差异与后续处理（2026-09-22）

任务书 PR #32 已合并，实施审计从 `e7f707b` 在原始工作树的 `codex/step7d-outer-loops-cosim` 分支开始。初始 SLX 中 root `iq_cmd` 的来源是 `Simple_Host/10`（`Host_Iq_A`），外环选中 `iq_ref` 则在 `Control_Task_10kHz/Reference_Manager/2` 内部，当时控制任务仅导出三个 CMP。直接切换 `FPGA_Reference_Mode=1` 不能闭合外环。

曾按任务书第 11 节报告差异，随后用户明确：Host 在三闭环下给位置参考，iq_test_ref 仅用于外环开环的电流测试。Task 1 基线提交后，Task 3 已保存最小 SLX 接线，导出现有外环选中 id/iq，同时保留原 Host 标签语义；初始化文件未修改。旧 Task 4 deadtime 速度失败保留在 `coordination/reports/step7d_codex_report.md`，初始差异证据保留在 `step7d_preflight_blocker.md`；后续修订结果见上节。下文 Step 7C 交付段保留其当时的历史状态。

## Step 7C 实现交付（2026-09-22）

分支 `step7c-dynamic-current-loop-cosim` 从任务书 PR #30 合并点 `b96a5ff617182eeab97a99e88a6e63068b79e39e` 开始。完整验收输出 `STEP7C_FULL_ACCEPTANCE_PASS`；详见 `coordination/reports/step7c_codex_report.md` 和 `docs/reports/step7c/README.md`。

- 静态 `CONTROL_BACKEND=0` 是原 legacy，根目录可运行且不初始化 XSI；`1` 是实际 FPGA/XSI 电流环。保存默认仍为 0。
- 用户批准只提取 legacy Gain/Bias；不增加 pre-deadtime saturation。两个后端共用原 `deadtime correction -> d_sum -> d_sat -> v0_eff_calc`。17 路 legacy 数值最大差异全部为 0。
- FPGA `CMP_active/2500` 直接进入 ideal-duty 边界，不经过原 PWM 半周期延迟或极性映射。保留唯一 inverter/deadtime 与自由运动 plant。
- FPGA reference 为 1 us exchange/plant、20 ns HDL clock、100 us current/PWM transaction、200 ns reset、zero prerun。四个 plant 积分器实际步长和 `Ts_ACR=100 us` 均有启动检查。
- 当前只用 scripted id=0、iq=0/+0.5/0/-0.5/0 A（边界 1/11/16/26/31 ms），Vdc=48 V、load=0；不接速度/位置环，不锁定机械运动或增加行程限制。
- ideal、1 us Simulink 平均死区、8 ms 运动中 stop 均通过；PI_PROFILE=0 未调参，未修改 RTL。停机 needs_reset=1、bridge=0、vd/vq=0。
- 1 us 对 0.5 us 最大差异 `[iq,id,v,x]` = `[0.0003142032 A,0.00000636946 A,0.00592308 mm/s,0.0000751298 mm]`；12 ms 两种步长 accepted/active 均为 120/119。
- Step 7B minimal/wrapper、6D profile0 DEMO=0、6E profile0 DEMO=0 已重新通过。
- Step 7D 需另行授权，恢复外环时复用此 current-loop 边界；当前不合并 PR、不开始 Step 7D、不操作硬件。

当前 main（Step 7C 任务书编写时）：

```text
9d70c901046efbd6364c60d6d4c0ce12bb4c5f62
```

## Step 7B 已接受实现

Step 7B merge：

```text
PR #28
merge 9572a73e09fa477d03bc56f22627b7599118de5f
```

已验证：

- `PMLSM_ThreeLoop_Simple.slx` 已进入 Git 历史，原始 as-found baseline 是 `6774035`；
- R2026b + HDL Verifier + Vivado 2026.1 的真实 Simulink HDL Cosimulation block/XSI 路径可用；
- `mc_foc_cosim_top` 导出实际 `CMP_active`、accepted/active command IDs、valid/fault 状态；
- 历史 d-current smoke 第一笔 active CMP = `1165/1335/1335`；
- `FPGA_HDL_Cosim` 在 Step 7B 中只是并联 monitor，不驱动 plant；
- 原 `Control_Task_10kHz -> Inverter_DeadTime -> PMLSM_Plant_Model` 保持；
- 50 us exchange 下，实际 active load 发生后 Simulink 可能到下一个 50 us 网格才看到命令，因此不适合作为 Step 7C plant actuation reference；
- AMD SoC Blockset support package 26.2.2 已被当前 R2026b 识别；
- Step 6D profile0/1、Step 6E profile0 和 Step 7B smoke/时序均有 accepted evidence。

Step 7B 报告：

```text
coordination/reports/step7b_codex_report.md
docs/reports/step7b/
```

## Step 7C 已批准设计

设计规格：

```text
coordination/specs/step7c_dynamic_motor_current_loop_cosim_design.md
```

PR #29 已合并：

```text
merge 9d70c901046efbd6364c60d6d4c0ce12bb4c5f62
```

核心冻结点：

1. **Plant 自由运动。**
   - 不锁 position/speed；
   - 不增加 soft/hard travel limit；
   - 电气/机械状态正常积分。

2. **本阶段只闭 FPGA 电流环。**
   ```text
   scripted id_ref/iq_ref
          ↓
   FPGA HDL current loop
          ↓
   average inverter
          ↓
   free-moving PMLSM
   ```
   速度环/位置环留给 Step 7D。

3. **静态控制后端。**
   ```text
   CONTROL_BACKEND=0 legacy Simulink
   CONTROL_BACKEND=1 FPGA HDL
   ```
   不做运行时无扰切换。

4. **只有一套 inverter/deadtime 和一套 plant。**
   Legacy 与 FPGA 只在 normalized duty 入口前分流。

5. **FPGA plant boundary：**
   ```text
   D_high = CMP_active / 2500
   ```
   FPGA 路径必须旁路：
   ```text
   PWM_Update_HalfTs
   legacy count scaling
   legacy polarity inversion
   ```

6. **Deadtime 只由 Simulink average inverter 负责。**
   Step 6E gate/deadtime 不进入 average plant。

7. **动态 FPGA feedback：**
   ```text
   ia / ib / ic
   theta_e
   omega_e
   ```
   必须来自正在运动的 plant，不得继续用 Step 7B fixed smoke。

8. **Reference timing：**
   ```text
   HDL clock                  20 ns
   PWM/current transaction    100 us
   Simulink↔HDL exchange       1 us
   plant integration           1 us
   XSI reset                 200 ns
   PreRunTime                  0
   physical time             1:1
   ```
   `Ts_ACR` 继续是 100 us。

9. **默认自由运动 current profile：**
   ```text
   0–1 ms      iq_ref =  0 A
   1–11 ms     iq_ref = +0.5 A
   11–16 ms    iq_ref =  0 A
   16–26 ms    iq_ref = -0.5 A
   26–31 ms    iq_ref =  0 A

   id_ref = 0
   vdc    = 48 V
   load   = 0 N
   ```

10. **Acceptance scenarios：**
    - ideal average inverter / no deadtime；
    - Simulink average deadtime = 1 us；
    - stop during free motion；
    - 1 us vs 0.5 us convergence。

11. **PI_PROFILE=0 保持。**
    闭环首次异常先检查 sign/phase/theta/we/delay/deadtime/timing，不能第一反应重调 PI。

## 当前唯一 Step 7C Codex 任务书

```text
coordination/tasks/step7c_dynamic_motor_current_loop_cosim.md
```

实施顺序：

```text
Task 1  抓取修改前 legacy numeric baseline
Task 2  normalized-duty boundary + static backend + legacy equivalence
Task 3  1 us HDL Cosimulation timing + direct current-test refs
Task 4  ideal inverter 自由运动 FPGA 电流闭环
Task 5  1 us average deadtime + dynamic stop
Task 6  1 us vs 0.5 us convergence
Task 7  最终回归、报告、GitHub PR
```

## Codex 启动指令

本地 Codex 执行：

```text
开始 Step 7C，严格按 executing-plans 顺序执行。

先读取：
coordination/HANDOFF.md
coordination/specs/step7c_dynamic_motor_current_loop_cosim_design.md
coordination/tasks/step7c_dynamic_motor_current_loop_cosim.md

只在：
D:/Project/FPGA_XC7A200T
工作。

先核对 Git 主工作树、origin/main 和所有本地 tracked/untracked 修改。
不要创建 worktree/额外 clone，不 stash，不 reset/clean，不覆盖或删除我的文件。

Step 7C 的目标是第一次让 FPGA HDL current loop 真正驱动自由运动的
PMLSM_ThreeLoop_Simple average inverter + motor plant。

非常重要：
1. 不锁定位置/速度，不增加行程限制。
2. 先抓取当前 legacy numeric baseline，再改 SLX。
3. CONTROL_BACKEND 必须是静态选择：
   0 = legacy Simulink，
   1 = FPGA HDL。
   legacy 模式必须能从项目根目录运行，不调用 HDL setup、不依赖 XSI runtime。
4. 只保留一套 inverter/deadtime 和一套 motor plant。
5. legacy 保留原 PWM_Update_HalfTs 和旧 count/polarity mapping。
6. FPGA backend 必须直接使用 CMP_active/2500，
   严禁再走旧 PWM delay、旧 count mapping 或旧 polarity inversion。
7. average deadtime 只由 Simulink 负责，不接 Step 6E gate deadtime。
8. FPGA live feedback 必须来自正在运动的 plant：
   ia/ib/ic/theta_e/omega_e。
9. Step 7C 直接使用 scripted id/iq current test；
   不接速度环和位置环。
10. PI_PROFILE=0，不先调 PI。

参考 timing：
HDL clock = 20 ns
current/PWM period = 100 us
Simulink-HDL communication = 1 us
plant step = 1 us
XSI reset = 200 ns
PreRunTime = 0
physical timescale = 1:1

控制周期 Ts_ACR 必须继续是 100 us，不能跟 plant step 变成 1 us。

默认自由运动 iq profile：
0-1 ms      0 A
1-11 ms    +0.5 A
11-16 ms    0 A
16-26 ms   -0.5 A
26-31 ms    0 A
id_ref=0，vdc=48 V，load=0 N。

按任务书完成：
- legacy before/after equivalence；
- static backend + normalized-duty refactor；
- 1 us HDL block timing；
- ideal inverter dynamic current loop；
- 1 us average deadtime dynamic loop；
- stop during motion；
- 1 us vs 0.5 us convergence；
- Step 7B minimal/wrapper、6D profile0、6E profile0必要回归。

如果第一次动态闭环发散，按任务书顺序检查：
duty polarity -> phase order -> theta -> we -> current signs ->
duplicate PWM delay -> duplicate deadtime -> communication timing -> PI。
不要第一反应就改 PI，也不要用换相/最终负号掩盖接口错误。

最终写：
coordination/reports/step7c_codex_report.md
docs/reports/step7c/

推送分支并创建：
Step 7C: Close dynamic FPGA current loop with free-moving PMLSM

停在开放 PR 等待 ChatGPT Review。
不要开始 Step 7D，不跑 bitstream，不操作硬件。
```

## Step 7D 边界

Step 7C 只负责运动中的 FPGA 内环。

Step 7D 才恢复：

```text
Simulink position/speed outer loops
             ↓
        id_ref / iq_ref
             ↓
      FPGA current loop
             ↓
 average inverter + free plant
```

Step 7D 应复用 Step 7C 已冻结的 backend、normalized active-duty boundary、live plant feedback 和 1 us reference timing，不重新定义 Simulink↔HDL 接口。
