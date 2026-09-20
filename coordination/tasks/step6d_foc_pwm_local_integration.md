# Step 6D — 本地主项目 FOC→PWM 整合任务与实施计划

> 给 Codex：在用户原本的主项目目录执行，可用 executing-plans 顺序完成；不创建 worktree、额外 clone 或云端实施副本。先跑通可观察的功能，再做必要验证。此文档 PR 不代表已经运行本地任务。

**日期：** 2026-09-20。
**目标：** 将 C4 的三相调制量转换成含义明确的上管逻辑占空比，接入已有三相 PWM，演示“峰值采样→FOC→比较值影子寄存器→下一 ZERO 生效”。
**架构：** 两个新增 RTL：`mc_duty_to_cmp` 和 `mc_foc_pwm_top`；复用 `mc_foc_current_core` 与 `motor_pwm_core`，不重写数学或载波模块。
**技术：** SystemVerilog、Python 标准库、Vivado/XSim 2026.1、Tcl/XDC。
**依据：** 用户已认可的 6D 方案；Step 6 总架构；已合并 C4 和 Step 6B 的真实接口。本文件合并本轮接口规格和执行计划，不再拆多份重复文档。
**基线：** PR #19 已合并，提交 `a2f4d1eb63c4cabd5e938d428e4fa436936690d2`。

## 1. 主目录、保护范围与启动条件

任务文档合并并由用户在本地 Codex 启动后执行。先记录当前目录、`git rev-parse --show-toplevel`、`git worktree list --porcelain`、远端和 `git status --short`。上一阶段确认的 MAIN 为 `D:/Project/FPGA_XC7A200T`；仍须检查本次会话实际位置、权限和远端 `kazecode666/FPGA_XC7A200T_Study`，不能只凭路径字符串宣称进入主目录。

保留所有用户 tracked/untracked 修改、硬件资料、旧 worktree，以及 `FOC_Current` 的本地仿真/实现结果。禁止强制覆盖、`reset --hard`、`clean -fd`、自动 stash、自动删除旧工程。若会话不能访问 MAIN，或同步会覆盖用户修改，报告具体问题并停止相关写入，不另建目录代替。

先 fetch 并核对最新主线；确认与用户修改无路径冲突后，在 **同一个 MAIN** 建立 `step6d-foc-pwm` 分支。已有同名分支须先核查，不用 `-C/-f` 重建。不通过分别复制 worktree 拼接源码。

C1–C4 的 RTL/TB/ROM/参考脚本/向量/旧工程/已验收报告、Step 6B PWM、Step 6A 和 Simulink 全部只读。本轮新增文件限定在第 7 节。原有 `FOC_Current/FOC_Current.xpr` 保留，新增 `FOC_PWM/FOC_PWM.xpr`；两个工程共享 MAIN 源码，不复制数学模块。

## 2. 必须显式记录的极性修订

**本节是本次合并所接受的接口澄清，优先于旧文档把 C3/C4 输出直接称作 active-high duty 的表述。它不改变 C4 数据、Step 6A golden 或 Step 6B 的比较动作。** 旧文件不回写以掩盖历史差异。

区分三个量：

- `d_foc`：C4 原始 signed S26/F24 调制量，保留现有 Sector/XYZ 相映射，不在 C4 clamp。
- `D_high`：本次定义的上管逻辑 HIGH 比例，0 对应 LOW，1 对应 HIGH；不是对真实板卡门极极性的断言。
- `CMP`：Step 6B 接受的整数比较值，HIGH 比例仍为 `CMP/TBPRD`。

采用：

```text
D_high = clamp(1 - d_foc, 0, 1)
CMP = round_nearest_ties_up(D_high * 2500)
```

不能把 `CMP = round(clamp(d_foc,0,1)*2500)` 作为本轮上管约定，也不能直接在 pwm 引脚上加 NOT：后者会破坏停机 LOW 语义。不增加运行时极性开关或交换 U/V/W 来隐藏符号问题。

依据是理想三相平均电压（U/V/W 对应 A/B/C，同一已接受命令的母线电压）：

```text
V_alpha = Vdc/3 * (2*D_u - D_v - D_w)
V_beta  = Vdc/sqrt(3) * (D_v - D_w)
```

当前 profile 0 的 d_current 用例中，C4 `v_alpha=-2.181243896484375 V`，输出 raw duty `(8960408,7816808,7816808)`。直接当上管 duty 会得到相反的 alpha 符号。按本节转换，比较值为 **(1165,1335,1335)**，PWM 重建 alpha 为 **-2.176 V**；差值来自比较值量化，不得要求与连续电压逐位相等。

