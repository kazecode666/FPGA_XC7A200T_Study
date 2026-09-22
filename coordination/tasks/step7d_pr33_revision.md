# PR #33 / Step 7D 修订说明：AUM3-S4 电流 PI 与接入阶段验收

日期：2026-09-22  
适用分支：`codex/step7d-outer-loops-cosim`  
适用 PR：#33

本文件修订 `coordination/tasks/step7d_outer_loops_cosim.md` 在 PR #33 当前实施中的若干冻结条件。其余未冲突要求继续有效。

## 1. 修订目的

Step 7D 当前目标是验证“Simulink 外环 -> FPGA HDL 电流环 -> average inverter/deadtime -> free-moving PMLSM”能够正确形成完整闭环。它不是低速死区性能优化或最终控制器整定阶段。

PR #33 已证明 live reference / live feedback / CMP_active/2500 / 事务时序等主接口能够工作，但当前 `PI_PROFILE=0` 的电流 PI 系数与本项目 AUM3-S4 学习模型的理论整定参数不一致。该参数错误允许在 Step 7D 中修正，不再受原任务书“PI_PROFILE=0 冻结”的限制。

原则：

- baseline 用于保存修改前事实，不代表发现参数错误后禁止修正；
- 不通过盲目扫参、移动统计窗口、滤波输出或修改 plant 来制造 PASS；
- 有明确电机参数、公式和离散定义依据的参数错误可以修正；
- 修正后使用 Step 7 动态联合仿真验证，不要求重新执行完整 Step 6 历史验收。

## 2. AUM3-S4 电流 PI profile 定义

本项目 AUM3-S4 参数：

```text
Rs = 2.37 ohm
Ld = Lq = 1.745 mH
Ts_ACR = 100 us
```

并联 PI：

```text
u = Kp * e + x
x[k+1] = x[k] + Ki * Ts * e + anti-windup
```

采用学习笔记中的零极点对消/阻尼设计：

```text
Kp = L / (4 * xi^2 * Ts)
Ki = Kp * Rs / L
```

从本修订起：

| PI_PROFILE | 含义 | xi | Kp | Ki (1/s) | Ki*Ts |
|---|---|---:|---:|---:|---:|
| 0 | AUM3-S4 Step 7 主用快速基准 | 1/sqrt(2) ≈ 0.7071 | 8.725 | 11850 | 1.185 |
| 1 | AUM3-S4 保守基准 | 1 | 4.3625 | 5925 | 0.5925 |

S32/F24 最近舍入目标：

```text
profile 0:
  KP_F24    = 146381210   -> 8.725000023841858
  KI_TS_F24 = 19881001    -> 1.185000002384186

profile 1:
  KP_F24    = 73190605    -> 4.362500011920929
  KI_TS_F24 = 9940500     -> 0.5924999713897705
```

当前旧 profile 0 的 `Kp=2.18125, Ki=2962.5` 不再作为本项目 AUM3-S4 Step 7 主参数。不要推断或宣称它具体属于哪一台电机；只记录它与当前 AUM3-S4 理论整定和 Simple 模型不一致。

### 2.1 本次允许修改

允许修改 profile 0 的 Kp/KiTs 及其直接依赖的当前源码/参考常数/测试期望，使仓库当前定义自洽。

建议把新代码和新报告中的 profile 描述改成明确的 AUM3-S4 / xi 名称，避免继续把 profile 0/1 描述为模糊的 “real commissioning / MIL override”。历史已接受 Step 6 报告保留原文，不回写历史。

### 2.2 本次不顺带修改

`KAW_D/KAW_Q` 本次先保持现值。若后续发现其离散定义、饱和差值符号或 Simulink/RTL 语义存在明确不一致，再单独审计和修订；不要为了本次 speed gate 一并调参。

## 3. 速度 PI：以 Simple 模型实际结构为准

当前 Step 7D 的 `PMLSM_ThreeLoop_Simple` 不包含学习笔记中 DSP 实现所讨论的“N 点位置差分测速 + IIR 低通”反馈链，因此本阶段不把该链路对应的 4.6 ms 等效延迟模型带入 Simple 模型速度 PI。

本次：

- 保持 Simple 模型现有速度 PI 参数、限幅和抗饱和结构；
- 不改成学习笔记中基于位置差分 + IIR 的 h=5 参数；
- 不新增位置差分或 IIR 仅为了匹配笔记；
- 后续如果真实 DSP/SoC 实现加入该测速链，再在相应阶段重新采用包含该延迟的速度环设计。

因此，本次只修正 FPGA 电流内环参数来源，不把速度 PI 改动混入同一修订。

## 4. deadtime 速度性能门槛改为“接入阶段”门槛

原任务书对 ideal 与 1 us average-deadtime 都使用 0.5 mm/s MAE/RMSE，过于偏向低速性能优化。Step 7D 的主要目的为接入正确性。

修改为：

