# Step 6D：FOC duty adapter 与三相 PWM 本地整合

## 本地目录与保护边界

在用户原始 MAIN `D:/Project/FPGA_XC7A200T` 实施，Git 主工作树 gitdir/common-dir 均为 `.git`；远端为 `https://github.com/kazecode666/FPGA_XC7A200T_Study.git`。从最新 main `44e8a8ec98bc011f7b459def146e75ffe1ad75eb` 创建同目录 `step6d-foc-pwm`，确认 C4 合并提交 `a2f4d1eb63c4cabd5e938d428e4fa436936690d2` 为祖先。上游本轮仅两份交接文档，与用户修改无重叠。

新工程真实路径：`D:/Project/FPGA_XC7A200T/FOC_PWM/FOC_PWM.xpr`。源码、ROM、向量全部来自 MAIN；既有 `FOC_Current/FOC_Current.xpr` 与旧 worktree 保留。原 16 个 tracked 路径的 binary diff 未变；75 个原有 untracked 文件仍存在且大小未变，见 `docs/reports/step6d/local_preservation.txt`。没有自动 stash、强制 checkout、reset/clean、目录覆盖或文件哈希验收。用户移动的硬件资料及旧 XPR 修改均未提交。

## 实现与实际时序

只新增 `mc_duty_to_cmp`、`mc_foc_pwm_top`、测试/参考与本轮工程文件。C1–C4、PWM、Simulink、golden、ROM 和旧报告只读。

极性由 `D_high = clamp(1 - d_foc, 0, 1)` 显式适配；不 NOT 引脚、不交换 U/V/W。S27 做差，U25 clamp，U37 乘 2500，U38 加 2^23 后右移 24，以非负半入舍入得到 U12 CMP。适配器一笔容量，Q 捕获，Q+1 乘法，Q+2 valid，最早 Q+3 接收；背压保持整组三相命令，flush 优先取消。

共享 50 MHz 载波 TBPRD=2500，周期 5000 拍/100 us。峰值 P 请求，N=P+1 同拍顶层/C4 接受；实测 N+512 C4 完成、N+513 适配器接收、N+515 CMP valid、N+516 PWM 写 shadow，N+2499 目标 ZERO 三相原子装载，下一拍确认 load 后释放预留位置。严格禁止在目标 ZERO 当拍或更晚提交本笔命令。

run_enable 停止在对应 clk 上升沿关闭 PWM，运行过后必须 reset 才能恢复。FOC 错误、超时/load、供数/握手异常分别锁存 fault_code=1/2/3；用户停止可为 0。运行中的每个峰值检查资源/供数，即使 request 被 pending 屏蔽也不漏检。所有提交在 PWM 端口之前门控，防止复用 PWM 的 disabled preload 机制接收陈旧结果。停止后 C4 可以结束已有运算，但结果丢弃，不回滚 PI。

## 仿真与参考

参考由已验收 C4/C3 Python 函数推进真实原始输入，最终 build 仅 --check。197 行新向量：两套原始历史各 80 笔及各 1 笔 tail、10 笔线性方向、24 笔稳定演示及 1 笔 tail。未把 seeded 回归或尾样本混入 160 基础数。

| 检查 | 结果 |
|---|---|
| 适配器连接真实 PWM | 18 完整周期；7 个已知/有符号边界、半入舍入、背压 1、flush 1、同 ZERO 1、方向 10，通过 |
| 方向/六扇区 | 实测 HIGH 重建，各分量最大误差 0.008746390328 V，低于 48 V 下 0.0202 V 门槛 |
| 集成 profile 0 / 1 | 各 base=80、tail=1、accepts=81、loads=81、full_cycles=80，通过 |
| 必要协议检查 | 每 profile 6 项：运算中停止/重开、无效母线、reset abort、目标 ZERO 超时、缺样本、峰值资源占用，通过 |
| 默认 DEMO=1 | 24 笔 + 1 tail，24 个完整应用周期，输入组间稳定，通过 |
| 原 C4 回归 | 每 profile base=336、accepted=349、responses=347、aborted=2、latency=512、poisoned=175616，通过 |
| 原 PWM 回归 | 原始自检 TB，通过 |

完整周期 NBA 后计数，包含起始 ZERO、不含下个 ZERO；每相 HIGH 精确等于 2×当前 active CMP，且非 ZERO active 不变。profile 0 d_current 为 CMP=(1165,1335,1335)，HIGH=(2330,2670,2670)，FOC alpha=-2.181243896484 V、实测 PWM alpha=-2.176 V，方向一致。

整链平均电压使用当前 active 的样本编号、Vdc 与 FOC 电压；profile 0 最大 alpha/beta 差为 0.011079052734/0.010152028523 V，profile 1 为 0.010487792969/0.009658628944 V。这些是包含 clamp 工况的观察值，不据此声称过调制输入可线性复现。线性方向验收单独使用上述 10 点。

最小 Python/adapter/top 在实现前观察到缺模块失败，随后通过。完整脚本前两次尝试因 Windows xelab.bat 的 generic 参数转义失败，没有算作验收通过；现改用当前 Vivado 安装的 `bin/unwrapped/win64.o/xelab.exe` 保留参数边界。没有为此修改旧 RTL 或测试。

