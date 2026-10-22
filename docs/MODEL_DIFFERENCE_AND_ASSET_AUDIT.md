# 模型功能差异与资料核查：M0 实查

日期：2026-10-22。审计起点：`main@361c2c6`（PR #43 已合并）。

**状态：部分完成，等待 Review。** 四个源模型的结构、连接、参数和资料已核查；本地 Simple 的启动可复现性、调制标度和 M1 冻结边界仍待裁决。本轮未执行图更新、仿真、构建或模型保存，不是模型运行验收。

整合结论和 M1 建议见 [M0 报告](../coordination/reports/m0_simulink_model_asset_audit.md)，原始证据见 [证据索引](reports/m0_simulink_audit/README.md)。2026-10-21 初查中的待核项已按下列实际证据更新，未确认项没有统一改成通过。

## 1. 证据与路径约定

`M = PMLSM_MIL_ControlCore_Sim`；`C = PMLSM_ControlCore_Block/PMLSM_ControlCore`；`S = PMLSM_ThreeLoop_Simple/Control_Task_10kHz`；`D = PMSLM_Close_Loop_MBDL4/FOC_3Close_Loop_Control`；`R = PMLSM_ThreeLoop_Simple`。下表的 `C/F`、`S/F`、`D/F` 中 `F` 均为 `FOC_Algorithm`。双斜杠 `ADC//QEP` 表示块名中的一个字面斜杠，`\n` 表示块名中的换行。

- 结构/连接：实际 `load_system`、`find_system`、`get_param`，与 SLX XML/JSON 交叉检查；“存在并连接”不表示本轮执行了该路径。
- 参数：隔离进程执行已读初始化链，分别记录 base/model workspace；用 `slResolve` 验证 Simple 的遮蔽关系。
- 状态/函数：读取 Stateflow 实际状态动作、转移和 MATLAB Function 文本；没有用旧截图判断缺失。
- “未找到证据”表示在四个归档全部层级、脚本和库引用中未定位对应实现。

## 2. 功能矩阵与建议去向

