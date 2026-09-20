# Step 6E 执行报告：互补死区与六路统一关断

## 主目录、基线和修改范围

MAIN 实测为 `D:/Project/FPGA_XC7A200T`，Git 主工作树 gitdir/common-dir 均为 `.git`，远端 `https://github.com/kazecode666/FPGA_XC7A200T_Study.git`。fetch 后从最新 main `fcc33bb70107811e99ddab11187906696b4b24db` 在同目录创建 `step6e-complementary-pwm`，包含已合并 6D 提交 `2f3461f5716496e323f2aa91debe6e6df1409bd1`。上游只有本轮两份任务/交接文档，与用户修改不重叠。

切换前后及交付前核对原 16 个 tracked 路径的 binary diff 未变、97 个原有 untracked 文件仍存在且大小未变。原硬件资料移动、4 个旧 XPR 修改未提交。旧 worktree 原位保留，不新建 worktree/clone，不 stash、强制 checkout、reset、清理或使用文件哈希。`FOC_Current` 和 `FOC_PWM` 的工程、.sim/.runs/WDB/DCP 保留，见 local_preservation.txt。

旧文件仅两处授权兼容变更：

- `mc_foc_pwm_top.sv` 增加输出 `pwm_command_loaded`，一个 assign 直接连到已有 compare_load_event，无新寄存器或调度/数据变更。
- `mc_foc_pwm_top_tb.sv` 增加同名 logic，以兼容原 dut(.*)。旧测试、断言、计数和 PASS 标记不变。

其他新增均在任务书清单内；C1–C4、mc_duty_to_cmp、motor_pwm_core、ROM、数学参考、197 行 6D 向量、Simulink、旧工程和报告不改写。未打开/重建旧 FOC_PWM；共享源接口已变，其旧检查点不能声称验收了新输出接口，后续需要刷新时应重新综合/实现。这里不伪造旧工程 NEEDS_REFRESH 实测值。新整核在 FOC_Gates 独立计算。

## 实现与边沿

mc_pwm_deadtime_leg 使用目标位、有效位和参数宽度倒计数；只通过 always_ff 驱动输出。默认 D=25、合法 1..2500；0/2501 均经实际展开得到明确非法参数拒绝，见 invalid_parameters.txt。

E 采到启用或新请求时关闭旧侧、装满 D。E..E+D-1 全关，E+D 开启目标侧；反向、disable、reset 优先取消，无短脉冲迟到补发。宽度 ≤D 的请求不产生目标脉冲，D+1 产生一拍；稳定请求保持，不在每个 ZERO 重插死区。原 PWM 更新 B，桥臂采样 E=B+1，该一拍不误算进 D。

wrapper 复用一个 control 和三个 leg；无复制 FOC/载波 FSM，无可综合跨层引用，不改变 6D 极性。第一次真实装载 S 后，S+1 armed，S+2 开始启动等待，默认首开 S+27（540 ns，其中启动传播 2 拍、死区 25 拍）。正常切换实际双关 25 拍=500 ns。

同步 trip_req 直接参与 gate_enable，采样边沿六路写零并 trip_latched；仅 reset 清除。run_enable 停止也当拍清零。旧 control_needs_reset 在 F 置位，F+1 六路清零。fault_code 原样透传，trip 单独观察。撤销 trip 或重新 run 不恢复；整链 reset、新鲜命令实际装载与完整启动等待后才恢复。高 trip 穿越 reset 释放仍不会打开门极。

## 仿真：先主功能，再必要检查

最小 leg 测试先观察缺模块失败，实现后通过；wrapper 零样本也先观察缺模块失败，随后实测 S+27 首开及正常 H/L、stop 通过。先完成干净的 24+tail 演示，再扩展自动关断检查。没有产品级失败探针框架、新数学参考或新大型向量集。

最终完整 build 为 `docs/reports/step6e/final01/`，进程退出码 0、明确 STEP6E_BUILD_PASS，最后一次 RTL/TB/build/wave 修改后执行。开始时已提交全部相关输入 `cc8276f23eceb62a4dd07b7311a4711554d5526a`；运行期间仅提交生成的项目和 README 为 `701acd8e54490018ec755c233ebfdcbf0d1d37b0`。provenance 记录开始提交，build_result 记录结束提交，两者 RTL/TB/脚本相同。

| 单桥臂 D | NBA 后比较拍数 | H/L 实际开启次数 | 定向用例 |
|---|---:|---:|---|
| 1 | 226 | 11/11 | duty 5、短脉冲 3、取消 3、异步复位 1 |
| 25 | 1617 | 11/12 | 同上 |
| 50 | 3067 | 11/12 | 同上 |

duty 为 0/25/50/75/100%；短脉冲为 D-1/D/D+1（D=1 的 D-1=0 在采样沿之间撤销）；取消包含等待反向、精确终点禁用和等待中 disable。正常双向开启非零，防止永远全关假通过。参考只记录绝对边沿和最近请求/启用时间，不读 RTL 倒计数；边沿前保存输入，NBA 后比较、检查未知值与同桥臂互锁。

| 整合测试 | 基础/尾样本 | 完整周期 | 门极参考和关断 |
|---|---|---:|---|
| profile 0 DEMO=0 | 80+1，accept/load=81/81 | 80 | 405007 拍；每相 H/L=81/80；10 项关断通过 |
| profile 1 DEMO=0 | 80+1，accept/load=81/81 | 80 | 405007 拍；每相 H/L=81/80；10 项关断通过 |
| 默认 DEMO=1 | 24+1，accept/load=25/25 | 24 | 125007 拍；每相 H/L=25/24；稳定输入，无故障注入 |
| 原 6D DEMO=0 profile 0/1 | 各 80+1 | 各 80 | 原 6 项协议检查和原 PASS 计数不变，通过 |

