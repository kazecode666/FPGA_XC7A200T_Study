# 浮点模型：连续点位与原MIL对齐

日常只需要一次初始化，随后打开同一个模型并点 Run：

```matlab
cd('D:/Project/FPGA_XC7A200T/simulink模型')
init_PMLSM_PI_FOC_Float_Baseline
open_system('PMLSM_PI_FOC_Float_Baseline')
```

保留用户本地操作默认值：**10 mm、5 s、Vmax=10 mm/s、Amax=100 mm/s²**；Jmax=1000 mm/s³、首段0.05 s开始。任务中的1 mm/1.2 s/V5/A50是独立回归场景，验收脚本显式设置，不覆盖这里的本地默认。修改物理/设计参数应编辑init并在停止后重新初始化；运行中不要执行init。InitFcn只检查，不发送命令或恢复默认值。

## 同一次Run连续运动

1. 停止时设置足够长的 `M1A_StopTime_s`，例如30；可启用工具栏 Simulation Pacing。这里是**仿真秒**，墙钟时间取决于计算速度与pacing。
2. 点 Run。默认 `Host_AutoStart_EN=1` 只自动执行一次首段到10 mm；设为0则从当前位置保持并等待发送。
3. 等待面板 `View_move_ready=1`，在 `Set_Host_Target_mm` 填写**绝对坐标**20 mm。编辑目标本身不提交、不改变原段。
4. 切换 `Send_Move_Toggle` 一次（0→1或1→0均可）。每次切换只提交一次；保持开关不变不会反复发送。
5. 等Ready再次为1后，目标改5 mm，再切换一次发送开关。可继续 -5→0；不需要Stop、重新init或Run。

10→20→5指坐标10、20、5 mm，不是每次增加目标数值。每段从上一段规划终点开始，以新锁存时刻重新调用原S曲线；不清零机械位置、控制器积分或仿真时钟。不支持运动中重规划，不排队：Busy或对齐期间发送的目标会被消费并拒绝，后续Ready不会偷偷执行它，必须重新切换发送。

Ready要求三闭环、PWM允许、无PI/Init复位、对齐旁路或完成；曲线结束后，实际误差在原 `Pos_deadband=0.02 mm` 窗内连续5个位置事件（50 ms，首拍9.9 ms）。`trajectory_done`只说明规划结束，`in_position`说明实际到位；未补偿死区的速度纹波不要求严格为零。

| command_status | 含义 |
|---:|---|
| 0 | 初始保持 |
| 1 | 一次自动首段 |
| 2 | 新点位已接受 |
| 3 | 尚未Ready/Busy，拒绝且不排队 |
| 4 | 目标或发送位非法，拒绝 |
| 5 | Ready时重复当前目标，确认但不运动/重新计时 |
| 6 | 模式、PWM、复位或对齐条件禁止，拒绝 |
| 7 | 点位段被PWM禁止/PI复位中断 |

状态保留到下一个事件。Ready会随实际到位窗重新判断，不能将曾经出现1当作永久许可；发送瞬间若已变0会拒绝，等Ready后重新切换发送，不自动排队。段中PWM禁止/PI复位后，本轮冻结规划参考、标记中断且不置Ready；重新使能不承诺自动续跑。重新Run建立新的仿真，不等同于实机故障恢复。

## 对齐：默认旁路

`Alignment_Enable=0` 时继续原理想角度路径。开启应**停止后**设 `Alignment_Enable=1`，建议 `Host_AutoStart_EN=0`。Run后切换 `Set_Init_Start` 到1；也可停止时先设 `Init_Start=1`，随后Run。`Set_Alignment_Enable`是停止后配置入口，不做运行中热切换验收。

迁移的是原MIL chart：IDLE(0)→RAMP_ID(1)→HOLD_ALIGN(2)→RAMP_DOWN_ID(3)→DONE(4)，100 µs执行，0.5 A、上升10000拍、保持30000拍、释放2000拍。面板显示Init状态和Done；对齐中位置提交被拒绝。DONE后先以**当前实际位置**建立保持参考，等Ready后再发点位，不复用过期的首段计时。

`Init_Reset=1`恢复原图IDLE/Done无效语义，释放为0并重新Start才能再对齐。原图复位**保留偏置数值，但使其有效性失效**；该行为未重设计。它不是全局PI复位或清故障按钮。`Simulation_Travel_Fault`为明确仿真注入，默认0；保留原禁止输入和PWM禁止，没有恢复真实行程检测或完整故障管理。

真实角度继续供plant/逆变器使用，控制器单独使用迁移的固定/反馈角选择。已测的是原MIL现有零位置/零真实角标称场景；不宣称识别未知非零安装偏置。

## 调试模式和暂停

