# M0 — Simulink 模型功能、参数与资产审计

日期：2026-10-22。分支：`codex/m0-simulink-model-asset-audit`。基线：`origin/main@361c2c6`，含已合并 PR #41、#43。

**状态：部分完成，提交开放 PR 等待 Review。** 完整 MIL、ControlCore、Simple、DSP 的结构/参数审计和所需说明补齐已交付。调制标度、Simple 独立启动基线和 M1 范围仍有明确未决项。本轮未改变算法，未证明三模型动态等价或可上机运行；不自动进入 M1。

## 1. 源版本、工作区保护与执行范围

实际目录仅 `D:/Project/FPGA_XC7A200T`，外部 `D:/Project/PMSLM_Simulation` 只读。开始时分支为 `codex/study-l1-checkpoint-d@9115280`；本地 main 为 `74f6128`、旧 origin/main 为 `199eecb`。Git直连两次失败后，读取已有Windows代理配置，以单次 `git -c http.proxy=http://127.0.0.1:7897 fetch origin main` 成功取回 `361c2c6`。未修改全局Git/PATH/MCP配置。

确认文档PR #43已合并、入口文档无本地修改后，用非强制 `git switch -c codex/m0-simulink-model-asset-audit origin/main` 建立分支。当前本地主分支引用未强行移动；审计工作从更新后的main提交开始。无clone/worktree、stash、reset、clean或文件删除。初始已有tracked修改/根目录硬件删除状态、untracked模型数据与历史结果全部保留。

| 对象 | as-found版本与处理 |
|---|---|
| MIL / ControlCore / DSP SLX | 与`361c2c6`及外部源字节一致；未改写 |
| Simple SLX | 本地556658字节，与主线/外部源均不同；没有保存或提交这份用户修改 |
| Simple初始化 | 本地2026-09-30导出脚本3055字节，引用本地未跟踪MAT；主线为独立参数计算脚本；两者均保留，没有相互覆盖 |
| DSP参数脚本 | 与外部源一致；与Git内容只存在换行格式差异，无语义修改 |
| 硬件资料 | 根目录原路径呈用户删除状态，实际文件位于`硬件说明/`；不提交移动/删除，不重复上传 |
| 仿真结果、XPR、Study模型、slprj等 | 原样保留，不混入本轮提交 |

工作区证据保存在本地`.superpowers/m0_20261022/`：`status_before.txt`、`head_before.txt`、`user_before.patch`，以及六个明确源文件的审计前字节快照。审计后用同一路径的Git二进制diff逐字节对照原patch、检查原untracked路径仍在、比较模型/脚本快照；不以文件哈希作为功能验收。

工具实查：MATLAB `26.2.0.3386108 (R2026b)`，路径`D:/Program Files/MATLAB/R2026b/bin/matlab.exe`；Motor Control Blockset、C2000 Microcontroller Blockset、HDL Coder、HDL Verifier、Fixed-Point Designer均安装26.2，AMD FPGA/SoC支持包26.2.3。详见[环境](../../docs/reports/m0_simulink_audit/tool_environment.json)。Vivado路径`E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat`；`-version`输出2026.1/Build6511674，但该版本命令退出码为1，只作为版本banner证据，不声称Vivado项目检查通过。

独立`-batch`进程完成加载/查询/参数脚本执行；没有清空或关闭用户MATLAB会话。已有用户startup中的SATK连接检查在独立进程自动执行，未更改其配置。回调与脚本在加载前静态读取：MIL的InitFcn调用DSP参数链（含`clear; clc`），故只在隔离进程base执行；DSP无模型初始化回调；Simple PreLoad仅设旧co-sim参数，InitFcn需要交互状态，未执行。标准MCB/C2000库mask由工具加载，未调用代码生成、外设初始化或硬件控制。

## 2. 模型差异、功能语义与候选源

逐项矩阵见[已更新核查表](../../docs/MODEL_DIFFERENCE_AND_ASSET_AUDIT.md)，包含准确block path、SID、连接、状态和迁移去向。证据可查[层级CSV](../../docs/reports/m0_simulink_audit/model_hierarchy.csv)、[关键块与输入连接](../../docs/reports/m0_simulink_audit/key_blocks.json)、[Stateflow/函数](../../docs/reports/m0_simulink_audit/stateflow_semantics.json)。不根据模型大小、名称或时间戳判断哪套更正确。

