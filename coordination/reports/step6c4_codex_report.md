# Step 6C4 执行报告

## 工作目录与范围

本次 MAIN 实际为 `D:/Project/FPGA_XC7A200T`，Git 主工作树的 git-dir/common-dir 均为 `.git`，远端为 `https://github.com/kazecode666/FPGA_XC7A200T_Study.git`。起始主目录提交 `74f6128954a4972c0ae15de4bddd716d30688d36`；fetch 后从最新 main `2ffc23e` 创建 `step6c4-foc-current`。已验证 C3 合并提交 `4eb050bd62f6ac7c80ecf3f0a4a017d62f07d1ef` 是基线祖先。

没有创建新 worktree/clone。原 C2/C3 worktree 保留。同步前检查 624 个上游变更路径与用户改动无冲突，再进行普通 Git 分支切换；切换后原 15 项 tracked 改动的 status/binary diff 一致，12 个未跟踪硬件资料仍在原位置且大小一致。快照保留于本地 `.Xil/step6c4_local_preflight/before.json`。用户三个旧 XPR 修改、根目录资料移除和 `硬件说明/` 不属于本 PR；未 stash、强制覆盖或清理。

唯一新 RTL 是 `mc_foc_current_core`。C1/C2/C3 数学模块、ROM、旧 PWM、Simulink、Step 6A 数据和历史报告保持已验收版本。没有接电机对象、ADC、PWM 或硬件，没有 bitstream、硬件编程或 Step 6D。

## 主链、状态和 TDD

先编写最小零输入 TB，真实 Vivado xelab 因缺失 `mc_foc_current_core` 报错，之后才实现连接顶层。零输入在 N+512 返回三个 8388608，保存零输入 WDB 和 `docs/reports/step6c4/local_bringup.md`。Python 六项测试先观察缺失参考模块失败，再实现组合模型。随后扩展同一个自检 TB。

顶层捕获全部样本；C1 同笔 sin/cos 原样保存用于逆 Park，C2/C3 共用 captured vdc。子核接受/输出/父捕获分别为 1/6/7、8/264/265、266/268/269、270/398/399 拍。统一 512 拍输出，最早 513 拍接受下一笔。PI 只由 C2 持有和更新，成功 N+264 提交；下游失败不回滚。enable 只限制新接受，无效 vdc 不启动子核，内部异常需 reset 恢复。

## 数值与协议验证

组合 Python 模型直接调用已验收算法函数，只量化 Step 6A 原始输入。每 profile 从零状态连续回放 80 行历史，然后 256 行固定种子样本（0x6C42026 + profile），上一行 next_state 递推到下一行，不用 CSV 中间输出替代计算。正常流零意外错误，无筛除样本。

每 profile 基础 336 行，5000 clocks 送样本；逐位检查 Clarke、sin/cos、Park、PI raw/hi/lim、OLD/NEXT 状态、逆 Park、SVPWM 时长/sector/duty/error，以及每级 valid、单次启动和状态提交边沿。合计 672 基础行。

每 profile 额外协议序列包括：6 笔短序列（5 次最早 513 拍间隔）、20 拍 disable 拒绝、处理中 disable 仍完成、零和负母线（携带 pi_reset 仍保持状态）、C2/C3 运算中各一次异步复位中止、下游 RANGE_ERROR 不回滚 PI、丢失 SVPWM valid 触发 INTERNAL_ERROR/reset 锁定、reset 后正常恢复。pi_reset/q_zero 同时覆盖历史和 seeded 命令；忙时每拍扰动全部输入。每 profile 349 accepts / 347 responses / 2 aborts，343 笔完整正常事务共 175616 拍输入扰动；总计 698 / 694 / 4。

## Step 6A 整链浮点误差

下表 source_row 是 160 行数据中的 **一基行号（不计表头）**。电流单位 A、电压 V，t1/t2 除以 100 us 归一化，原 duty 计数除以 10000。全部 160 行源值/固定值/误差在 `coordination/reports/step6c4_foc_fixed_vectors.csv`。整数逐位相等是本轮硬门槛；以下是误差观察，不引入新容差，不外推 C3 独立比较的 5e-5 或 sector 白名单。