模式、轨迹参数、电机参数在停止后设置，不做无扰热切环。

| 模式 | Position_Loop_EN | Close_Loop_EN | Iq_Test_Mode | 命令 |
|---|---:|---:|---:|---|
| 三闭环 | 1 | 1 | 0 | Host_Target_mm+发送开关 |
| 速度+电流 | 0 | 1 | 0 | Host_Speed_mmps |
| 独立电流 | 0 | 0 | 1 | Host_Id_A、Host_Iq_A，Apeak |

上表变量均有 `Host_` 前缀。矛盾组合在启动前拒绝。Pause暂停仿真时间，Continue继续；Stop结束整个仿真。PWM=0禁止平均逆变器电压，机械和仿真仍可继续；PI_Reset_EN沿用原积分/AW规则，不清全部故障。

默认手动 `Host_Replay_EN=0`。开发用1时，Speed/PWM/Reset由 `M1A_Speed_ts/M1A_PWM_ts/M1A_Reset_ts` 经同一个Host选择，末值保持。连续点位live测试在running时调面板实际绑定的Constant参数，不用From Workspace序列代替交互。

## 旁边的S曲线和预览

画布上的 **S_Curve_Reference_Actual** 内嵌图始终绑定真实Host的 `x_ref_mm` 和plant的 `x_mm`。`target_mm`是编辑草稿，`target_accepted_mm`才是已接收坐标；草稿水平值不能冒充轨迹。

```matlab
preview=preview_PMLSM_reference;           % 停止时默认首段；运行/暂停时读本次锁存段
last=preview_PMLSM_reference('segment');   % 停止后读out.logsout的最后锁存段
```

两种方式均调用原 `pmlsm_scurve_profile`，包含实际段起点、绝对时间与规划速度，不初始化、不运行电机。运行中的预览只读Host显示用状态；停止后的segment模式要求out来自本模型。若在完成后重新init，默认预览代表新的首段；旧out的segment仍是旧仿真，使用该次Host保存的trajectory_config，不借用重新init后的参数。旧out若缺少该配置会明确报错，不猜测历史参数。

所有Goto均为同父层local、方括号显示；跨子系统只有显式端口。仅整理新增区域，FOC/PI及plant内部布局保留。

## 运行依赖、负载及记录

正常Run共六个文件：SLX、init、`m1a_require_float_init.m`、`design_PMLSM_three_loop.m`、`pmlsm_scurve_profile.m`、无隐藏状态的 `pmlsm_point_move_step.m`。preview可选，验收脚本和旧MAT均不是正常Run前提。

母线 `Udc=48 V`，负载为顶层 `Simulation_Load_N` 读取 `M1A_Load_ts`。例如停止后设置：

```matlab
M1A_Load_ts=timeseries([0;0.5;0],[0;0.8;1]); % N，末值保持
```

保留电流/PWM100 µs、速度1 ms、位置10 ms、plant1 µs、一次50 µs应用延迟和一次1 µs平均死区。长交互默认物理日志抽取100倍到100 µs，命令/状态按100 µs全采，不改plant步长；短时电流细节仍可通过Motor_Control_Monitor的Scope查看或停止后将 `M1B_Physical_Log_Decimation=1`，注意长运行内存。

正常Run保存 `out.logsout` 和SDI记录，不清空旧SDI运行：

```matlab
getElementNames(out.logsout)
Simulink.sdi.view
s=out.logsout.get('iq_ref').Values;
figure;plot(s.Time,s.Data);xlabel('s');ylabel('Apeak');
```

原41路具名记录保留；`id_ref/iq_ref`为对齐/故障选择之后真正送FOC的参考，新增 `*_ref_before_alignment`记录选择前值。`id_controller/iq_controller`为控制角下Park结果，`id/iq`为plant真实坐标；角度日志区分 `theta_control_rad/theta_true_rad`。新增trajectory_config保存Vmax/Amax/Jmax/minRamp/Ts_ACR的实际运行快照；新增段起点/时间、接受计数、拒绝计数、Ready/Busy/中断及原对齐6路记录。`speed_memory/x_speed`实测记录周期是1 ms，不能写成100 µs。完整[信号表](reports/m1b_repeat_moves_alignment/signals.csv)给出来源、抽取及实际时间戳。

API运行中提交、暂停/继续及保存绑定的验收与鼠标点击分开报告；没有自动鼠标点击。布局图是MATLAB模型导出，具名CSV是API导出，均不冒充SDI侧栏截图。

[本轮验收](../coordination/reports/m1b_repeat_moves_and_alignment.md) · [结果索引](reports/m1b_repeat_moves_alignment/README.md) · [FOC只读准备](FOC_FIXED_POINT_READINESS.md)。