采用核查表的M/C/S/D/R/F路径缩写，关键结论如下：

1. **首个PI-FOC候选是`PMLSM_ThreeLoop_Simple/Control_Task_10kHz/FOC_Algorithm`。** `Clark→Park→Id/Iq→dq_voltage_limiter→InversePark→SVPWMG`存在并连接。保留Simple的复位输出/积分状态、已选中外环id/iq输出、自由运动plant、共享平均逆变器、归一化FPGA入口、外环速度积分/输出限幅、零参考时不抹去平衡积分、S曲线与具名日志。`Host_Iq_A`不是三闭环下速度PI输出的替代品。
2. 完整MIL的`M/Control_Core/PMLSM_ControlCore_Block`是真实Model Reference。核心PI在`C/F/Id`、`Iq`，但默认`Current_Control_Mode=2`，两个阈值1.5的mode开关选DPCC；PI分支存在不代表默认输出来自PI，也不代表其并行状态停止更新。DPICC/PICDO保留研究，不加入首次HDL范围。
3. 三套dq PI的离散结构一致：`ud_raw=Kp*ed+xd-we*Lq*iq`，`uq_raw=Kp*eq+xq+we*(Ld*id+psi)`；`x_next=x+Ki*Ts*e-Kaw*du_z`。`du_z`为前拍raw-minus-limited；不是当前拍无延迟回算。限幅系数为`min(1,0.9*Udc/sqrt(3)/(sqrt(ud_raw^2+uq_raw^2)+1e-6))`。d/q积分初态为0，PI reset清积分与输出；限幅器的延迟记忆不能自动认为也具有同样reset语义。`Iq_int_limit`实际作用于速度PI积分，不是电流PI独立钳位。
4. **对齐释放有实质差异。** MIL核心Stateflow含`RAMP_DOWN_ID`，保持对齐角、用2000拍将0.5A降到0后DONE；DSP状态图HOLD_ALIGN后直接DONE，虽然参数文件也定义了`Id_Release_Ramp_Ticks`。两个模型都保持Ramp10000拍/Hold30000拍、由对齐位置锁存计算电角偏置。Simple没有对应实际对齐状态机，以理想plant角度代替。
5. MIL/DSP都有行程管理：hard±500mm锁存，soft±470mm只阻止继续向外且超过1mm/s阈值的速度参考。它们不是一个完整减速规划器。外部故障/行程故障合并；软件锁存未见复位端口。DSP的`FReset_Manual→GPIO66`清驱动器故障命令不能清上述软件锁存，`PI_Reset_EN`也不能代替系统恢复；该事实需进入M1协议设计。Simple旧co-sim的fault_code/needs_reset只覆盖旧核心协议，不等于DSP系统保护。
6. 完整MIL默认静止电流试验（机械状态冻结），Simple自由运动；DSP无仿真plant。测量链也不同：MIL/DSP的位置差分50拍+IIR用于速度，Simple直接用plant理想v/omega/theta。当前MIL速度选择`Speed_Feedback_Mode=1`，不能把Simple理想速度当成真实测速已验证。
7. DSP中`Scheduler_10k_1k_100/UART_tick`存在，但没有追到SCI收发块/命令协议。`obs_*`为导出观测变量依据；不能把调度tick或参数声明写成通信实现完成。

### 本地Simple与主线的具体差异

[保存结构对照](../../docs/reports/m0_simulink_audit/simple_as_found_vs_main.json)显示本地新增四个From Workspace源：`Step7D_Interactive_speed/load/pwm/reset`，分别替换Simple_Host第7/3/6/11输出到`Publish_host_v_ref_mmps`、`Publish_load_N`、`Publish_PWM_EN`、`Publish_PI_Reset`的连接；内部FOC和外环未发现对应结构/参数改动。co-sim PortTimes的文本表示从`1e-06`变成长十进制，数值相同。这不是宣称全部SLX元数据或动态行为等价。

本地InitFcn为`reload(ModelWorkspace); pmlsm_interactive_cosim_init(bdroot);`；远端只有reload。本地参数脚本从`init_PMLSM_ThreeLoop_Simple.mat`取七个timeseries；主线脚本不依赖MAT。当前实际场景：位置目标1mm、起始0.05s、Vmax5mm/s、Amax50mm/s²；speed=0、PWM=1、reset=0；load在0.8s加0.5N、1s撤除，StopTime1.2s。不能只引用Host_Load_N=0来描述有效负载。