|量|最大绝对误差|profile|source_row|case|
|---|---:|---:|---:|---|
|i_alpha|1.220703125e-05|0|15|angle_0.0000|
|i_beta|1.3594003975e-05|0|15|angle_0.0000|
|id|1.3594003975e-05|0|18|angle_1.5708|
|iq|2.17200290529e-05|0|66|feedforward|
|ud_lim|9.58486421498e-05|1|98|angle_1.5708|
|uq_lim|0.000133832436049|1|146|feedforward|
|v_alpha|0.00182476466512|1|150|sat_hold_1|
|v_beta|0.00469674940051|0|69|sat_start|
|ud_raw|8.58946664724e-05|1|98|angle_1.5708|
|uq_raw|0.000120659809554|1|146|feedforward|
|t1|0.00014175989159|1|150|sat_hold_1|
|t2|0.000169484264522|0|69|sat_start|
|duty_u|4.88792293556e-05|1|146|feedforward|
|duty_v|1.38897596244e-05|0|69|sat_start|
|duty_w|0.000155637397177|1|150|sat_hold_1|
|du_d_z|2.27579897949e-06|1|156|recovery_3|
|du_q_z|1.49733110177e-06|1|156|recovery_3|

角度 0.2 rad 的量化编码为 2086，已验收 C1 ROM 产生的 sin/cos 相对原浮点误差为 -0.000198261459 / +0.0000359612213。在 source_row 69/150，以固定 ud/uq 配合精确原角度重算，可分离出逆变换 alpha/beta 的角度/ROM项约 -0.00198969 / -0.00461102 V，解释了这两行电压误差的主要来源；余项来自 PI 和电压定点化。没有修改已验收 LUT 规则来缩小误差。历史 duty_w 最大误差约 1.55637e-4，高于 C3 独立输入比较数值，作为整链差异明确保留供 Review。

sector 差异如下；sat OLD 与源 `sat_flag_z` 的差异为 **0**：

|profile|source_row|case|source sector|fixed sector|
|---:|---:|---|---:|---:|
|0|51|edge_1_1.732|3|1|
|0|63|edge_1_-1.732|2|6|
|1|134|edge_-1_1.732|1|5|
|1|140|edge_-1_-1.732|6|4|

这些行在 ±1/±1.732 扇区边界附近、角度为零。row 51/63 的 alpha/beta 误差约 6.10e-6/1.42e-6 V；row 134/140 约 1.22e-5/3.33e-5 V，足以改变边界符号。完整 duty 误差仍逐项列在 CSV；未设置扇区豁免来影响整数验收。未观察到未解释的整体比例/极性翻转。

## Vivado 和本地交付

真实工程为 `D:/Project/FPGA_XC7A200T/FOC_Current/FOC_Current.xpr`。默认 synthesis/TB 均为 PI_PROFILE=0，目标 xc7a200tfbg484-2；唯一 XDC 为 20.000 ns sys_clk。工程外部引用 MAIN 的 16 个 RTL、ROM、TB 和向量，不读取旧 worktree。

Vivado 2026.1（SW 6511674）、验收环境 Python 3.13.0。默认参数在本地工程 synth_1/impl_1 实际完成综合与 route，原生 runme.log 和 DCP 保留。

|阶段|Slice LUT|FF|DSP48E1|BRAM Tile|
|---|---:|---:|---:|---:|
|综合|10466|8090|87|2|
|Route 后|10375|8094|87|2|

综合原语清单的未打包 LUT 单元计数为 13196，与 utilization 的 Slice LUT 口径不同。锁存器/黑盒为 0；ROM 推断为两个 RAMB36E1。

默认 profile 0 的 routed WNS=+1.900 ns、WHS=+0.029 ns、TNS=THS=0，setup/hold 各 19456 个端点、失败均为 0；19019/19019 个网络完整路由，routing errors=0。no_clock、unconstrained_internal_endpoints、loops、latch_loops 均为 0。最差 setup 从 SVPWM captured_quotient_b 到 t1_debug CE，最差 hold 在 C2 eval_engine 内。profile 1 仅仿真，没有整核 route/时序声明。