先用独立 Python 和正负 alpha/beta、六扇区内部点验证相序与方向，再进入整链演示。不得修改已验收 C4 以消除这一显式适配边界。

## 3. mc_duty_to_cmp：数值转换加一笔命令保存

端口：`clk, reset_n, flush, input_valid, input_ready`；输入 `foc_duty_u/v/w` signed [25:0] F24；输出 `cmp_u/v/w_cmd` unsigned [11:0]、`cmp_cmd_valid`；输入 `cmp_cmd_ready`。本轮固定 TBPRD=2500，不扩展可变频率功能。

每相整数定义如下；Python 用大整数，RTL 必须显式扩宽：

```python
ONE = 1 << 24
high_raw = min(ONE, max(0, ONE - foc_raw))
cmp = (high_raw * 2500 + (1 << 23)) >> 24
```

`ONE-foc_raw` 至少用 S27，clamp 后用 U25 保存 0..2^24；乘积保留 U37，加舍入偏置时扩到 U38，再右移 24。检查结果 0..2500 后赋给 U12，不先把负数转 unsigned。三相同拍捕获、一起转换、一起发出。

建议并冻结一个简单调度：Q 接受输入并寄存 high_raw；Q+1 寄存乘积；Q+2 输出三相 CMP 并置 valid。不做组合 bypass；无反压时接收方最早 Q+3 握手。只有一个事务位置，计算中或输出未被接收时 input_ready=0。输出 valid=1 且 ready=0 时，三相 CMP 和 valid 保持不变；不能用仅一个时钟的脉冲丢弃待发命令。

`flush` 是同步取消，优先于接受/发出；取消内部计算及待发 valid。异步 reset_n 清空控制及可见数据。顶层停止时还须在 PWM 接口处屏蔽 valid，避免旧 valid 在 flush 同一边沿被接收。

必须有的直观数值对照：

| d_foc | D_high | CMP |
|---:|---:|---:|
| 1 | 0 | 0 |
| 0.75 | 0.25 | 625 |
| 0.5 | 0.5 | 1250 |
| 0.25 | 0.75 | 1875 |
| 0 | 1 | 2500 |

另测 F24 raw=-1 和 ONE+1，分别得到 2500 和 0，证明先有符号减法再 clamp。比较值测试与上管 HIGH 比例测试不要混淆输入方向。

## 4. mc_foc_pwm_top：单载波调度和三相命令归属

顶层参数 `PI_PROFILE=0/1`，原样传给 C4。输入为 `clk, reset_n, run_enable, sample_valid` 和 C4 原始样本字段（ia/ib/ic S24/F15；theta_e U16；we S32/F16；id_ref/iq_ref/vdc S25/F15；pi_reset/uq_zero_en 单 bit）。输出 `sample_request, sample_ready, pwm_u/v/w, needs_reset, fault_code[2:0]`。其他观察点经层次访问，不加大量调试引脚。

复用 PWM 的 50 MHz 时钟、TBPRD=2500、10 kHz 共用上下计数载波；三相不使用相移载波。定义 P 为 PWM 到达峰值、寄存 carrier_peak 拉高的边沿。

本轮仅测试台供数，约定固定一拍响应窗口：运行且无在途命令时，`sample_request` 在 carrier_peak 的高电平区间有效；TB 在这个区间的下降沿放好下一组数据和 sample_valid；N=P+1 上升沿实际握手，**同一边沿启动 C4 接受样本**，不多插一个隐藏捕获级。sample_ready 仅在该窗口且 C4 ready、适配器空闲、PWM 无 shadow_pending、顶层无在途事务时有效。其余时刻不接受新样本。请求未获得有效样本或资源不空闲要报错停机，不默默跳过控制周期。真实 ADC 的转换延迟接口另行设计，不把此一拍模拟供数当作真实 ADC 时序。

接受时占用一个 `transaction_pending` 位置，记录样本所属载波周期；直到目标 ZERO 的 compare_load_event 被确认，才释放位置。FOC 正在计算、适配器等 ready 或 PWM 影子命令等 ZERO，均不允许另一组样本占用。只有 C4 `command_valid` 才能进入适配器；`result_valid && error_code!=0` 是失败，不是正常零矢量。

正常预期时序：