fresh进程`pmlsm_interactive_cosim_state('get')`确为空；InitFcn中的assert要求先prepare。本轮只读该状态，未调用InitFcn、未prepare或初始化XSI。故这份本地保存模型不能声称在新进程直接Run即可复现。模型+脚本+MAT+交互准备配置应整体冻结，不能只提交MAT或覆盖远端参数脚本。

## 3. 参数覆盖、时序和关键语义

原始[参数分阶段导出](../../docs/reports/m0_simulink_audit/parameter_stages.json)和[加载/时间序列证据](../../docs/reports/m0_simulink_audit/focus_queries.json)分清以下优先关系：

- DSP手动执行`PMSLM_Init_Params_MBDL4`写base并清原调用空间；仅声明ExportedGlobal不证明运行中外部已经写过。
- MIL InitFcn顺序为control→plant→mil_test：control先恢复DSP增益，plant设独立对象参数，mil_test最后把电流PI覆盖成完整基准、Udc覆盖成MIL_Vdc、默认算法改为2。预先在base设mode=1会被该回调覆盖；M0未改默认模式。
- Simple模型工作区来源为MATLAB File。实际`slResolve`在MIL base已经装载后仍返回Simple的Kp=8.725/Ki=11850等值，证明同名模型变量遮蔽base。InitFcn会reload，之后交互init再写host/timeseries和base backend；场景脚本/SimulationInput的作用域和回调先后不能合并成“最后执行的任意变量都生效”。
- 正常层级优先还需考虑mask局部变量。本轮核查已存参数表达式和库mask；未执行图更新，不声称全部编译类型/调度已解析。未发现SLDD或额外ModelWorkspace数据文件依赖，只有上述Simple MAT配对。

| 类别 | 完整MIL最后值 | Simple模型工作区实际值 | DSP初值 |
|---|---|---|---|
| 电机 | Rs2.37Ω；Ld=Lq1.745mH；ψ0.141Wb | 同左；M0.91kg；Kf=31.4/√2=22.2031529293N/Apeak | 同电气参数；无仿真机械对象 |
| 电流PI Kp/Ki/KiTs | 4.3625 / 5925 / 0.5925 | 8.725 / 11850 / 1.185 | 2.18125 / 2962.5 / 0.29625 |
| 电流Kaw_d/q | 0.2 / 0.2 | 0.1358166189111748 / 同值 | 0.2 / 0.2 |
| 速度PI Kp/Ki/KiTs/Kaw | 0.03 / 0.05 / 0.00005 / 0.4 | 0.0180334748526811 / 1.44267798821449 / 0.00144267798821449 / 0.08 | 同MIL |
| 位置P/死区/限速 | 5 / 0.02mm / 10mm/s | 22 / 0.02mm / 20mm/s | 同MIL |
| 速度积分/输出iq限制 | ±0.10 / ±0.30A | ±0.5 / ±1A | 同MIL；不限制对齐id的0.5A |
| 标称母线/电压圆限幅 | 48V / 24.9415316V（0.9×48/√3） | 同左 | 同左；没有在线Vdc采样进入控制器 |
| 周期 | 电流100us；速度1ms；位置10ms | 同左 | 同左；Ts_SCI=1ms只是参数 |
| 角度/位置 | mm，mm/s，rad；完整周期60mm，极距30mm；mod到2π并加零偏/对齐选择 | plant x先以m积分、转mm；theta=2πx/0.06m | (QPOSCNT−2147483648)×0.0001mm/count；再按60mm转电角 |
| 电流标定 | 仿真三相采样/可选重构 | 理想物理量，无实际ADC标定 | OffsetA/B/C2253，Gain0.01664A/count，Three_Current_Sampling_EN=true；仅理论/调试初值 |
| Vdc标定 | 场景48V | 场景48V | 3.0/4096V/count、倍率20已定义，但ADCD0未接入 |

调度器速度计数初态0，当前值加1后比较>=10；在相关使能持续成立、没有复位/保持时，第10个电流事件产生首个速度tick。位置计数按速度tick累加，第100个电流事件产生首个位置tick。在这些条件下，FunctionCallGenerator从StartTime=0起触发时推得0.9ms/9.9ms；DSP绝对首个ISR时刻由硬件采样相位决定，本轮无实测，不写死成同一个绝对时间。