门极模型在定向关断阶段也持续逐拍比较；表中拍数是正常流结束时打印的值。每套新自动测试 10 项为：H 导通/L 导通/死区等待/精确 E+D 的 trip 共 4；等待中停止、首次装载前停止共 2；首次装载前 trip 1；旧 control 故障 1；新鲜 reset 恢复 1；trip 高跨 reset 1。shutdown 后观察 5200 拍，不因撤销 trip/run 重开而出现陈旧使能。

新整合对 160 笔原始输入逐位比较 FOC duty、CMP/shadow/active，实测 N+512 完成、N+516 shadow 握手、N+2499 ZERO 生效。原始 PWM 每个完整 5000 拍周期三相 HIGH=2×CMP，包含起始 ZERO、不含下个 ZERO。门极 HIGH 不使用这个等式，按独立事件模型与实际开启间隔验证，不补脉冲。本轮不声称死区后平均电压/电流闭环性能。

## 新工程与实现

真实 XPR：`D:/Project/FPGA_XC7A200T/FOC_Gates/FOC_Gates.xpr`。21 个综合源、ROM 与向量均解析在 MAIN；part=xc7a200tfbg484-2，唯一 XDC 为 `create_clock -name sys_clk -period 20.000 [get_ports clk]`。默认综合 PI_PROFILE=0/DEADTIME_CYCLES=25，默认仿真 0/DEMO=1/25、初停 0 ns。

Vivado 2026.1 win64 SW Build 6511674。新工程实际计算综合（2026-09-20 16:23:34 +0800 启动）和 implementation（16:25:35 启动），16:28:26 完整构建退出；没有复用旧工程检查点。脚本记录 COMPUTED/REUSED，以后仅同源且 NEEDS_REFRESH=0 可复核复用。

| 默认实现指标 | 实测 |
|---|---|
| Setup | WNS=2.257 ns、TNS=0，20198 端点、0 失败 |
| Hold | WHS=0.041 ns、THS=0，20198 端点、0 失败 |
| Route | 19989/19989，routing errors=0 |
| Routed resources | Slice LUT=10934、FF=8481、DSP=87、BRAM tile=2 |
| 结构 | LATCH=0、BLACKBOX=0；DSP48E1=87、RAMB36E1=2 |
| 内部时序检查 | no_clock/unconstrained_internal_endpoints/loops/latch_loops 均 0 |

profile 1、D=1/50 只仿真，其他死区参数未进行全套验收，不宣称其 route 已通过。

## 告警与未证明的范围

未降级告警。综合锚定 WARNING 行 145：Synth 8-3332 未用寄存器 100（工具其后抑制同类）、8-6014 未用状态 27、8-3936 位裁剪 14、8-589 case equality 综合替换 2、8-7129 未用角度低位端口 2。实现 runme 锚定 WARNING/CRITICAL WARNING/ERROR 行为 0，不等于独立规则报告无告警。

DRC：NSTD-1/UCIO-1 各 1 个 Critical Warning，CFGBVS-1=1；DPIP-1=63、DPOP-1=40、DPOP-2=82 为 DSP 流水建议；REQP-1839=20 为 RAMB36 异步控制，CHECK-3=1 表示该规则报告已达 20 条上限，不把 20 当作所有受影响对象总数。无其他 Error/Critical Warning。

Methodology：DPIR-1=1318（异步 reset 驱动妨碍 DSP 内寄存器合并）、SYNTH-6=2（RAM 时序可能次优）、SYNTH-10=40（宽乘法器）、TIMING-18=214（外部 IO delay 缺失）。完整对象/分类保留在 final01 的 drc.rpt、methodology.rpt、warning_categories.txt。

既有 RAM 异步控制可能在复位置位期间影响读值/内容，默认 STA 不证明此行为。同步 trip 不保证异步窄脉冲捕获或失钟关断；默认 500 ns 仅为学习设定，真实器件安全死区未设计。本轮无引脚/IOSTANDARD、外部 IO/trip 时序、驱动器极性/独立保护链、功率级/电机/ADC/编码器、bitstream、硬件操作或联合仿真。

## 默认 GUI 与交付

已通过 Vivado -mode gui 实际打开 MAIN XPR、加载 wave_step6e.tcl 并 run all，得到 STEP6E_DEMO_PASS，终点 2.500131 ms。gui_demo.txt 同时记录默认参数与 synth_1/impl_1 Complete/100%/NEEDS_REFRESH=0；系统窗口标题指向真实 XPR。GUI 保持干净演示状态，未使用 computer use。

重新打开步骤见 `motor_control_ip/integration/README_step6e.md`：Run Behavioral Simulation 初停 0 ns；source 本地 wave_step6e.tcl；先 run 300 us，再放大 1–2 us 观察 500 ns 双关；run all 完成。已到终点可 restart。WDB/.runs/.sim/DCP 保留本地，不整体提交或删除。

独立整分支只读复核已完成，无 Critical/Important/Minor 待办；计数、时序和报告一致，范围排除项沿用任务书并记录于 review.txt。最终暂存路径审计及 git diff --check 通过。文本证据仅去除行尾空白，原始工具日志仍在本地。交付开放实现 PR 等待 ChatGPT Review，不自动合并或进入下一阶段。