| 事件 | 相对样本接受 N |
|---|---:|
| C4 发布 duty/command_valid | +512 |
| 适配器接受已发布 duty | +513 |
| 适配器置 CMP valid | +515 |
| PWM 无反压时接受三相 shadow 命令 | +516 |
| 三相 shadow→active | 峰值之后的第一个真实 ZERO |

这是需要实现/测量的调度，不是已有 6D 测量结果。C4 原有 512 拍不变；正常样本间隔仍为 5000 拍/100 us，不能将 516 拍当成新积分周期。反压仅允许延后比较值握手，不改变 C4 的采样语义。

运行中必须遵守 Step 6B：只有下一 ZERO 原子装载三相 active；同一 ZERO 边沿刚接受的命令不能旁路生效。记录实际 sample accept、CMP handshake、compare_load 三个时间。同时检查 `CMP handshake - sample accept < 2500` 且握手严格早于目标 ZERO；只通过相对 2500 拍检查还不够。

顶层可用已有 `tbctr==1 && !count_up` 在上升沿前识别即将进入 ZERO，不把已寄存的 carrier_zero 当成提前一个时钟的事件。若目标 ZERO 前未接受 CMP，锁存超时，禁止命令在该边沿或以后变成过期 shadow 命令；6D 顶层对这一失败禁止提交，不改变 standalone PWM 的原始同边沿规则。目标 ZERO 后一拍观察 compare_load_event 并核对归属，避免 NBA 误判。

PWM disabled 时原核会 ready 并允许预装载，所以**任何停止/故障路径必须门控 cmp_cmd_valid**；不能只关 pwm_enable 却仍向 disabled PWM 写旧命令。

## 5. 启停和故障：清楚但不做产品级控制器

- reset_n=0 同时清空 C4、适配器、PWM、顶层在途/故障状态，三相 LOW；释放须满足已有同步释放契约。
- 复位后允许 run_enable 先保持 0。第一次置 1 启动载波；初始 active=0，首笔正确命令到目标 ZERO 前保持 LOW，不插入未说明的 50% 预装载。
- 运行过后 run_enable 置 0：在相应采样边沿关闭 PWM，禁止新请求与所有比较值提交，flush 适配器，设置 needs_reset。再次置 1 不能绕过复位恢复旧结果。
- C4 可以完成已经在途的运算，但停止后其结果不得被使用，PI 不做回滚。恢复前用 reset_n 清空整链；run_enable 不是异步硬件 trip。
- FOC 错误、供数/接口异常或未赶上目标 ZERO：锁存 needs_reset，停止请求和命令发送；PWM 最迟在检测后的下一个 clk 上升沿转 LOW。不要用组合 NOT/AND 门直接翻转 pwm 引脚。保留原 C4 error_code 作为调试原因。

fault_code：0 无故障（用户停止可保持 0）；1 FOC error；2 deadline/load error；3 sample/handshake protocol error。首个故障保留到 reset。needs_reset 用于阻止陈旧结果重新出现，不实现自动重试或复杂诊断。

## 6. 验证内容与学习演示

### 默认演示：干净输入，约 24 个载波周期

同一参数化顶层 TB 提供 `DEMO=1`（默认 GUI）和 `DEMO=0`（自检）。演示在峰值请求时供数，接受后外部输入保持到下一组样本；不每拍毒化电流/角度/母线，不混入故障注入。

安排约 24 个周期：若干零输入/命令复位、第一笔 d_current、q 轴用例、参考电流阶跃、正常停止。独立示例之间用明确的 pi_reset 样本准备状态，连续阶跃段则不每笔清零。默认 48 V；另选一小段 12/72 V 演示时明确标注，不伪装成固定母线工况。至少一笔有效命令应用后保留完整周期，末笔也不能计算完立即停止而未观察 PWM。

这是固定输入驱动的演示，**没有电机模型反馈**。不得把 duty/PWM 的变化声称为电流跟踪性能。

### 自动检查：少量但覆盖新连接风险