| 功能 | 完整 MIL + ControlCore | Simple（本地 as-found） | DSP 实机 | 建议去向 |
|---|---|---|---|---|
| 系统/引用 | 存在并连接：`M/Control_Core/PMLSM_ControlCore_Block`（SID77，Model Reference），与启动、plant、日志 bus 相连 | 存在并连接：`R/Control_Task_10kHz`（505）；五个输出含选中 id/iq | 存在并连接：`D`（340），由 `PMSLM_Close_Loop_MBDL4/HWI_ADC_INT` 触发 | 分开算法、运行管理、plant |
| 电流 PI-FOC | `C/F/Id`（386）、`Iq`（255）存在并连接；默认 mode=2，经 `select_ud_current_mode`/`select_uq_current_mode` 旁路其输出 | 存在并连接：`S/F/Id`（566）、`Iq`（591）直接到限幅 | 存在并连接：`D/F/id`（1215）、`iq`（1380） | 首选 `S/F` 为浮点 PI-FOC 起点 |
| 其他电流算法 | 存在并连接：`C/F/DPCC_Current_Controller` 下有 DPICC、half-delay、PICDO，默认选择 DPCC | 未找到证据：`S/F` 无对应分支 | 未找到证据：`D/F` 无对应分支 | 完整 MIL 中历史保留/后续研究 |
| 坐标变换 | `C/F/Clack`、`Park Transform`、`Inverse Park Transform` 存在并连接 | `S/F/Clark`、`Park`、`InversePark` 存在并连接 | `D/F/Clack`、`Park Transform`、`Inverse Park Transform` 存在并连接 | 算法核心；保留三电流 Clarke、D-axis/rad |
| 前馈/解耦 | `C/F/Id/Product1` 减 `we*Lq*iq`；`Iq/Product1` 加 `we*(Ld*id+psi)` | `S/F/Id/Product1`、`Iq/Product1` 同符号连接 | `D/F/id/Product1`、`iq/Product1` 同符号连接 | 算法核心，不简化为两个标量 PI |
| 圆形限幅/AW | `C/F/dq_voltage_limiter`（415），`Unit Delay`/`Unit Delay1` 将误差延迟回 PI | `S/F/dq_voltage_limiter`（698）同结构 | `D/F/dq_voltage_limiter`（1340）同结构 | 算法核心，保留延迟状态与限幅顺序 |
| SVPWM/补偿 | `C/F/SVPWMG`（295）前接 `DeadTime_Compensation`；默认补偿=0，为旁路 | `S/F/SVPWMG`（618）直接接反 Park | `D/F/SVPWMG`（1256）直接接反 Park，再到 ePWM1/2/3 | 调制归核心；CPU count 换算与硬件 PWM 分开 |
| 速度/位置外环 | 存在并连接：`C/Triggered_Speed_loop`、`Triggered_Position_loop`、`Reference_Manager` | 存在并连接：`S/Speed_Loop`、`Position_Loop`、`Reference_Manager`；选中 iq 经控制任务第5输出送 co-sim | 存在并连接：`D/Triggered_Speed_loop`、`Triggered_Position_loop`、`Reference_Manager` | 共享浮点环境；首个 HDL DUT 暂不含外环 |
| 多速率/首拍 | `C/Scheduler_10k_1k_100`：加1后比较>=10，位置计数只在速度 tick 更新 | `S/Scheduler_10k_1k_100` 同结构，`R/Control_Tick_10kHz` 周期 Ts | `D/Scheduler_10k_1k_100` 同结构；电流由 ADC ISR 调度 | 可部署调度；按事件计数确定首拍 |
| 启动/对齐 | 存在并连接：`C/Angle_Init`（128），IDLE→RAMP_ID→HOLD_ALIGN→RAMP_DOWN_ID→DONE；MIL sequencer 等真实 Init_Done | 未找到证据：全层级无 Angle_Init/电零位校准；`R/Simple_Host` schedule 是仿真替代 | 存在并连接：`D/Angle_Init`（1551），HOLD_ALIGN→DONE，未含 RAMP_DOWN_ID | 运行管理；建议恢复 MIL 平滑释放并验证 |
| 轨迹/命令 | 仿真替代：`M/Startup_And_Commands/Simple_Command_Profile` | 仿真替代：`R/Simple_Host` 调 `pmlsm_scurve_profile`；本地四路 `Step7D_Interactive_*` 覆盖 speed/load/PWM/reset | `D/Reference_Manager` 读取 ExportedGlobal 命令；未找到自动 S 曲线入口 | 工况/轨迹归场景，真实命令仲裁归运行管理 |
| 使能/复位/模式 | `C/Reference_Manager`、`C/Angle_Init`、`C/F/Id/Switch`/`Switch1` 和 q 对应块；外环使能与电流环不同 | `R/Effective_PI_Reset`=reset通道 OR `PWM_Disabled`；`S/F/Id/Reset_Integral`/`Reset_Output` 和 q 对应块 | `D/Controller_Driver_IO_Manager` 控 RELCON/ENCON/OE；PI_Reset_EN 另控电流积分/输出 | 运行管理+算法复位；清故障与 PI reset 分开 |
| 积分/给定限制 | `C/F/Id/x_d_z`、`Iq/x_q_z` 零初态；速度环 `Saturation` 限积分、`Saturation1` 限 iq | 对应 d/q 状态零初态；`S/Speed_Loop/Saturation` ±0.5、`Saturation1` ±1A；`Position_Loop/Saturation` ±20mm/s | d/q 零初态；速度环 `Saturation` ±0.10、`Saturation1` ±0.30A | 算法状态/运行限制；Iq_int_limit 是速度 PI 积分限幅 |
| 参数/标定 | `M` InitFcn 分层覆盖；`C/Caculate_measurement/Theta_Offset` 读细调偏置；DSM 接命令 | MATLAB File 模型工作区；本地 `.mat` timeseries+交互回调再覆盖；未找到在线标定实现 | `D/ADC//QEP/Current_Offset_Calibration` 存在并连接；ExportedGlobal 为在线参数依据 | 分开生成常量、运行参数、标定、场景 |
| 电流反馈 | 仿真替代：`M/Power_Plant_Feedback/Sensor_Model` 三相/重构选择→`C/F/Clack` | 仿真替代：`R/PMLSM_Plant_Model` 相电流直达 FOC/co-sim | 存在并连接：`D/ADC//QEP/ADCA_Current`/`ADCB_Current`/`ADCC_Current`，校准、增益、三相/重构选择 | 物理单位适配；实 ADC 外设归板级 |
| 位置/速度/角度 | `C/Caculate_measurement` 50拍差分、IIR、饱和；`C/Triggered_Speed_loop/Speed_Feedback_Select` 默认 measured | 仿真替代：`R/PMLSM_Plant_Model` 的 v、theta、omega 经 root tag 直接送 `S` | `D/ADC//QEP/eQEP`→`Caculate_measurement`，计数转 mm、差分/IIR、偏置/对齐角选择 | 单位归接口合同；测量延迟后续显式加入 |
| ADC/编码器外设 | 仿真替代：`PMLSM_ControlCore_Block/control_tick_10k` | 仿真替代：`R/Control_Tick_10kHz`、`FPGA_HDL_Cosim`，无实 ADC/eQEP | 存在并连接：`HWI_ADC_INT` ADCA1_INT→`D`，三 ADC 触发 ePWM1_ADCSOCA | FPGA 板级适配，不复制 TI 外设 |
| PWM/死区 | 仿真替代：`M/Power_Plant_Feedback/Inverter_Model/PWM_Update_Delay` 默认旧 half-delay、accurate=0 | `R/Inverter_DeadTime`：legacy 经 `PWM_Update_HalfTs`/`Legacy_Counts_To_Duty`，FPGA duty 从另一路选择，共用一套 deadtime/plant | `D/F/ePWM1`/2/3：AHC互补、zero影子装载、RED/FED=100 | 调制/PWM调度/门极死区各自独占责任 |
| 故障锁存/关断 | `C/External_Fault_Latch` OR+delay，`C/system_fault_latch_or` 合并行程；输入非零有效，来源为 MIL 注入 | `R/FPGA_HDL_Cosim/Bridge_Valid`/`Duty_Guard1`及 fault/needs_reset 监视属于旧 co-sim；未找到等价系统故障采集/锁存 | `D/Controller_Driver_IO_Manager/External_Fault_Latch` 对低有效输入反相锁存；`D/System_Fault_Latch_OR` 合并行程；安全 AND/OE 与 ePWM TZ | 运行管理+板级独立关断，保留极性差异 |
| 恢复/行程/互锁 | `C/Travel_Safety_Manager`（591）和外部 latch 未见清锁存输入；soft±470/hard±500mm；soft只挡向外且超过1mm/s参考 | 未找到证据：无 Travel_Safety_Manager；自由运动保留；PI reset不代替系统恢复 | `D/Travel_Safety_Manager`（1463）同逻辑；FReset_Manual→GPIO66，未清软件 latch；Init_Reset/行程故障复位 Angle_Init | M1明确运行恢复协议；场景与保护分别验证 |
| plant/工况 | 仿真替代：`M/Power_Plant_Feedback/PMLSM_Plant_Model`，默认静止电流试验冻结机械状态 | 仿真替代：`R/PMLSM_Plant_Model` 自由运动；本地0.8s加0.5N、1s撤除 | 未找到证据：DSP顶层无仿真 plant，由实物承担 | 仿真对象/场景，不生成进 HDL |
| 日志/通信 | `M/MIL_Logging` 存在并连接；`C/Scheduler_10k_1k_100/UART_tick` 不等于串口实现 | `R/Motor_Control_Monitor` 与具名日志存在并连接 | obs_* / ExportedGlobal 为观测依据；`D/Scheduler_10k_1k_100/UART_tick` 存在，未找到 SCI收发/命令协议连接 | 日志归仿真；遥测/通信后续集成 |

