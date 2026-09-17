# 给 FPGA 项目的 Simulink 文件说明

核对日期：2026-09-17。源项目目录：`D:\Project\PMSLM_Simulation`。

本文用于让 FPGA 项目定位并理解现有控制算法、仿真环境和 DSP 代码生成模型。分类依据为当前磁盘上的 MATLAB 脚本和 SLX 内部 XML 配置；本次没有运行仿真、生成 C/HDL 或验证上板结果。

## 1. 先读哪些文件

| 文件 | 分类 | 用途及 FPGA 项目应如何使用 |
| --- | --- | --- |
| `PMLSM_MIL_ControlCore_Sim.slx` | **主闭环仿真模型（MIL）** | 将启动/测试指令、控制核心、逆变器、电机、传感器和日志连接起来。用于理解测试条件与比较算法输出，是仿真入口。不是 FPGA 硬件实现顶层。 |
| `PMLSM_ControlCore_Block.slx` | **供 MIL 使用的控制算法核心模型** | 重点阅读对象。包含电流控制、坐标变换、电压限幅、SVPWM、启动及外环等逻辑；当前可见 PI、DPCC、半拍补偿 DPICC、PICDO 等路径。它不是完整的电机仿真环境，也不是已经准备好的 HDL 生成模型。 |
| `PMSLM_Close_Loop_MBDL4.slx` | **DSP 实机控制 / 嵌入式 C 代码生成模型** | 对接 TI C2000 外设和 MBDL4 驱动板。当前 `SystemTargetFile=ert.tlc`，`HardwareBoard=TI F2838x`，处理器类型为 C2000；配套参数脚本面向 F28388D。用于查阅实机 ADC 中断、PWM 和控制集成，不能直接作为 FPGA RTL。 |
| `PMSLM_Init_Params_MBDL4.m` | **实机控制参数主脚本** | 当前面向 F28388D + MBDL4 + AUM3-S4，定义时钟、PWM、ADC 标定、编码器换算、电机参数、PI、限幅、启动和在线调试变量。它还为 MIL 的控制参数提供基础值。 |
| `init_PMLSM_control_params.m` | **控制参数加载入口** | 调用 `PMSLM_Init_Params_MBDL4.m`，并记录参数来源；不是一份独立、冻结的 MIL 参数副本。 |
| `init_PMLSM_plant_params.m` | **仿真对象参数** | 定义电机 dq 电气模型、机械模型、平均逆变器、传感器、行程等参数，主要使用 `PMLSM_` 前缀。可用于 FPGA 算法的离线参考仿真，不应整体当作硬件寄存器配置。 |
| `init_PMLSM_mil_test_params.m` | **MIL 测试和场景参数** | 设置电流/速度/位置测试、控制算法模式、逆变器模式、PWM 更新延迟、给定波形、负载和观测器参数，并覆盖部分控制参数。测试激励不属于实机控制器本体。 |

注意文件名中的 `PMLSM` 与 `PMSLM` 两种拼写确实同时存在，读取时使用表中的原始名称。

## 2. 模型之间的关系

```text
PMSLM_Init_Params_MBDL4.m
    ├─ 实机参数 → PMSLM_Close_Loop_MBDL4.slx → TI C2000 嵌入式 C 工作流
    └─ init_PMLSM_control_params.m
          + init_PMLSM_plant_params.m
          + init_PMLSM_mil_test_params.m
                 ↓
        PMLSM_MIL_ControlCore_Sim.slx
          ├─ Startup_And_Commands：启动及测试给定
          ├─ Control_Core：控制核心及接口适配
          │    └─ PMLSM_ControlCore_Block.slx
          ├─ Power_Plant_Feedback：逆变器、电机、传感器反馈
          └─ MIL_Logging：仿真记录
```

当前 MIL 主模型的 `InitFcn` 按顺序调用：

```matlab
init_PMLSM_control_params;
init_PMLSM_plant_params;
init_PMLSM_mil_test_params;
```

`init_PMLSM_MIL_params.m` 是同样顺序的兼容总入口。读取截图中的七个文件之外，也应认识这个入口。

MIL 主模型与控制核心当前都配置为 `grt.tlc`、`HardwareBoard=None`。不要仅凭模型中存在代码生成设置，就把它们认定为实机部署或 HDL 生成工程。实机模型与 MIL 控制核心也是两个独立模型文件；不能默认算法和参数会自动同步。

## 3. FPGA 项目优先关注的接口

`PMLSM_ControlCore_Block.slx` 的顶层端口可以作为算法边界参考：

| 方向 | 端口 | 含义 |
| --- | --- | --- |
| 输入 | `ia`, `ib`, `ic` | 三相电流反馈；结合调用端确认标度，控制层按物理电流使用。 |
| 输入 | `x_mm` | 位置反馈，单位 mm。 |
| 输入 | `v_ref_cmd_mmps_in`, `x_ref_mm_cmd` | 速度给定（mm/s）和位置给定（mm）。 |
| 输入 | `enable_cmd`, `fault_i`, `fault_u` | 使能及故障接口。 |
| 输入 | `iq_test_mode_cmd`, `iq_test_ref_cmd` | 电流测试模式和测试给定。 |
| 输入 | `close_loop_en_cmd`, `pos_loop_en_cmd` | 闭环/位置环使能。 |
| 输入 | `init_start_cmd`, `init_reset_cmd`, `pi_reset_en_cmd`, `id_ref_set_cmd` | 启动、复位和 d 轴给定。 |
| 输入 | `v_ideal_mmps` | 仿真理想速度输入；移植时需要明确采用实际测速还是仿真反馈。 |
| 输出 | `vd_cmd`, `vq_cmd` | dq 电压指令。 |
| 输出 | `duty_a`, `duty_b`, `duty_c` | PWM 相关指令；不能仅凭 duty 名称假定其范围为 0～1，见下一节。 |
| 输出 | `id_ref`, `iq_ref`, `id_meas`, `iq_meas`, `theta_e` | 控制参考、反馈及电角度。 |
| 输出 | `fault_latch`, `Init_Done`, `Close_Loop_EN` | 故障与启动/闭环状态。 |