## 综合、布局布线和本地演示

最终完整验收为 `docs/reports/step6d/final03/`，进程退出码 0，明确 `STEP6D_BUILD_PASS`。Vivado 2026.1 (win64), SW Build 6511674；工具环境 Python 版本见 provenance.txt。最后一次相关 RTL/TB/参考/build/wave 修改均早于此次运行，之后没有修改这些输入。运行开始 HEAD 为 9e99c85 加启动器修正；运行期间将相同内容与项目/README 提交为 `183c2942b865d309b1f920803cb75c79463338eb`，build_result.txt 记录该测试提交。后续仅归档生成的项目配置、报告和证据。

在 MAIN 新工程真实执行 synth_1 与 impl_1 至 route_design，均 Complete/100%，未复用旧工程检查点。器件 xc7a200tfbg484-2，唯一 XDC 为 `create_clock -name sys_clk -period 20.000 [get_ports clk]`。profile 1 只验收仿真。

| 默认 profile 0 | 结果 |
|---|---|
| Routed setup | WNS=2.053 ns、TNS=0、20150 端点/0 失败 |
| Routed hold | WHS=0.069 ns、THS=0、20150 端点/0 失败 |
| 路由 | 19943/19943，routing errors=0 |
| Routed 资源 | Slice LUT=10903、FF=8454、DSP=87、BRAM tile=2 |
| 综合结构 | LATCH=0、BLACKBOX=0；DSP48E1=87、RAMB36E1=2 |
| 内部时序完整性 | no_clock=0、unconstrained_internal_endpoints=0、loops=0、latch_loops=0 |

### 警告与 STA 边界

未降低任何告警级别。synth_runme 中锚定 WARNING 行共 145（含重复）：Synth 8-3332 未用寄存器 100（之后工具抑制同类消息）、8-6014 未用寄存器/调试状态 27、8-3936 位宽裁剪 14、8-589 case equality 综合替换 2、8-7129 未用角度低位端口 2。impl_runme 锚定 WARNING/CRITICAL WARNING/ERROR 行为 0，但这不代表下面的独立 DRC/methodology 检查没有告警。

DRC：NSTD-1/UCIO-1 各 1 个 Critical Warning，因没有 IOSTANDARD/引脚约束；CFGBVS-1 1 个 Warning。非板级 Warning：DPIP-1=63、DPOP-1=40、DPOP-2=82（DSP 流水建议）；REQP-1839=20（RAMB36 异步控制），并有 CHECK-3=1 提示该规则已达 20 条报告上限，因此 20 不是全部潜在受影响对象的数量。没有其他 Error/Critical Warning。

Methodology：DPIR-1=1318（异步 reset 驱动妨碍 DSP 寄存器合并）、SYNTH-6=2（RAM 时序可能次优）、SYNTH-10=40（宽乘法器）、TIMING-18=209（外部 IO delay 缺失）。完整分类与对象保留在 warning_categories.txt、drc.rpt、methodology.rpt。

既有 ROM/RAM 控制由异步复位寄存器驱动，REQP-1839 指出复位置位期间可能影响存储内容/读值且默认 STA 不分析此行为。本轮不修改已验收旧模块，也不把上述警告当作板级豁免或宣称已证明安全。仅时钟约束内部路径通过，不包含外部 IO/板级安全验收。

已通过 Vivado `-mode gui` 实际打开 MAIN XPR，加载 wave_step6d.tcl 并 run all。`docs/reports/step6d/gui_demo.txt` 记录默认 `PI_PROFILE=0 DEMO=1`、24+1 接受/装载与 24 个完整周期 PASS，终点 2.500131 ms；synth_1/impl_1 同时为 Complete/100%、NEEDS_REFRESH=0。系统进程窗口标题也显示该 XPR 的真实绝对路径。GUI 与本地波形保持打开，不使用 computer use。

执行计划要求的一次独立整分支只读复核已完成，无 actionable finding 或待办 minor；见 review.txt。最终仅提交本轮新增文件和必要文本证据；Vivado 原始日志另保留本地，提交的文本报告只归一化行尾空白。`git diff --check` 通过。

默认演示打开说明见 `motor_control_ip/integration/README_step6d.md`：打开 MAIN XPR，Run Behavioral Simulation 初停 0 ns，source `FOC_PWM/wave_step6d.tcl` 后先 `run 300 us`，再 `run all`。波形明确区分原始 F24 d_foc、上管 F24 D_high、CMP、shadow/active、采样与生效。theta 为 U16 角度；real 单位仅在 TB。

## 完成边界

没有电机反馈模型、ADC/编码器、六路互补输出、死区、过流 trip、驱动器极性确认、引脚/IOSTANDARD/外部 IO 时序、bitstream 或硬件操作。本轮只能验证三路逻辑 PWM；STA 通过不代表异步器件行为和板级安全已证明。保留 .sim/.runs/WDB/DCP 本地结果，不整体提交。完成后开放 PR 等待 ChatGPT Review，不合并、不进入下一阶段。