## 3. 参数实查摘要

完整值与遮蔽证据见 [parameter_stages.json](reports/m0_simulink_audit/parameter_stages.json)，时间序列与加载后配置见 [focus_queries.json](reports/m0_simulink_audit/focus_queries.json)。

| 参数 | 完整 MIL 最后覆盖 | Simple 模型工作区 | DSP 初始化 |
|---|---:|---:|---:|
| Kp_ACR / Ki_ACR | 4.3625 / 5925 | 8.725 / 11850 | 2.18125 / 2962.5 |
| Ki_ACR*Ts_ACR | 0.5925 | 1.185 | 0.29625 |
| Kaw_d / Kaw_q | 0.2 / 0.2 | 0.1358166189 / 同左 | 0.2 / 0.2 |
| Kp_ASR / Ki_ASR / Kaw_s | 0.03 / 0.05 / 0.4 | 0.01803347485 / 1.442677988 / 0.08 | 0.03 / 0.05 / 0.4 |
| Kp_pos / 位置环速度限幅 | 5 / 10mm/s | 22 / 20mm/s | 5 / 10mm/s |
| 速度积分 / 输出iq限幅 | 0.10 / 0.30A | 0.5 / 1A | 0.10 / 0.30A |
| 电流/速度/位置周期 | 100us / 1ms / 10ms | 同左 | 同左，电流由ADC ISR触发 |
| plant/solver步长 | 100us / 100us | 1us / 1us（本地） | 无plant；solver=Ts=100us |
| 平均逆变器count分母 / ePWM TBPRD | 7500 / 无实外设 | 10000 / 无实外设 | 无平均逆变器 / 5000 |