| 指标 | ideal | 1 us average deadtime |
|---|---:|---:|
| 每个固定速度窗口 MAE | <= 0.5 mm/s | <= 1.5 mm/s |
| 每个固定速度窗口 RMSE | <= 0.5 mm/s | <= 1.5 mm/s |
| 每个固定速度窗口 max abs error | <= 2.0 mm/s | <= 2.0 mm/s |

其他结构/协议硬门槛不放宽：

- live reference / live feedback 来源必须正确；
- fault=0；
- range flags=0；
- 正常运行 needs_reset=0；
- accepted/active command 对应关系正确；
- CMP_active/2500 边界正确；
- 正负运动方向正确；
- 无 NaN/Inf、无发散；
- 电流峰值和现有 deadtime 电流门槛继续检查。

原 PR #33 中 `speed_deadtime` 在旧 0.5 mm/s 门槛下的失败记录必须保留，不删除、不改写。报告中注明：旧门槛失败是真实历史结果；本修订根据项目“接入验证”目标改变后续 acceptance 口径。

在修改 profile 0 后必须重新运行同一 speed 场景，不能直接拿旧结果套用 1.5 mm/s 门槛宣称通过。

## 5. 调度检查保持轻量

不建设复杂 Simulink 完整性测试框架。

对 current/speed/position 三条实际执行事件，只增加一个统一的完整网格检查：

```matlab
expected = (firstTime:period:cfg.stopTime).';
actual = actual(:);
assert(numel(actual) == numel(expected));
assert(all(abs(actual - expected) < tolerance));
```

其中 `firstTime` 使用已经从实际模型审计/实测得到的相位，不凭变量名猜测。

只增加一个最小负例：删除最后一个事件后必须被拒绝。无需为“截断前缀/缺尾/错误相位”等分别建立大套件；一次完整 expected-grid 比较已经覆盖这些情况。

保留现有命令 ID/accepted-active 检查，不再继续扩展与本阶段目标无关的 Simulink 测试基础设施。

## 6. MATLAB R2026a / R2026b MCP

用户当前同时保留 MATLAB R2026a 和 R2026b，现有 Codex MCP 指向 R2026a。Step 7B/7C/7D 使用 R2026b。

后续本项目需要独立的 R2026b MCP 服务：

- 不删除或替换现有 R2026a MCP；
- 不全局升级 MATLAB/Toolkit；
- 不修改用户全局 PATH；
- 为本项目建立明确绑定 R2026b 的 MCP 服务/项目配置；
- R2026b 会话内初始化已安装的 Simulink Agentic Toolkit；
- 开始模型读写前确认：
  ```matlab
  version('-release')
  matlabroot
  which model_read -all
  which model_edit -all
  which model_check -all
  ```
- 必须看到 R2026b 与对应 Toolkit 函数后再继续。

若 Codex 当前无法安全建立 R2026b MCP，先报告实际配置和阻塞，不要让 R2026a MCP 修改 R2026b Step 7 模型。

## 7. 修改与验证范围

### 7.1 不重跑完整 Step 6

本次不重新执行 Step 6C2/C4/6D/6E 的整套仿真、综合、route、timing 或历史 acceptance。

允许同步修改 profile 0 直接依赖的当前常数、参考生成器、literal/self-check 和必要 fixture，使未来运行这些测试时不会仍期待旧 profile 0。不要重写历史 Step 6 报告或伪造新的 Step 6 PASS。

对 profile 常数至少做轻量检查：

- F24 raw 解码为目标 Kp/KiTs；
- 相关 RTL 能被当前 Step 7 XSI runtime 编译；
- 不出现新的编译/elaboration 错误。

### 7.2 功能验证直接回到 Step 7

修改 profile 0 后按以下顺序：

1. 重新生成 Step 7 当前 FOC XSI runtime。
2. 先运行 Step 7C 的代表性动态 current-loop 场景（至少 ideal + deadtime），确认：
   - 正负 q 电流方向正确；
   - iq 能跟随参考；
   - id 无异常；
   - fault/range flags 为 0；
   - 无发散或接口异常。
3. 重跑 Step 7D：
   - `speed_ideal`
   - `speed_deadtime`
4. 如果结构/协议硬门槛通过，且新的接入阶段性能门槛满足，继续 Task 5–8 的位置、负向位置、关闭输出/重新初始化、收敛和最终 Step 7D acceptance。
5. 不因本次 profile 改动回头重跑完整 Step 6。

若改成正确 AUM3-S4 profile 后出现明显发散、fault/range、方向错误或电流异常，先按接口/参数/定点实现诊断，不自动改速度 PI 或死区模型。

## 8. PR #33 报告要求

PR #33 后续更新应明确区分：

1. **旧事实**：旧 profile 0 + 旧 0.5 mm/s gate 的 Task 4 blocker；
2. **修订决定**：AUM3-S4 profile 0 参数纠正 + deadtime 接入门槛调整；
3. **新运行结果**：修改后重新执行的 Step 7C/7D 结果；
4. **未做事项**：没有完整重跑 Step 6，没有引入位置差分/IIR，没有重新整定速度 PI，没有自动加入死区补偿。

最终仍停在开放 PR 等待 Review，不自动合并，不操作硬件，不开始后续硬件阶段。
