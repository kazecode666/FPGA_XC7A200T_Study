# Step 6C4 — 本地主项目整合任务与实施计划

> 给 Codex：在用户本地主项目的同一个工作目录中执行本计划，可使用 executing-plans；不得再创建 linked worktree、额外 clone 或云端实施副本。先跑通主链，再做必要验证。

**目标：** 把已验收的 C1/C2/C3 连接成 `mc_foc_current_core`，在用户主目录留下可直接打开、仿真和查看实现结果的 `FOC_Current/FOC_Current.xpr`。
**架构：** 一个新增 RTL 顶层，复用电流变换、PI/限幅、逆 Park、SVPWM 四个已有模块；单事务，N+512 响应。
**技术：** SystemVerilog、Python 标准库、Vivado/XSim 2026.1、Tcl/XDC。
**依据：** 用户已确认的 C4 方案；`coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`；已合并的 C1/C2/C3 规格及实现。本文件同时给出 C4 接口契约和实施顺序，不再拆成重复的规格/计划文档。
**基线：** PR #17 已合并，`4eb050bd62f6ac7c80ecf3f0a4a017d62f07d1ef`。文档提交不是 C4 实现或验证完成证据。

## 1. 本次最高优先级：工作地点和本地成果

用户要求在原本的本地项目目录整合，而不是把成果继续留在 `.codex/worktrees/...`。本节覆盖之前任务/技能中默认使用 worktree 的建议。

开始时记录当前目录、`git rev-parse --show-toplevel`、`git worktree list --porcelain`、`git remote -v` 和 `git status --short`。用 Git 工作树登记和原项目内容定位真正的主目录，记作 `MAIN`；它是实施时读取到的绝对路径，不是预先猜测的盘符或文件夹名。核对远端是 `kazecode666/FPGA_XC7A200T_Study`。

- 当前若在旧 linked worktree，先转到可访问的 `MAIN`，所有写入和 Vivado 操作均以该目录为根。
- 若当前 Codex 会话只能访问 worktree，报告权限限制并停止写入；不得用另一个 worktree 代替，也不得把复制文件说成已完成本地整合。
- 旧 worktree 保留，不移动、不删除；不要直接拷贝它们的整个 `.runs/.cache/.Xil`。
- 先 fetch 已合并的 Git 基线，再更新主目录的文件。不要分别复制 C1/C2/C3，制造多个源码副本。
- 保留用户已修改/未跟踪文件。禁止 `reset --hard`、`clean -fd`、强制切分支、默认覆盖、自动 stash 或把用户修改打包提交。存在阻塞同步的修改时，列出冲突路径，停止相关写入。

工作目录干净、目标分支尚不存在时，可以在 **MAIN 内**使用：

```text
git fetch origin
git switch --no-track -c step6c4-foc-current origin/main
git merge-base --is-ancestor 4eb050bd62f6ac7c80ecf3f0a4a017d62f07d1ef HEAD
```

执行前确认本任务文档已经在接受的主线中。若已有该分支，先检查其提交和占用目录，不用 `-C/-f` 重建。新建分支不等于新建工作目录。结束时保留主目录在 C4 分支，不切回导致新文件消失的旧分支。

**本地完成条件：** MAIN 中存在 C1/C2/C3 源码、ROM、参考文件和 C4 新源码；`FOC_Current.xpr` 的设计源码都来自 MAIN；默认配置的实际仿真及 synth/impl 结果保留在该本地项目下；不能只有远端 PR 或 worktree 中的工程。

## 2. 只连接，不重写数学模块

```text
mc_current_transform -> mc_pi_dq_core -> mc_inv_park -> mc_sector_svpwm
        C1                   C2            C1              C3
```

顶层名字 `mc_foc_current_core`，参数 `PI_PROFILE=0`，仅支持 0/1，并原样传入 C2。