严格区分：MIL solver/plant默认100us；Simple本地solver/plant1us、电流100us；legacy PWM半周期延迟50us；旧co-sim HDL时钟20ns/50MHz、事务100us、块内交换端口1us、reset200ns、prerun0。PreLoad后实际base同时有`FPGA_Cosim_Ts_s=50us`和`STEP7C_Comm_Ts_s=1us`，backend=1；交互prepare才会重写配置。本轮没有把这些未经prepare的混合设置当成已运行合同，也没有改成backend0。

**count/极性待决：** 三套SVPWM的`Duty\nCalculate/Gain*`仍乘`CPU_Clock=200MHz`，该变量不是FPGA fabric时钟。Simple count分母10000；完整MIL平均逆变器分母7500；DSP ePWM时基100MHz、TBPRD5000。旧Step6A在其源版本测得零电压原始输出5000counts，本轮仅确认相关结构/参数仍在，不重跑其数值验收。Simple legacy转换为`1-CMP/10000`；旧FPGA入口为`CMP_active/2500`。两种极性和尺度属于各自已验证边界，不能把2500/旧RTL位宽直接继承成新合同。

平均逆变器的legacy半周期延迟与硬件shadow装载描述同一类更新责任；FPGA归一化duty入口绕开legacy延迟/极性后，只有一套平均死区。DSP ePWM RED/FED1us则是实际门极死区。如果未来把生成RTL、旧PWM、平均死区模型全部串接，必须防止重复延迟/死区，本轮没有修改任何一路。

MCB库在R2026b实际可定位，六个Park/反Park外层和Lookup MaskWS N_points都是1024，D-axis、Two inputs、Electrical position、Radians。没有update时内部dlgSett为空；不能宣称已证明实际插值精度。旧Step6A R2026a实测800区间是历史证据，M1只补当前选定库版本的最小变换数值检查。

## 4. 硬件接口依据与真正缺项

硬件资料[映射清单](../../docs/reports/m0_simulink_audit/hardware_assets.json)记录远端根路径、本地路径与比对结果。以下页码为PDF从1开始的物理页码；驱动板说明书印刷页码比PDF页码少5。已逐页提取相关文字，并渲染核对ACM原理图p1、驱动板端口表p11；未下载第三方软件。

| 接口 | 已找回的依据 | 已确认的含义 / 边界 |
|---|---|---|
| BX72时钟/串口/扩展 | `BX72-251215.pdf` p1、p12/p13；`BX72管脚分配表V2.1.xlsx` Sheet1；现有Step5A XDC | FPGA_CLK=Y18/50MHz；USB_UART_RX=N13、TX=N14；GPIO0/1扩展信号有板卡引脚表。这些资料未标注电机线缆功能，不能猜ADC/PWM/编码器封装引脚 |
| FPGA侧ADC | `ACM9238-SCH.pdf` p1，本地`ACM9238-SCH-ADC模块.pdf`；旧Step6架构说明明确ACM/AD9238 | U2=AD9238，双通道、每通道D[11:0]+CLK+OTR，3.3V数字供电。P1: CH1_CLK=2、CH1_OTR=13；CH2_CLK=32、CH2_OTR=31；P1数据交错排列。图中CH1对应芯片B数据、CH2对应A数据，不能由CH1直接推定相A |
| MBDL4模拟输出 | `YXPHM-MDBL4电机驱动板硬件说明书.pdf` p11表2-2、p16/p17图3-8/3-10；驱动板原理图p1 | 1=IA、2=IB、3=IC、4=IDC、5=VDC、6=TEMP；CC6903标称VCC/2+0.044×I，母线倍率20。DSP的2253/0.01664是特定3V ADC初值，不能直接给AD9238复用 |
| MBDL4数字输入/反馈 | 同说明书p11表2-1、p20/p21；`MDBL4转接板.pdf` p1 | 数字26针：1..6=PWM1..6，7=RELCON，8=ENCON，9=F_Reset，19=ERRI，20=ERRU，21/22/23=QEPA/B/Z，25/26=GND。ENCON/RELCON高有效，ERRI/ERRU低有效；不是DSP底板J5的针号 |
| 编码器 | 说明书p12表2-3、p21/p22；接口图；DSP eQEP1 mask | 已有ABZ接口/差分与单端跳帽路径、缓冲电路、0.1um/count换算；实际方向、电零位与FPGA线缆映射未有本轮实测 |
| DSP ADC映射 | 已同步`PMLSM_Hardware_Interface_Map.md`与DSP `D/ADC//QEP` mask；`28388至尊底板V1.1.pdf` p1 J9 | IA=ADCA0/J9-26，IB=ADCB0/J9-20，IC=ADCC2/J9-12；ADCD0/J9-8为计划Vdc，当前未接；ePWM1 SOCA触发，ADCA1_INT进入控制任务；采样窗口24。这是DSP映射 |
| DSP PWM | `D/F/ePWM1/2/3` mask，DSP接口图、底板p1 | GPIO0..5；up/down、TBCLK100MHz、TBPRD5000、CMPA在zero影子装载；AHC、RED/FED100=1us；SOCA在PRD。TZ1/TZ2 one-shot强制A/B低；未重建C输出验证XBAR |
| DSP使能/故障 | `D/Controller_Driver_IO_Manager` mask/连接，接口图；底板p1 U10/J5 | GPIO30低有效OE；GPIO62/63/66=RELCON/ENCON/F_Reset，对应底板J5-1/2/6；GPIO67/68=ERRI/ERRU，J5-7/8。系统fault抑制RELCON/ENCON并禁止OE。接口图记录GPIO68→TZ1、67→TZ2，为历史配置依据 |
| 通信 | BX72引脚表/原理图及DSP模型全层级查询 | FPGA USB UART板卡脚已给定；当前控制命令协议/寄存器映射未找到实现，不由UART_tick或vendor网络例程推断 |

