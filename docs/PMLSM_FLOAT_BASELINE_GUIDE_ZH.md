# 纯 Simulink PI-FOC 浮点基线

使用 MATLAB/Simulink R2026b 和 Motor Control Blockset。正式入口为新模型 `PMLSM_PI_FOC_Float_Baseline`；原 Simple、MIL、ControlCore、DSP 模型保留。

## 打开并运行

在新 MATLAB 窗口执行：

```matlab
addpath('D:/Project/FPGA_XC7A200T/simulink模型');
init_PMLSM_PI_FOC_Float_Baseline;
open_system('PMLSM_PI_FOC_Float_Baseline');
out = sim('PMLSM_PI_FOC_Float_Baseline');
```

也可以初始化并打开后点击 Run。默认是 1 mm 位置给定，0.05 s 开始 S 曲线，仿真 1.2 s，零外负载、1 us 平均死区。查看 `out.logsout` 中的 `x_mm`、`v_mmps`、`id`、`iq` 等记录；原有 Motor_Control_Monitor 仍保留。旧 FPGA 专用监视通道固定为零，不表示硬件结果。

未显式初始化时会提示 `init_PMLSM_PI_FOC_Float_Baseline`。模型 InitFcn 只检查参数，不加载脚本或重新覆盖工况。Model Workspace 为空，实际参数来自 Base Workspace。

## 修改工况与参数

正式默认值集中在 [初始化脚本](../simulink模型/init_PMLSM_PI_FOC_Float_Baseline.m)。编辑该文本后重新执行脚本，再运行模型。重复执行会恢复该脚本的所有默认值；请在初始化之后设置本次临时工况。

负位置工况：

```matlab
init_PMLSM_PI_FOC_Float_Baseline;
Host_Target_mm = -1;
out = sim('PMLSM_PI_FOC_Float_Baseline');
```

独立负载阶跃（0.8 s 加 0.5 N，1.0 s 撤除）：

```matlab
init_PMLSM_PI_FOC_Float_Baseline;
M1A_Load_ts = M1A_LoadStep_ts;
out = sim('PMLSM_PI_FOC_Float_Baseline');
```

速度工况：

```matlab
init_PMLSM_PI_FOC_Float_Baseline;
Host_Enable_Schedule = [0 1 0 1]; % time / speed-enable / position-enable / host-PWM
M1A_Speed_ts = timeseries([10;10],[0;M1A_StopTime_s]); % mm/s
out = sim('PMLSM_PI_FOC_Float_Baseline');
```

电流工况保留自由机械运动：设置 `Host_Enable_Schedule=[0 0 0 1]`、`Host_Iq_Test_Mode=1`、`Host_Iq_A=0.2`（或负值），然后仿真。

实际负载、速度、PWM 使能及额外 PI 复位分别由 `M1A_Load_ts`、`M1A_Speed_ts`、`M1A_PWM_ts`、`M1A_Reset_ts` 输入，均零阶保持。这些输入替代来源中已闲置的 Host 同类输出；修改 `Host_Speed_mmps/Host_Load_N/Host_PI_Reset_EN` 不会改变这三路实际输入。关闭 `M1A_PWM_ts` 会禁止平均电压，并通过原有 OR 逻辑复位电流 PI。

理想逆变器对照：同时设置 `PMLSM_deadtime_s=0; PMLSM_deadtime_ratio=0;`。默认恢复可再次执行初始化脚本。

## 单位、时基与调制

内部机械量 m、m/s；外环/显示 mm、mm/s。电流 Apeak、电压 V、电角度 rad、电角速度 rad/s。相电阻 2.37 ohm，Ld=Lq=1.745 mH，磁链 0.141 Wb，质量 0.91 kg，推力系数 31.4/sqrt(2) N/Apeak，完整电气空间周期 0.06 m，母线默认 48 V。

电流/PWM 100 us，速度 1 ms，位置 10 ms，plant 1 us；持续使能时首次速度/位置事件为 0.9/9.9 ms。`duty_u_cmd/v_cmd/w_cmd` 是死区和应用更新之前的上管高电平比例，零矢量为各 0.5。只有一次 50 us 更新延迟和一次平均死区。

步长核对时同时修改 `Ts_Plant` 和别名 `PMLSM_Ts_s`，例如都设为 `0.5e-6`；控制周期、PWM 更新和平均死区保持不变。

## 复现验证

在独立批处理进程运行，避免影响桌面上其他模型和工作区：

```powershell
& 'D:\Program Files\MATLAB\R2026b\bin\matlab.exe' -batch "addpath('D:/Project/FPGA_XC7A200T/scripts'); m1a_verify_float_baseline('all')"
& 'D:\Program Files\MATLAB\R2026b\bin\matlab.exe' -batch "addpath('D:/Project/FPGA_XC7A200T/scripts'); m1a_fresh_float_baseline"
```

`all` 包含结构、初始化/变量生效、实际调制/PI/时序、九个源 backend0 迁移场景和一个步长对照。`m1a_fresh_float_baseline` 把新 SLX、初始化、只读检查函数及两个计算函数复制到新的隔离目录，运行完整默认工况；可用两个独立进程复核重复性。新模型运行不需要旧 MAT、XSI、prepare 或 CONTROL_BACKEND；迁移验证的源侧按原来源加载，只在内存配置后仿真并不保存。

[结果索引](reports/m1a_float_baseline/README.md)与[实施报告](../coordination/reports/m1a_pure_simulink_float_baseline.md)说明实际结果、阈值和未验收范围。M1A 没有生成 HDL/C，没有运行 Vivado 或操作硬件；启动保护/恢复属于后续 M1B，定点 HDL 属于 M2。