| 方向 | 信号 | 格式/行为 |
|---|---|---|
| 输入 | clk, reset_n, enable | 50 MHz；异步复位断言，系统负责同步释放 |
| 输入/输出 | sample_valid / sample_ready | 仅握手边沿接受一笔完整样本 |
| 输入 | ia, ib, ic | signed [23:0]，F15 |
| 输入 | theta_e | [15:0]，沿用 C1 二进制电角度 |
| 输入 | we | signed [31:0]，F16 |
| 输入 | id_ref, iq_ref, vdc | signed [24:0]，F15 |
| 输入 | pi_reset, uq_zero_en | 与接受样本一起捕获 |
| 输出 | duty_u, duty_v, duty_w | signed [25:0]，F24，不 clamp |
| 输出 | result_valid | 成功/错误均产生单拍完成脉冲 |
| 输出 | error_code | 00 OK；01 INVALID_VDC；10 RANGE_ERROR；11 INTERNAL_ERROR |
| 输出 | command_valid | `result_valid && error_code==0`，不是 PWM 的 ready/valid 接口 |

无 output_ready。外部数据保持到下一次结果或硬件复位。`sample_ready = reset_n && enable && !busy && !needs_reset`。

`enable=0` 只阻止新接受，保留 PI 状态；已经接受的事务仍完成，包括有效命令。它不是急停、功率级使能或中途取消。没有接受就没有新的积分更新。不要把 enable 每次关闭当作复位。

接受后必须保存全部输入。收到 C1 电流变换结果时，同时保存 id/iq、i_alpha/i_beta 和 sin_theta_dbg/cos_theta_dbg；逆 Park 使用这对相同的 sin/cos，不增加第二个 LUT。C2 与 C3 使用同一份 captured vdc。C1 输入/输出之间不增加新缩放；C1 固有的舍入/饱和行为照常保留，不伪造它没有提供的错误标志。

## 3. 时序与状态契约

顶层在 N 接受，在 **N+512** 发布结果，即 10.24 us。最早下一笔在 N+513 接受。所有提前完成/出错结果在内部等待固定输出时刻。控制采样周期仍为 100 us，不能将 512 拍当作新 PI 采样周期。

以下正常路径表明确区分子模块输出更新和父模块采样，避免 NBA 同边沿误用：

| 阶段 | 子模块接受 | 子模块输出更新 | C4 保存结果 |
|---|---:|---:|---:|
| 电流变换 | N+1 | N+6 | N+7 |
| PI/限幅 | N+8 | N+264 | N+265 |
| 逆 Park | N+266 | N+268 | N+269 |
| SVPWM | N+270 | N+398 | N+399 |
| 顶层发布 | — | N+512 | 外部读取 |

用简单状态机/年龄计数器实现。启动脉冲在目标边沿之前已经有效；不要在同一 always_ff 刚写 input_valid 后就把该边沿当作子模块已接受。C2/C3 检查 ready，C1/逆 Park 只发单拍 valid。按表检查阶段完成，异常不继续启动下游。

**PI 状态只由 C2 管理。** 正常路径在 C2 的 N+264 成功边沿更新，不延迟到 C4 的 N+512，不在每笔样本启动时复位，也不复制一套积分器。C2 出错时维持旧状态；C2 成功后若下游失败，已更新的 PI 状态不回滚。测试和报告必须反映这一实际行为。

错误策略：

| 情况 | 处理 |
|---|---|
| 接受时 vdc<=0 | 不启动子模块，N+512 返回 01，PI 状态不变 |
| C2 返回 01/10 | 不启动逆 Park/C3，N+512 透传错误，允许之后正常请求 |
| C3 返回 01/10 | 不产生 command_valid；C2 已成功的状态不回滚 |
| ready/阶段完成时序异常或子核返回 11 | 返回 11；一个 needs_reset 标志锁住后续接受，直到 reset_n；不自动重试 |
| reset_n=0 | 同时复位顶层和全部子核，清空 PI 状态、中止在途计算、可见数据和 valid 清零 |

所有错误响应的 duty 和 command_valid 为零。禁止把 C2 的错误零电压继续算成正常 0.5 duty。内部故障的 needs_reset 仅是防止陈旧子核结果污染下一笔的恢复约定，不实现复杂诊断/重试系统。

调试点通过层次访问即可：captured 输入、每级 valid/结果、C2 OLD/NEXT 状态、sector、error_stage、age。不要为调试增加大量顶层引脚或 KEEP。只在相应阶段完成/顶层结果时检查有效字段。

## 4. 文件范围

新建：