现有硬件型号、驱动板端口、电流标定来源和编码器换算已经恢复，无需用户重填接口清单。查过仓库coordination/docs/scripts/RTL/XDC、原始PMSLM说明与模型、全部硬件文件、vendor ZIP条目和本地XPR后，仍未找到**完整电机线缆→BX72扩展口→FPGA封装引脚的已签定映射/电平适配记录**，也没有已实现的AD9238采样时序约束。双通道ADC与DSP三相独立采样的选择/重构方案仍未明确；不能默认为三通道。这些影响M5/M6板级集成，不阻塞M1使用物理单位反馈的浮点控制器。

## 5. 资料同步和工程依赖

`eb89a3d`单独提交8个缺失源资料：[同步清单](../../docs/reports/m0_simulink_audit/sync_manifest.json)逐项记录来源、目标、字节数、用途和未覆盖策略。五个任务指定候选均在原始目录找到；另外三份是PI离散式、对齐释放和传感器说明。全部原样复制，没有改外部源。旧说明中的`.../d`等路径、旧默认Plant_Input_Mode/冻结模型名只属历史记录，准确路径/有效值以本报告为准；未为历史引用补造模型或脚本。

| 依赖组 | 结果和处置 |
|---|---|
| Model Reference | MIL唯一模型引用解析到已入库ControlCore；无需复制外部备份 |
| 库/字典/辅助函数 | Motor Control、C2000、scheduler、HDL Verifier库可定位，查询模型中无unresolved库；无SLDD；S曲线/设计函数和交互辅助脚本已入库；未找到必须补的自定义类 |
| Simple本地MAT | 当前本地初始化的真实依赖，7个timeseries已读取；远端参数脚本不引用，故保留本地不单独提交。未把用户本地SLX/MAT/初始化混入资料同步 |
| 原始MIL库模型 | 外部`PMLSM_MIL_Library_Sim.slx`是独立组件试验入口；实际MIL plant/sensor为内嵌子系统，无live link，当前引用闭包不需要它 |
| 历史备份/冻结模型 | 旧说明引用的FullStartup_OK、F28335备份等不在当前Model Reference闭包，非本轮必需；保留原始目录现有备份 |
| 九个已跟踪XPR | [131个File引用](../../docs/reports/m0_simulink_audit/xpr_sources.json)本地均存在，源RTL/XDC已入库；FOC_Current未跟踪wcfg只影响波形显示，不是仿真源依赖；没有打开工程/运行Vivado构建 |
| 本地Study_L1 XPR | 5个引用均存在；复制来的约束/TB有learning下已入库原件，现有Tcl可重建，不上传整个本地工程 |
| 可重建入口 | `scripts/step3_synthesis.tcl`、`step4_implementation_timing.tcl`、`step5a_bx72_build.tcl`、`step5b_bx72_build.tcl`、`step6b_motor_pwm_build.tcl`、`step6c1_foc_transforms_build.tcl`、`step6c2_pi_build.tcl`、`step6c3_svpwm_build.tcl`、`step6c4_foc_build.tcl`、`step6d_foc_pwm_build.tcl`、`step6e_gate_build.tcl`及learning重建入口均保留，不执行 |
| co-sim runtime | HDL Verifier及AMD支持包已安装，旧构建/prepare入口存在；没有重建XSI DLL或验证其当前二进制可运行性 |
| 硬件资料 | 所有既有资料已在远端；本地仅移动/改名、换行或XLSX容器差异，语义内容一致，无须重复入库 |

