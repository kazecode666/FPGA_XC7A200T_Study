# A1：真实速度 PI 审计

基线 main：`944bd702377a2a90acea720f8fdb575781639a2d`（PR36、PR37 已合并）。
审计对象为原工作树 **未提交的真实 SLX**，不是 Git 中的旧布局。
SHA256：`074c2ca8c7f708ff50194245382391647481f593e88898245bf68278f02af517`。
原文件仅静态读取、在独立 R2026b 进程中加载和复制子系统，未保存、未运行整机仿真。
`slx_static_audit.txt` 保存源连接与 SID；`runtime_audit.txt` 保存实际生效参数。

## 调度和输入

SID785 `Control_Tick_10kHz` 是 `FunctionCallGenerator`，SampleTime=`Ts=100 us`，从 t=0 调用 SID505。
SID740 `Scheduler_10k_1k_100` 的 `spd_cnt_z`（759）初值 0：先做 `count+1`，比较 `>=10`（760），终值拍把下一计数清零。
所以 speed_tick 首次在 **0.9 ms**，之后 **1.9、2.9、… ms**，周期 1 ms；不是 t=0 的速度执行。
SID1128 为 rising TriggerPort，状态 held。后续 Checkpoint 的有效 CE 必须代表这个上升沿事件；持续高电平不是多个原模型 tick。
真实调度器及 SID785 function-call 源复制入独立 testbench，调度器保持 function-call 父级调用上下文。运行结果由 `actual_tick` 与向量逐拍比较确认，日志设为无限数据点，避免 ToWorkspace 默认1000点截断。

速度参考：SID991 `Reference_Manager` 先按 Position_Loop_EN 选择位置环速度或 v_ref_cmd，再经 SID1030 slew limiter、SID1020 的 ±20 mm/s 限幅、SID1028 Close_Loop_EN 选择（禁用时 0），输出3 → [v_selected] → SID1264 → Speed_Loop 输入1。本次 as-found SLX 的速度命令由 SID1965 `Step7D_Interactive_speed` 的 STEP7D_speed_ts 提供，不能只引用 Simple_Host 内的速度公式。
反馈：plant 内 SID233 `v_to_mmps` 乘1000把 m/s 转 mm/s → SID242/plant输出7 `v_mmps` → SID489 [v_mmps] → SID922 → control task 输入3（510）→ Speed_Loop 输入2（1124）。单位均为 mm/s，输出是 Apeak。未采用位置差分或滤波。
Angle_Init_EN（1125）在该模型由 SID1272 的常量0提供。
测试直接注入 PI 边界速度参考和速度反馈，刻意超过正常 ±20 mm/s 参考范围以覆盖饱和，不代表整机工作范围。

## 离散方程（一次有效速度 tick）

定义 x 为 SID1228 UnitDelay **当前输出的旧积分状态**，d 为 SID1166 UnitDelay 的旧 excess；初值均为0。
`clip(z,L)=max(-L,min(L,z))`。

```text
e       = v_ref - v_meas                       // SID1163
P       = Kp_ASR * e                          // SID1130
I_inc   = (Ki_ASR * Ts_ASR) * e               // SID1129
aw      = Kaw_s * d                          // SID1149，上一 tick 的 excess
u       = 0 + P + x                          // SID1133（friction_compensation 已 commented on）
l       = clip(u, Speed_loop_Iq_Limit)         // SID1159
excess  = u - l                              // SID1162，送 SID1166 的下一状态
candidate = clip(x + I_inc - aw, Iq_int_limit)// SID1134 → SID1158

hard = Angle_Init_EN OR PI_Reset_EN_cmd OR Iq_Test_Mode_cmd OR NOT Close_Loop_EN_cmd
refzero = abs(v_ref) < v_ref_zero_eps
over = (abs(v_ref) > v_ff_eps) AND (sign(v_ref)*e < -v_over_eps)
int_reset = hard OR refzero OR over

iq_ref = hard ? 0 : l                        // SID1164，限幅之后门控
x_next = int_reset ? 0 : candidate           // SID1165，积分限幅之后门控
d_next = excess                             // 无 reset 门控！
```

当前数值：Kp=0.018033474852681124，Ki=1.4426779882144898，Ts_ASR=0.001 s，KiTs=0.0014426779882144898，Kaw=0.08。
输出限幅 ±1 A，积分限幅 ±0.5 A；v_ff_eps=0.5 mm/s，v_over_eps=3 mm/s，v_ref_zero_eps=0。
`abs(v_ref)<0` 永远为假；不能把零参考解释为无条件积分复位。
`over` 只清下一积分状态，当拍输出仍使用旧 x；该条件与主机 PI_Reset 不同。

## Reset、enable 和保持

hard 和 int_reset 分别来自原 `pi_reset_manager`（1189）输出1、2。
根层 Effective_PI_Reset（1277）是 [PI_Reset] OR PWM_Disabled（1276）。本次 as-found SLX 中 [PI_Reset] 由 SID1968 `Step7D_Interactive_reset` 的 STEP7D_reset_ts 提供，而非直接使用 Simple_Host 的 Host_PI_Reset_EN。有效 reset 进入 control task、优先级 -10 的数据存储写入，再被 reset manager 读取。
独立模型的 `reset` 输入对应 **有效 PI_Reset_EN_cmd**；`enable` 对应 Close_Loop_EN_cmd；角初始化和电流测试模式另有可观察输入，不被省略。

没有速度子系统 EnablePort；disable 是 hard reset 的一项。在有效 tick：输出立刻0、下一 x 清0，当前 x 仍是旧状态；d 仍更新为当拍 `u-l`。
reset/tick 同拍：先以旧 x/d 计算 u、l、candidate，hard 覆盖输出，int_reset 覆盖 x_next；不会把 d 清零。
reset/disable 完全位于两个速度 tick 之间：速度 PI 不执行，输出和两个状态保持。
因此 disable、reset 是 **采样复位**，不是 FPGA 异步复位；不能在空闲时钟擅自更新状态。
re-enable 后取上个执行拍留下的 x/d；尤其 d 不因 hard reset 自动清零。

SID1229 iq_ref → [iq_ref_normal] → SID991 输入1。
Reference_Manager 输出2在 Iq_Test_Mode 时改选 iq_test_ref，否则选速度 iq_ref；这里的 outer reference 与 PI 自身的 l/u 不能混为一谈。

## 保真边界

独立 `speed_pi_float.slx` 为重新编写的图形运算模型。
`speed_pi_compare_tb.slx/Original_PI` 为真实 SID1122 原样副本，仅增加观测端口和饱和比较器；原 reset manager、UnitDelay、Gain、Sum、Switch、限幅器全部保留。
原主 SLX 的 InitFcn 含交互联合仿真入口，因此不调用它进行整机仿真；验证采用允许的独立模块抽取。
本阶段不改变原算法、整机参数、FOC 或 SLX；调度和复位事实与任务书要求的待审计语义一致。