其余顶层输出包括速度给定及限幅中间量、对齐位置/角度偏置和 `speed_loop_tick`，可用于对照调试。正式定义 FPGA 接口前，还需逐端口确认数据类型、位宽、范围、采样时刻和复位语义；本文不是最终 RTL 接口规范。

## 4. 必须区分的参数和时序

- 实机参数当前设置 PWM 10 kHz、电流环 `Ts_ACR=100 us`、速度环 `Ts_ASR=1 ms`、位置环 `Ts_POS=10 ms`。控制核心固定步长为 `1e-4`，MIL 主模型步长使用 `MIL_Ts_s`。这些是控制周期，不是 FPGA fabric 时钟频率。
- 实机参数当前 `EPWM_Clock=100 MHz`，上下计数得到 `PWM_Period=5000`；仿真对象参数仍为 `PMLSM_pwm_period_counts=7500`。MIL 逆变器内部能看到 `-1/PMLSM_pwm_period_counts` 换算。现有说明描述了 `1-CMPA/period` 的极性约定，因此 FPGA 项目必须沿实际 SVPWM 输出和逆变器输入核对计数尺度、极性、上下计数和更新时刻；不能把两套计数值直接混用。本次仅记录该差异，未修改或验证其仿真影响。
- 实机电流 PI 使用基准的 50%：`Kp_ACR=2.18125`、`Ki_ACR=2962.5`；MIL 测试初始化会覆盖为完整基准：`Kp_ACR=4.3625`、`Ki_ACR=5925`。所以同名参数在不同初始化阶段可能不同。
- `init_PMLSM_mil_test_params.m` 当前默认 `Current_Control_Mode=2`（DPCC），模式注释为 1=PI、2=DPCC、3=DPICC、4=half-delay DPICC、5=half-delay PICDO-DPICC。先确定 FPGA 要实现的算法，再读取对应分支；不要将所有模式视为已在实机模型实现。
- 当前 MIL 默认是静止电流阶跃测试：`MIL_Mode=1`、`Plant_Input_Mode=2`、`MIL_StaticCurrentStepTest_Enable=1`，理想平均逆变器、无死区补偿。它不代表自由运动工况。
- 电气完整周期为 60 mm，极距为 30 mm。使用 `theta_e=2*pi*x/60 mm` 时不能把 30 mm 当成完整周期。
- `PMSLM_Init_Params_MBDL4.m` 开头有 `clear; clc;`。执行它或其包装入口会清理调用工作区；MIL 主模型初始化也会重新加载默认参数。只需理解模型时先静态读取；需要测试覆盖值时，应核对回调执行顺序，不能假定提前设置的变量会保留。

## 5. 如何从 FPGA 项目读取

所有文件均位于本机 `D:\Project\PMSLM_Simulation`，不需要先搬走或改写原模型。MATLAB 会话中可从以下入口加载：

```matlab
cd('D:\Project\PMSLM_Simulation');
load_system('PMLSM_MIL_ControlCore_Sim');
load_system('PMLSM_ControlCore_Block');
% 查看实机结构时再加载：
load_system('PMSLM_Close_Loop_MBDL4');
```

加载模型与运行仿真/构建是不同操作。运行前检查模型回调与所需 MATLAB 产品、C2000 支持包；不要为了浏览而直接启动构建或下载硬件。

如果 FPGA 项目中的助手只能读取文件，`.m` 可直接作为文本读取；`.slx` 是 ZIP 容器，可只读检查其中的 `simulink/*.xml`、`simulink/systems/*.xml` 和 Stateflow 数据。完整算法分析需要跟踪子系统引用、MATLAB Function/Stateflow 内容和参数来源，不能只根据文件名或顶层截图判断。

建议阅读顺序：本说明 → 四个参数脚本 → MIL 主模型 → 控制核心中拟实现的算法 → 实机模型对应的外设连接。辅助资料为 `PMLSM_MIL_Model_Notes.md`、`PMLSM_MIL_Test_Flow.md`、`PMLSM_Hardware_Interface_Map.md`、`PMLSM_ePWM_Polarity_Check.md`；旧说明中的默认值必须与当前脚本/模型复核。

## 6. 其他文件与工作边界

- `PMSLM_Close_Loop_MBDL4_F28335_Backup.slx` 及同名参数备份是历史备份，不应因名称中有 F28335 就覆盖当前 F2838x 配置。
- `*_Backup.slx`、`*.slx.r2023b` 为备份/历史版本线索；`*.slxc`、`slprj` 为缓存或生成内容，不是优先算法源文件。
- 目录中还存在简化三环、MIL 库、死区波形查看等模型，它们不属于本次截图中七个文件的主入口；需要使用时单独核对。
- 当前三个主要模型均未在本文中被认定为 HDL Coder 已验证模型。FPGA 实现需要另外明确算法范围、定点精度、流水线延迟、PWM/ADC 时序与接口，并用 MIL 输出作对照。
- 本说明只提供读取和理解入口，不授权改动源模型。后续修改应遵守源项目 `AGENTS.md`：只改明确目标及相关连线，保持无关布局和默认端口外观，禁止全局自动布局和批量删除。