本轮没有上传.slxc、slprj、.Xil、build/runs、工具安装、凭证或许可证文件。报告是依赖定位和加载证据，不能把“文件已入库”解释为“完整项目构建已通过”。

## 6. M1 范围建议（待Review，不执行）

建议首先使用实际`PMLSM_ThreeLoop_Simple/Control_Task_10kHz/FOC_Algorithm`，参照`C/F`与`D/F`解释差异。该Simple内层与主线结构对应，保留当前ξ=1/√2增益，不用DSP调试参数或MIL默认DPCC覆盖。完整MIL仍提供系统级启动/测量/保护参照；DSP提供可部署运行管理与板级语义，不整套复制为DUT。

1. **先冻结浮点入口。** 记录本地/主线两个版本、所有场景值和callback覆盖顺序，建立明确的backend0纯Simulink场景入口与独立参数/命令接口。修复交互状态依赖属于M1经批准的工作，本轮未做。保留原Simple作为回归和演示环境，新的共享控制器边界以模块/引用关系评审，不创建正式新文件名。
2. **算法边界。** 物理单位输入为同步ia/ib/ic[Apeak]、theta_e[rad]、omega_e[rad/s]、id_ref/iq_ref[A]、Vdc[V]、enable/reset/sample-valid。输出先定义vd/vq及归一化三相调制量/valid；保留原raw-counts输出作为对照适配。单位/范围、同拍反馈、old-state PI、延迟AW、复位优先级和参数更新生效拍先写合同。不要把旧2500/24bit或旧hand-SV调度器当先决条件。
3. **运行管理与场景分开。** Simple的S曲线、故障注入、负载和日志属于场景；对齐、使能仲裁、故障锁存、复位/重启、运行限幅与测量有效性属于可部署管理。M1优先明确停机清状态/禁止无复位重启协议，恢复MIL对齐渐降及故障/行程的代表性管理验证；自由运动工况不因恢复保护被全局锁死。真实ADC校准、eQEP/PWM/TZ/OE留板级适配，通信/实机参数写入留后。
4. **浮点与HDL实现分开。** 浮点基线保持数值算法；M2再建立独立定点控制器实现，标明每个运算与状态范围、位宽、舍入、饱和、参数格式和valid/latency。DUT候选覆盖Clarke/Park、dq PI/前馈、圆限幅、反变换、SVPWM；PWM载波/影子装载/六路死区故障门控独立。流水线深度、格式、新SLX名仅在设计评审后确定，本轮不创建或生成。
5. **公共环境。** 电机、平均逆变器、plant步长、场景、日志和比较口径由共享环境维护；浮点/定点/生成RTL接相同物理接口。外环先作为共享浮点环境保留；不重新维护浮点/HDL Coder/手写SV三套生产算法。

DPCC/DPICC/PICDO、死区电压补偿研究、真实测量滤波延迟接入后的整定、通信协议、板级外设和上机属于后续阶段。已有手写RTL只用于学习、数学/边界向量与时序回归参照；是否复用某个PWM/接口模块须单独评审，不要求正式FOC继续扩展手写电流环。

### 复用测试与最少新增检查

- 复用Step6A PI/变换/限幅/SVPWM数学向量及来源记录；参数/库版本/调制边界不同时先说明适用范围，不强求新浮点与旧位宽逐bit一致。
- 复用Step7C/7D的自由运动、正负电流/速度/位置、单一死区、stop/reset/重启限制、步长收敛用例设计，以及StudyL1已验证的速度PI边界语义；旧通过结果保留为历史，不声称本轮重测。
- M1只新增/重做受影响检查：新进程backend0启动；真实参数覆盖/场景选择；六个变换在选定库版本的最小数值点；旧counts与归一化调制零矢量/六扇区/边界对照；PI复位与AW前拍记忆；对齐渐降/停机/故障锁存/恢复/软硬行程；改动前后同工况输出对照。
- M2/M3之后才做定点误差、生成RTL一致性与延迟验证；M4再做真实实现延迟闭环。无需重跑全部Step6/7/StudyL1。