```text
motor_control_ip/foc/rtl/mc_foc_current_core.sv
motor_control_ip/foc/tb/mc_foc_current_core_tb.sv
motor_control_ip/foc/tb/vectors/step6c4/foc_vectors.txt
motor_control_ip/foc/tb/vectors/step6c4/manifest.json
scripts/step6c4_foc_reference.py
scripts/step6c4_foc_reference_test.py
scripts/step6c4_foc_build.tcl
motor_control_ip/foc/README_step6c4.md
FOC_Current/FOC_Current.xpr
FOC_Current/FOC_Current.srcs/constrs_1/new/foc_current_clock.xdc
FOC_Current/wave_step6c4.tcl
coordination/reports/step6c4_foc_fixed_vectors.csv
coordination/reports/step6c4_codex_report.md
docs/reports/step6c4/
```

除本任务新增文件外，C1/C2/C3/PWM、Simulink、Step 6A golden/verifier、旧项目及已验收报告全部只读。同步这些已合并文件进入 MAIN 不等于授权修改其内容。不扩大范围修复旧项目或清理旧 worktree。

## 5. 实施步骤（同一 Codex 本地任务内完成）

### A. 同步主目录，先跑通零输入

- [ ] 完成第 1 节目录确认和非破坏性同步，记录 MAIN、起始分支/提交、用户原有修改。检查四个子模块及依赖、ROM、三个 Python 参考在 MAIN 中真实存在。
- [ ] 建立 FOC_Current 项目，使用外部引用的 MAIN 源码；ROM/向量仿真路径也来自 MAIN。
- [ ] 先写最小顶层 TB：初始化后零电流、零参考、we=0、vdc=48 V，接受一次，预期 N+512 返回三个 `26'sd8388608`，error=0、command_valid=1。
- [ ] 再连接四个子模块、captured 输入和阶段调度；运行 TB，保存一段能看到全链 valid 和数值流动的波形。失败测试只用于调试，不先搭复杂测试平台。

### B. 整链参考、连续控制和必要边界

- [ ] Python 复用已验收脚本的函数：C1 的 clarke_raw/sincos_raw/park_raw/inv_park_raw；C2 的 sample/pi_step；C3 的 svpwm_step。读取已验收 ROM，不编辑/重新生成它。定义 `foc_step(state, sample, profile, rom)`，返回整链中间量、结果和 next_state。
- [ ] 函数顺序必须是“原始电流 -> C1 -> C2 -> 逆 Park -> C3”；无效 vdc 不调用 C2；C2 成功后 next_state 已更新，后续错误不能退回旧 state。使用已有函数不等于从 RTL 读取预期输出。
- [ ] 读取实际 Step 6A 160 行，每个 profile 从零状态开始，分别连续回放 80 行。只量化原始 ia/ib/ic/theta_e/we/id_ref/iq_ref/vdc/控制命令；不得拿 CSV 的 id/iq、ud_lim/uq_lim 或 v_alpha/v_beta 替代整链计算。
- [ ] 电流及 theta 量化沿用 C1 规则，we/参考/vdc 沿用 C2 规则；入口先检查范围，不靠意外夹紧掩盖越界样本。PI 的所有历史状态由上一行 next_state 递推。
- [ ] 每个 profile 再生成 256 笔确定性、连续、有状态向量（固定种子 0x6C42026 加 profile）；电流在 +/-5 A、参考在 +/-30 A、电角速度在 +/-100 rad/s，vdc 取 12/48/72 V，包含阶跃、饱和保持/恢复、多个角度及命令复位。两套参数合计 672 行基础数值回放，少量协议用例另计。正常流发现意外错误应报告，不能筛掉失败向量再称全通过。
- [ ] 对全部历史和 seeded 行，RTL 与组合整数模型逐位比较每级关键输出、最终 duty、error 及 C2 OLD/NEXT 状态。每笔只接受/启动一次，正常流每 5000 clocks 送样本；另用一个短序列验证最早 N+513 接受和空闲不积分。
- [ ] 必要协议测试：busy 时扰动整组输入；enable=0 不接受且状态保持；处理中关闭 enable 仍完成；pi_reset/q_zero；vdc=0/-1；分别在 C2 运算中和 C3 运算中硬件复位；一次丢失阶段 valid 的内部超时检查。无需每拍复位扫描、成套 mutation 或文件失败探针。