三者 Rs=2.37Ω、Ld=Lq=1.745mH、ψ=0.141Wb、标称Udc=48V。极距30mm与完整电周期60mm要区分。所有数值保持原状。

## 4. 资产与依赖结果

- MIL、ControlCore、DSP 三个 SLX 与主线/外部源字节一致；本地 Simple 与二者均不同，保留未覆盖。DSP参数脚本仅换行格式不同。
- 已同步五个被引用文件：MIL说明、测试流程、硬件接口图、PWM极性说明、`init_PMLSM_MIL_params.m`；另补PI离散式、对齐释放、传感器三份说明。详见 [同步清单](reports/m0_simulink_audit/sync_manifest.json)。这些原文的历史默认值/路径不覆盖本次实查。
- 硬件本地位于 `硬件说明/`，远端仍在根目录；ACM本地名为 `ACM9238-SCH-ADC模块.pdf`。PDF/ZIP字节一致；两TXT归一换行后一致；XLSX全部非空单元格坐标和值一致。保留用户移动状态，不重复上传，不提交根目录删除。
- 四模型无SLDD。Motor Control、C2000、HDL Verifier库实际可解析；未找到自定义库/类缺项。`vivadosimlib`可定位不等于XSI runtime已重新构建。
- 九个已跟踪XPR的131个File引用均存在，仅FOC_Current可选`.wcfg`未跟踪。另一本地未跟踪Study_L1 XPR的5个引用均存在，约束/TB有已入库原件。源RTL/XDC与Tcl入口保持原位。
- 本地Simple初始化新引用的`.mat`包含timeseries；远端初始化不引用它。保留这对本地修改，不单独上传MAT制造远端运行基线。缓存、slprj、build/runs均未纳入。

## 5. 未决项

1. 本地Simple交互InitFcn依赖进程状态；fresh进程状态为空，PreLoad又设backend=1。M1需先冻结可独立启动的纯Simulink入口。
2. 原SVPWM都用200MHz CPU_Clock换算；旧Step6A记录零电压为5000原始counts。完整MIL分母7500、DSP TBPRD5000、Simple分母10000不能混用。本轮没有重跑该数值测试；建议M1定义归一化调制边界并保留旧counts对照。
3. 已恢复ADC型号/总线、编码器与驱动板端口；未找到完整FPGA电机线缆到封装引脚XDC，AD9238双通道和DSP三相独立采样的适配尚未确定。影响M5/M6，不阻塞M1，也不要求用户重复填写接口表。
4. R2026b六个变换的外层/Lookup MaskWS N_points均为1024；未更新图，dlgSett未求出。旧R2026a的800区间结果只作历史记录，M1补最小数值检查。

本轮不创建正式模型、不定点化、不生成HDL。后续路线为 Simulink → HDL Coder；M1建议经Review后才执行。