Review只需裁决两个当前问题：①是否接受Simple当前PI-FOC为M1算法源，并在M1显式建立backend0/可复现入口；②是否接受“归一化调制+旧counts适配对照”的新边界，以及MIL渐降对齐/独立恢复协议的优先级。板级线缆映射在M5前补具体缺项，不用它阻塞M1，也不要求用户重讲已有接口。

## 7. 验证、限制与停止条件

实际命令（从原目录执行；Python静态导出使用本机Python，PDF/XLSX读取使用Codex bundled Python）：

```powershell
python scripts/m0_static_audit.py
& 'D:\Program Files\MATLAB\R2026b\bin\matlab.exe' -batch m0_readonly_model_audit -sd 'D:\Project\FPGA_XC7A200T\scripts' -logfile 'D:\Project\FPGA_XC7A200T\.superpowers\m0_20261022\matlab_batch.log'
& 'D:\Program Files\MATLAB\R2026b\bin\matlab.exe' -batch m0_focus_queries -sd 'D:\Project\FPGA_XC7A200T\scripts' -logfile 'D:\Project\FPGA_XC7A200T\.superpowers\m0_20261022\matlab_focus_final.log'
git diff --check
```

| 验证层级 | 真实结果 |
|---|---|
| 静态归档 | 四模型579/1310/1095/736个保存块；回调、函数、状态图、模型引用、库链接和关键连接已导出 |
| 第一次加载查询 | 四模型loaded=1、Dirty加载/查询均off；579/1285/1031/736个查询块；Simple提示默认find_system不遍历全部variant |
| 追加allVariants查询 | ControlCore1285、Simple1070、DSP736；Dirty均off。XML包含保存的链接内部内容、runtime按FollowLinks=off，块数不同不用于等价性验收；MIL579不含引用模型内部 |
| 参数链 | DSP→MIL覆盖值、Simple模型工作区和`slResolve`、七个timeseries、加载后base配置均有实际导出 |
| 库数值内部 | six transforms mask N_points1024；未update，dlgSett为空，数值插值仍待验证 |
| 文档同步 | 8个新增文件与只读原始源字节一致；没有覆盖同路径文件 |
| XPR依赖 | 10个本地工程136个File引用均存在，其中9个工程已跟踪；未执行构建 |
| 源保护 | 按原用户路径对比Git二进制patch与六个源快照；原untracked路径仍存在；最终提交只含资料、审计脚本、精简证据和文档 |
| 文档一致性 | 7个入口/交付文档本地链接可定位；72个显式矩阵block path在归档/查询导出中均可定位；JSON可解析，Python审计脚本AST检查通过 |
| 代码检查 | MATLAB Code Analyzer：两个新增MATLAB审计入口无语法执行失败；主导出脚本有6条逗号/无效抑制注释样式提示，focus无提示，未写成零警告 |

第一次focus试用了Windows运行时不识别的`-nouserpath`，收到警告后参数被忽略，查询仍完成；随后去掉该参数重跑focus，最终采用`matlab_focus_final.log`和对应JSON。首次主导出后脚本补了allVariants选项，实际全variant数量由追加focus核实，不把首轮1031冒充全variant数量。两个最终MATLAB进程均退出0，日志分别有`M0_READONLY_QUERY_COMPLETE UPDATE=0 SIM=0 BUILD=0 SAVE=0`与`M0_FOCUS_COMPLETE ...`；每个模型关闭均save=0。

本轮没有电机闭环仿真、模型图更新、定点化、HDL/C生成、Vivado工程打开/综合/实现、bitstream或硬件动作。软件库可加载不是外设可运行；解析值不是动态性能验收；硬件资料齐备不是线缆已验证。

验收结论：功能/参数证据、资料同步与M1建议已交付；**运行就绪和最终接口冻结保持部分完成/待Review**，尤其是本地Simple交互依赖、count尺度/极性、当前变换数值和板级线缆证据。提交开放PR后停止，不合并、不自动进入M1。