**整链浮点对比：** 同时输出原 Step 6A 电流/电压、归一化 duty（原计数除 10000）和 C4 整链值、误差最大值及最差行，逐项列出 sector/sat 差异。C3 的 5e-5 容差和四行 sector 白名单只适用于其独立输入比较，不外推到 C4。第一版 C4 的硬数值门槛是与已验收子算法组成的整数参考逐位一致；浮点历史差异作为整链误差报告，不凭空设置新容差，也不宣称已满足未定义的浮点指标。明显比例、极性或未解释的不连续问题仍须报告给 Review。

### C. 在主目录保留可用 Vivado 工程

- [ ] `FOC_Current/FOC_Current.xpr` 默认综合 profile 0、默认 TB profile 0；同一参数化 TB 分别仿真 0/1。实现直接在该项目的 synth_1/impl_1 运行，保留本地 `.runs` 结果，不只在临时项目跑完留下空 XPR。
- [ ] 目标 `xc7a200tfbg484-2`，唯一板级前约束：`create_clock -name sys_clk -period 20.000 [get_ports clk]`。不设引脚/IOSTANDARD，不生成 bitstream。
- [ ] 默认 profile 0 完成综合、布局布线，检查 WNS/WHS>=0、TNS/THS=0、全部可路由网络完成且无路由错误，无 latch/blackbox/未时钟化内部端点/组合环。记录 LUT/FF/DSP/BRAM 和警告，不设猜测资源上限。没有运行 profile 1 整核 route 就不得声明该配置已完成时序验收。
- [ ] C1/C2/C3 原有 `--check` 和 Step 6A verifier 各运行一次；加已有 PWM TB 一次。C4 两套参数整链仿真已覆盖连接后的子模块，不重新运行所有历史单元测试或其 route。
- [ ] build 脚本只需过程退出码、准确成功标记、无 Fatal/Error 和必要计数检查；最后一次 RTL/TB/脚本修改后完整再运行。最终标记 `STEP6C4_BUILD_PASS`。
- [ ] 从 MAIN 实际打开 FOC_Current.xpr，启动默认行为仿真并加载 wave_step6c4.tcl。检查设计源码/ROM/向量实际解析位置，没有旧 worktree 路径或旧目录备用读取；无需建立额外 relocation 测试框架。

建议由 build 串起这些命令，不让用户逐项手动运行：

```text
python scripts/step6c4_foc_reference_test.py
python scripts/step6c4_foc_reference.py --generate
python scripts/step6c4_foc_reference.py --check
vivado -mode batch -source scripts/step6c4_foc_build.tcl
```

最终 build 只执行 --check，不在验收中悄悄重写预期向量。共享 Python 脚本直接导入，别复制成多份。

### D. 留下本地成果，再提交实现 PR

- [ ] 执行 git diff --check，按路径审查暂存内容；只提交 C4 源码/项目配置/测试/必要文本报告，Vivado cache、.runs 等生成物保留本地而不整体提交。不要删除用户生成物来达到干净状态。
- [ ] README 用中文说明主链、如何打开项目/仿真/查看波形，如何选择两套 PI 参数，10.24 us 计算延迟与 100 us 控制周期的区别。
- [ ] 执行报告写真实 MAIN、XPR 绝对路径、当前分支、测试提交、工具版本、672 基础行和额外协议用例计数、整链误差、default-profile route、未执行项目。报告应明确这里没有接电机对象、ADC、PWM 或硬件。
- [ ] 打开 `Step 6C4: Integrate PI-FOC in the main local project` 实现 PR 后停止，不自动合并，不开始 Step 6D。
- [ ] 最后向用户返回本地 XPR 绝对路径及默认仿真打开步骤。MAIN 中的文件和工程结果必须仍然存在；仅给 worktree 路径/远端 PR 不算完成。

## 6. 最小审查重点

同一笔角度/母线不能错配；PI 不重复积分也不每笔清零；q_zero 不等于固定 v_beta=0；错误不能变正常 0.5 duty；源码和实际运行位置必须是用户 MAIN。上述五项分别由阶段快照、状态序列、非零角度命令用例、错误用例及路径报告证明。

本任务不连接 duty_to_cmp/PWM、ADC/编码器、AXI/MPSoC、互补门极/死区/保护，不运行电机。文档和执行计划可一次交接，保持学习项目的体量。
