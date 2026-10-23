# M1A 浮点模型手动操作

本模型用于纯 Simulink PI-FOC 研究。日常只运行一次初始化，不需要先跑验收脚本。

## 打开并运行

在新 MATLAB 窗口执行：

```matlab
cd('D:/Project/FPGA_XC7A200T/simulink模型')
init_PMLSM_PI_FOC_Float_Baseline
open_system('PMLSM_PI_FOC_Float_Baseline')
```

在模型工具栏点 **Run**。**Pause** 暂停推进时间，**Continue** 继续，**Stop** 结束本次仿真。等效命令：

```matlab
out=sim('PMLSM_PI_FOC_Float_Baseline');
```

默认目标1 mm，停止时间1.2 s；StopTime保存为表达式`M1A_StopTime_s`。停止后可设置`M1A_StopTime_s=2`再Run。这里是仿真秒，计算墙钟时间可能不同；需要慢速观察可在工具栏启用Simulation Pacing。已用API验证start/pause/continue/stop和绑定目标参数的暂停调节；未用鼠标点击Dashboard自动化。

## 四个运行所需 m 文件

| 文件 | 职责 |
|---|---|
| init_PMLSM_PI_FOC_Float_Baseline.m | 唯一手动初始化；默认命令、电机、PI、时基及场景 |
| m1a_require_float_init.m | InitFcn自动只读检查，用户无需手动运行 |
| design_PMLSM_three_loop.m | 初始化调用的原三环增益计算，公式未改 |
| pmlsm_scurve_profile.m | Host采用的原S曲线函数 |

`preview_PMLSM_reference.m`为可选预览；`scripts/m1a_*.m`是开发测试。重新初始化会恢复默认命令，运行中不要执行完整初始化。脚本先使旧成功标识失效，成功后才重新设置。改物理参数或设计参数后应修改init并重跑；正常入口不再锁死固定Kp/Ki数字。

## 模式与命令

Simple_Host是唯一控制命令出口。顶层编辑控件绑定其内部Constant引用的Base变量；默认手动`Host_Replay_EN=0`。**模式、目标、轨迹参数在停止后设置**，不支持运动中无扰切环或目标重规划。修改普通Base变量不代表运行中参数必定已更新。

| 模式 | Host_Position_Loop_EN | Host_Close_Loop_EN | Host_Iq_Test_Mode | 给定 |
|---|---:|---:|---:|---|
| 三闭环（默认） | 1 | 1 | 0 | Host_Target_mm，经轨迹得到x_ref_mm |
| 速度+电流 | 0 | 1 | 0 | Host_Speed_mmps，直接速度命令 |
| 独立电流 | 0 | 0 | 1 | Host_Id_A、Host_Iq_A（Apeak） |

矛盾的组合在启动前拒绝。示例均在停止后执行，然后Run：

```matlab
% 三闭环负目标
Host_Position_Loop_EN=1; Host_Close_Loop_EN=1; Host_Iq_Test_Mode=0;
Host_Target_mm=-1;
% 或速度+电流模式
Host_Position_Loop_EN=0; Host_Close_Loop_EN=1; Host_Iq_Test_Mode=0;
Host_Speed_mmps=10;
% 或独立电流模式
Host_Position_Loop_EN=0; Host_Close_Loop_EN=0; Host_Iq_Test_Mode=1;
Host_Id_A=0; Host_Iq_A=0.2;
```

运行使能`Host_PWM_EN=1`，复位请求`Host_PI_Reset_EN=0`。可暂停后用对应顶层编辑控件调节PWM/复位，再Continue；它们绑定唯一有效命令。PWM=0禁止平均逆变器电压，但仿真和机械运动仍继续；**Stop结束整个仿真**。有效电流PI复位为请求OR PWM禁止。请求不是“清除所有故障”按钮；速度积分和AW延迟沿用原保持/更新语义，见修订报告。

自动回放只在`Host_Replay_EN=1`时使用`M1A_Speed_ts / M1A_PWM_ts / M1A_Reset_ts`，由Host内部明确选择再输出，不旁路Host。它们末值保持，不依赖停止时间。原`Host_Enable_Schedule`只为历史源模型对照保留，新Host模式以表中三个开关为准。

## 轨迹及仿真环境

停止后执行`preview=preview_PMLSM_reference;`，它读取现有Base参数，调用同一个标量S曲线函数，显示整段规划参考；不运行电机、不重新初始化。`Host_Start_s`是开始时间，`Host_Traj_Vmax/Amax/Jmax`为轨迹限制，`Host_Speed_Ramp_s`是最小轨迹加减速时间。速度模式使用直接速度给定；规划速度与Reference_Manager实际选中的`v_ref`不是同一信号。

顶层`Trajectory_Reference_Actual` Scope叠加实际`x_ref_mm`与`x_mm`，目标是`target_mm`，不要把目标水平线当成规划曲线。

负载和母线是**仿真环境边界**，不是实机上位机命令。母线使用`Udc`；唯一有效负载是顶层`Simulation_Load_N`读取`M1A_Load_ts`。例如停止后：

```matlab
M1A_Load_ts=timeseries([0;0.5;0],[0;0.8;1.0]); % N，末值保持
M1A_StopTime_s=1.3;
```

`Host_Load_N`是初始化默认负载，修改后需重新构造M1A_Load_ts。默认48 V、零负载、电流/PWM100 us、速度1 ms、位置10 ms、plant1 us，保留一次50 us更新和一次1 us平均死区；未重新整定PI。

## 查看具名记录

正常Run自动保存`out.logsout`并写入SDI，无需验收脚本重命名日志，不清空用户旧SDI运行。

```matlab
getElementNames(out.logsout)
Simulink.sdi.view
s=out.logsout.getElement('iq_ref').Values;
figure; plot(s.Time,s.Data); xlabel('s'); ylabel('Apeak');
```

推荐SDI分组：位置`target_mm/x_ref_mm/x_mm`；速度`v_ref/v_mmps`；电流`id_ref/id/iq_ref/iq`；执行量`vd_cmd/vq_cmd/vd_applied/vq_applied`、三相`duty_*_cmd/duty_*_applied`和使能。`iq_test_ref`只是测试入口，三闭环应比较选中的`iq_ref`与`iq`。日志详细来源及采样见[信号表](reports/pr47_host_revision/signals.csv)。

Motor_Control_Monitor保留真实信号的具名Scope入口，不参与计算；已移除旧19列向量及motor_control_monitor输出，用户不需要记列号。FPGA counts/事务/故障零值占位全部移除，真实归一化duty仍保留。

[轨迹结果](reports/pr47_host_revision/trajectory.png) · [修订验收报告](../coordination/reports/pr47_host_interface_revision.md)。旧M1A迁移数据属于原交付检查点，操作入口以本页及新报告为准。