警告未降级或掩盖：综合 runme.log 的 anchored WARNING 为 143（含重复，工具对 Synth 8-3332 默认显示上限 100），主要是截断/未使用状态、调试寄存器裁剪和 LUT 不使用角度最低两位；综合 ERROR/CRITICAL WARNING 均为 0。impl runme.log 的 anchored severity 行为 0，**这不意味着 DRC 没有警告**：独立 DRC 报告含 NSTD-1/UCIO-1 Critical Warning、CFGBVS-1，DSP 输入/输出流水建议和 20 项 REQP-1839 RAMB36 异步控制警告，另有 CHECK-3 默认规则显示上限提示。Methodology 含 DPIR-1 1318、SYNTH-6 2、SYNTH-10 40、TIMING-18 283。异步复位驱动的 RAM 控制警告不由默认 STA 证明无风险；本轮保留既有复位契约，测试覆盖中途异步复位与恢复，但不将数字仿真解释为器件异步行为或板级验证。没有约束引脚、IOSTANDARD、外部 I/O delay，因此仅是内部单时钟计算核时序验收。

最终验收为 `docs/reports/step6c4/final04/`，测试代码提交 `bd258b831a8e103f0b7271a5623e576ac570892e`，Vivado 进程退出码 0，准确标记 `STEP6C4_BUILD_PASS`。六项 Python 检查（C4 六个单元测试、C4 fixture --check、C1/C2/C3 --check、Step 6A verifier）及两套 C4 仿真、Step 6B PWM TB 均通过；最终 build 不运行 --generate，不重写期望向量。

首次实际综合/route 在 final02 完成。最后脚本修改后的 final04 完整验收重新执行 Python/仿真及综合/route 报告和门槛检查；设计输入未变，Vivado 确认两个既有 run 的 NEEDS_REFRESH=0，故复用本地已完成检查点，未虚称重复综合、未清空结果。期间 final01 因参数化波形路径失败，final03 因重复写同值综合 generic 导致内存中的 run 失效而停止；两处脚本问题都实际复现后修正，final04 验证通过。失败诊断保留本地，不作为通过证据。没有执行 reset_run 或移动/删除 .runs。

主要证据：`build_result.txt`、`provenance.txt`、两份 `c4_profile*_simulate.txt`、`project_paths.txt`、`synth_resources.txt`、`routed_resources.txt`、`route_timing_gate.txt`、`check_timing.rpt`、setup/hold 与利用率报告、DRC/methodology/警告分类。final04 里的原生 synth/impl 日志保留首次计算的真实时间，provenance 记录最终复核脚本提交，二者用途不同。

2026-09-20 已实际用 Vivado GUI 打开主目录 XPR，运行默认 profile 0 的完整行为仿真，并加载 `FOC_Current/wave_step6c4.tcl`。首个启动会话出现 ^C 中断，未计通过；保留诊断和中断 WDB 后，持续会话重跑成功。实际成功记录为 `docs/reports/step6c4/gui_default_simulation.txt`，窗口标题/句柄为 `gui_window.txt`。GUI 中 synth_1/impl_1 均 Complete、NEEDS_REFRESH=0；默认仿真和波形保持打开。

`local_artifacts.txt` 核对了两个 profile 和 GUI 波形里的同笔角度/母线、PI OLD/NEXT 路径，以及非空 WDB、综合 DCP、routed DCP。工程目录没有 .bit。用户原有 tracked diff 和 12 项未跟踪资料保留情况见 `local_preservation.txt`。最终只提交 C4 文件和必要文本证据，.sim/.runs/cache、中断及调试过程保留本地，没有删除文件来制造干净工作区。

用户重新打开步骤：打开上述真实 XPR，Run Behavioral Simulation，Tcl Console 执行 `source D:/Project/FPGA_XC7A200T/FOC_Current/wave_step6c4.tcl` 和 `run all`。计算延迟为 512 拍/10.24 us，控制周期仍为 5000 拍/100 us。实现 PR 打开后停止，等待 Review，不自动合并。