1. 适配器连接真实 PWM，检查上表 0/25/50/75/100% 和有符号边界；一个背压保持用例、一个 flush 用例即可。
2. 活跃比较值恒定的一整个 ZERO→ZERO 周期统计 HIGH 时钟：严格为 `2*CMP`，总计 5000 拍。在每个时钟 NBA 后取样，包含起始 ZERO，不含下个 ZERO；三相同时检查。
3. 两套 PI 参数各回放原来的 80 行 Step 6A 原始输入，共 160 笔（可复用 C4 参考函数和数据，不拿 CSV 的中间电压替代整链）。每个 profile 从零状态按原顺序推进，一峰值一笔；逐位检查 FOC duty、适配器 CMP、shadow 与目标 ZERO 的 active，最后一笔要观察完整应用周期。不重复 C4 的 512 笔 seeded 大回归。
4. 六扇区与正负 alpha/beta 的方向检查，在适配器/PWM 测试中用 C3 oracle 生成不经 PI 的调制量即可；这只是测试台路径，不给综合顶层增加 bypass 模式。固定 Vdc=48 V，alpha/beta 选 (±1,0)、(0,±1)、(0,2)、(2,-1)、(2,1)、(-2,-1)、(-2,1)、(0,-2) V，均在线性区。
5. 比较值中途到达不能改变 active；一个同 ZERO 到达的 standalone PWM 用例证明要等再下一个 ZERO。集成正常样本必须赶上第一个目标 ZERO；加一次等待超过目标 ZERO 的定向检查，证明不会把过期结果装入下一周期。
6. 集成只做必要的停止/错误检查：运算中停止后尝试重开、不经复位不得运行；无效母线不发送新 CMP；硬件复位中止后没有 stale 命令。无需整套 mutation、逐拍复位扫描、缺文件/模拟器崩溃探针。

PWM 平均电压重建必须使用**当前 active 命令对应的** FOC 电压和 Vdc，不与下一笔尚在计算的数据比较。用实测 HIGH 数除 5000 得到 D_high，再用第 2 节公式重建。第 4 项定向线性用例每分量误差应 <= `Vdc/2500 + 0.001 V`（48 V 下 0.0202 V，覆盖比较值取整与已保留十进制系数误差）；报告最大误差。对限幅/过调制/clamp 用例，不声称能复现不可实现的原电压；这类主要验证整数适配和实际脉宽。绝不能把 direction error 当量化误差放过。

## 7. 文件范围与四步实施

新增文件：

```text
motor_control_ip/integration/rtl/mc_duty_to_cmp.sv
motor_control_ip/integration/rtl/mc_foc_pwm_top.sv
motor_control_ip/integration/tb/mc_duty_to_cmp_tb.sv
motor_control_ip/integration/tb/mc_foc_pwm_top_tb.sv
motor_control_ip/integration/tb/vectors/step6d_pwm_vectors.txt
motor_control_ip/integration/README_step6d.md
scripts/step6d_foc_pwm_reference.py
scripts/step6d_foc_pwm_build.tcl
FOC_PWM/FOC_PWM.xpr
FOC_PWM/FOC_PWM.srcs/constrs_1/new/foc_pwm_clock.xdc
FOC_PWM/wave_step6d.tcl
coordination/reports/step6d_codex_report.md
docs/reports/step6d/
```

不增加通用测试框架、动态频率/极性选项、多级 FIFO、AXI/ADC/编码器接口。必要的小型仿真辅助代码直接放入上述 TB，不重构旧模块。

### A. 先把适配公式和占空比波形做出来

- [ ] 完成 MAIN/本地改动/基线检查，在同目录分支开发。
- [ ] 写简短 Python 参考，复用 C4/C3 现有函数，提供 --generate / --check。用第 3 节七个已知输入检查适配公式，并验证 d_current 的 (1165,1335,1335)。
- [ ] 写最小适配器 TB 后实现 clamp/乘法/舍入和一笔保持，观察正向通过，再接真实 motor_pwm_core，核对实际 HIGH 比例。只处理实际失败，不先搭失败测试基础设施。

### B. 接入 C4 与载波节奏

- [ ] 实现顶层请求窗口、同边沿样本接受、输出位置预留、CMP 握手、目标 ZERO 归属，以及简单启停/故障锁定。
- [ ] 先用零输入看到三个 CMP=1250，再重现 d_current 的 CMP 和上管 PWM 宽度。原始 foc_duty 与 D_high 分组命名显示，不能标成同一个 duty。
- [ ] 使默认 DEMO=1 输入稳定，留下约 24 周期的易读波形，再完成 DEMO=0 两套参数和第 6 节少量关键检查。

### C. 本地工程和最终验收

- [ ] 在 MAIN 新建 FOC_PWM.xpr，外部引用 MAIN 的 C4 依赖与 PWM，不读旧 worktree。默认综合 PI_PROFILE=0、默认仿真 PI_PROFILE=0/DEMO=1；默认仿真先停 0 ns 供加载波形。
- [ ] 器件 xc7a200tfbg484-2；唯一约束 `create_clock -name sys_clk -period 20.000 [get_ports clk]`。不约束引脚/IOSTANDARD，不生成 bitstream。
- [ ] 默认 profile 0 在此项目 synth_1/impl_1 真正完成综合/route并保留 .runs 结果。WNS/WHS>=0、TNS/THS=0、路由完整/零错误，无 latch/blackbox/no_clock/内部未约束端点/组合环；记录 LUT/FF/DSP/BRAM，不设猜测资源上限。profile 1 仅做仿真也可，明确不声称其 route 已验收。
- [ ] 最终 build 跑 6D 参考 --check、适配器+PWM TB、两套 DEMO=0 集成 TB；原 C4 两套功能回归、原 PWM TB 各一次。不重跑全部历史单元测试或旧项目 route。
- [ ] 只检查进程退出码、明确 PASS、无 Fatal/Error、必要计数。最后一次相关源码/脚本修改后执行完整 build；复用 NEEDS_REFRESH=0 的同源检查点时如实记录，不将旧报告冒充新实现。
- [ ] 实际从 MAIN 打开 FOC_PWM.xpr，运行默认学习演示和 wave_step6d.tcl；最终保留默认 profile 0/DEMO=1，不把 GUI 留在故障注入或 profile 1 模式。

命令入口由脚本提供并在 README 中写清：

```text
python scripts/step6d_foc_pwm_reference.py --generate
python scripts/step6d_foc_pwm_reference.py --check
vivado -mode batch -source scripts/step6d_foc_pwm_build.tcl
```

--generate 仅用于有意生成新 6D 向量，最终验收只 --check，不能悄悄改期望数据。向量有明确表头和准确计数，解析出错直接失败，不建设复杂 parser 框架。

标记：`ALL STEP 6D DUTY TO CMP TESTS PASSED`；`ALL STEP 6D FOC PWM TESTS PASSED profile=0/1`；`STEP6D_DEMO_PASS`；最终 `STEP6D_BUILD_PASS`。

### D. 留下可学习的本地成果并提交 PR

- [ ] 波形按“captured 输入→FOC 调制量→上管 duty/CMP→shadow/active→载波/PWM”分组。显示 sample_request/accept、FOC valid、CMP valid/ready、shadow_pending、carrier_zero/peak、compare_load_event 和样本编号。现有 PWM 观察端口直接复用。
- [ ] 可以在 TB 添加 real 单位别名，把电流/电压 F15 除 32768、FOC/PWM duty F24 除 16777216；载波/CMP/标志保留整数/逻辑。不得把 real 运算写入可综合 RTL。theta 是 U16 二进制角度，不按 signed F15；避免再次把 F24 duty 显示成 F25 的一半。
- [ ] 中文 README 说明打开 XPR、加载 wave_step6d.tcl、先看 2–3 周期再放大 ZERO/比较边沿。清楚区分计算完成、命令被接收、命令生效，以及 GPIO 逻辑与实际门极极性。
- [ ] 报告记录真实 MAIN/XPR/分支/测试提交/工具版本、极性方向与电压重建、HIGH 计数、两个 profile 计数、实际 516 拍链路及目标 ZERO、默认 route、所有警告与未执行项目。既有 RAM 异步控制等非板级警告仍须披露，STA 通过不等于异步器件行为或板级安全已证明。
- [ ] git diff --check 并核对每个暂存路径，只提交新源码/项目配置/必要文本证据；.sim/.runs/cache/WDB/DCP 保留本地，不整体提交也不自动删除。保留 FOC_Current 及用户原有修改。
- [ ] 打开实现 PR **Step 6D: Integrate FOC duty adapter and motor PWM**，返回真实 FOC_PWM.xpr 绝对路径和默认演示打开步骤，停止等待 ChatGPT Review。不自动合并，不开始下一阶段。

## 8. 完成边界

完成意味着：一笔固定输入样本的 FOC 调制量，经明确极性适配成为三相比较值，在指定 ZERO 同拍生效，并产生正确计数、宽度和平均电压方向的三路逻辑 PWM；工程与运行结果真实保留在 MAIN。

没有电机模型闭环、真实 ADC/编码器、六路互补门极、死区、过流 trip、驱动器极性确认、引脚约束、bitstream 或硬件操作。本轮 PWM 不能直接作为可上电的功率级控制器。
