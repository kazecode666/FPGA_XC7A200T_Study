# 模型功能差异与资料清单：M0 初查

日期：2026-10-21。远端基线：`main@319ee0103c4f4b42752fad49014ead2cfbefceea`。

**状态：ChatGPT 远端资料初查；Codex 实际 SLX/本地依赖审计待执行。** 本文不是三个模型逐块等价性报告，也不是运行验收。后续 Codex 在本文补充准确模型路径、参数解析结果和核查状态，保留未确认项，不把推测改写成已验证事实。

证据口径：`目录确认` 只说明文件已入库；`脚本文本` 说明可直接读到的定义；`历史文档` 说明旧报告记录；`本轮 MATLAB 实查` 必须由 Codex 的真实导出/执行补充。未发现证据不等于功能不存在。

## 1. 已确认入库的主要文件

| 资料组 | 已确认路径 | 仍需检查 |
|---|---|---|
| 完整 MIL | `simulink模型/PMLSM_MIL_ControlCore_Sim.slx`、`PMLSM_ControlCore_Block.slx` | 当前实际引用关系、回调、库/字典/数据依赖、有效算法模式 |
| Simple | `simulink模型/PMLSM_ThreeLoop_Simple.slx`、`init_PMLSM_ThreeLoop_Simple.m`、`design_PMLSM_three_loop.m`、`pmlsm_scurve_profile.m` | 本地与远端版本差异、Model Workspace 实际解析值、backend 与场景设置 |
| DSP 实机 | `simulink模型/PMSLM_Close_Loop_MBDL4.slx`、`PMSLM_Init_Params_MBDL4.m` | 实机控制/保护路径、支持包依赖、硬件配置与板卡版本 |
| 公共/场景参数 | `simulink模型/init_PMLSM_control_params.m`、`init_PMLSM_plant_params.m`、`init_PMLSM_mil_test_params.m` | 初始化顺序、覆盖关系、单位与生效值，不只读脚本名 |
| 旧 co-sim | `simulink模型/PMLSM_HDL_Cosim_Minimal.slx`、`init_PMLSM_fpga_cosim_params.m`、`init_PMLSM_step7c_params.m`、`scripts/` | 路径、工具依赖、可重建的 runtime；不因目录存在宣称可运行 |
| 学习与中间工程 | `PWM_Controller/`、`PWM_Breathe/`、`Motor_PWM/`、`FOC_Transforms/`、`FOC_PI/`、`FOC_SVPWM/`、`FOC_Current/`、`FOC_PWM/`、`FOC_Gates/`、`motor_control_ip/`、`learning/` | XPR/Tcl 是否仍引用仅本地存在的源文件；只补相关源依赖，不上传缓存树 |

文件名中的 `PMLSM` 与 `PMSLM`、`MBDL4` 与 `MDBL4` 按实际名称引用，不能自动更名或合并成同名文件。

## 2. 三模型功能差异初表

下表是审计导航。`历史文档` 与 `脚本文本` 已读取；SLX 内部存在性、连接和实际执行状态仍需本轮确认。

| 功能 | 完整 MIL + ControlCore | Simple | DSP 实机 | 本轮核查与迁移判断 |
|---|---|---|---|---|
| 系统职责 | 启动/命令、控制核心、plant/反馈、日志的完整仿真组织（历史文档） | 简化三环及旧 RTL co-sim 骨架（历史文档） | 实机控制与 C 代码生成（历史文档） | 区分可部署逻辑、测试激励、对象模型和观测设施 |
| 电流算法 | 说明中有 PI、DPCC、DPICC、PICDO 等分支 | 现有三环和可选手写 RTL 电流后端 | 实际控制分支须查 SLX | 找到 PI-FOC 源路径与有效模式；不迁移全部研究分支 |
| FOC 内部 | 坐标变换、PI/前馈、限幅、SVPWM 等需逐块查 | 不能只因同名就假定与完整 MIL 等价 | 同样逐块核对 | 记录离散方程、符号、状态更新、限幅顺序和单位 |
| 位置/速度环 | 说明列出外环及相关端口 | 原外环保留，外环电流参考经 reference manager 选择 | 实际执行调度与模式待核 | 不用 Host 电流测试入口代替速度环输出，不顺便重整定 |
| 指令与轨迹 | 启动/测试给定和运行管理混合，须拆分 | 脚本有位置、速度、电流测试、启用时序和轨迹参数 | 实际命令入口与参数写入路径待核 | 区分测试工况、外部命令和可部署状态机 |
| 启动/对齐 | 说明列出 init、angle offset、Init_Done 等 | 有哪些保留/旁路，不能只看截图判断 | 对齐与启动互锁待核 | 查明确切使能条件、状态及退出规则 |
| 使能/复位/模式切换 | 说明列出 enable/reset/模式端口 | 存在 PWM_EN、PI_Reset 等，以及旧 co-sim stop/reset 约定 | 实际关断与恢复逻辑待核 | 记录积分状态、在途计算、PWM 和故障复位的区别 |
| 给定、积分和输出限幅 | 具体范围/顺序需查 | 脚本明确定义速度限幅、速度环电流限幅及积分限幅 | 实机限制来源与作用位置待核 | Simple 并非“完全没有限制”；恢复清单逐项列出 |
| 故障/保护 | fault_i、fault_u、fault_latch 等是历史说明列出的接口，不代表所有保护都实现 | FPGA fault_code/needs_reset 等不等于完整系统保护 | 过流、母线、驱动故障、互锁、行程等逐项核查 | 每项标记已实现/旁路/仿真替代/未找到证据，并给路径 |
| 参数管理 | 初始化脚本存在覆盖关系 | 独立参数脚本文本，不代表所有运行覆盖已核实 | 实机标定与调试参数脚本 | 分类生成期常量、运行可调值、标定值、测试覆盖和状态 |
| 采样与调度 | 控制周期与仿真步长需分别解析 | 脚本定义 Ts=100 us、速度/位置为 10/100 倍；实际生效待查 | ADC/中断/ePWM 调度按模型核对 | 控制周期不等于 FPGA 时钟，记录首拍、相位与更新边界 |
| 电流反馈 | plant/传感器仿真 | 动态 plant 到 legacy/co-sim | ADC 原始码与标定 | 不把已校准物理值输入等同 ADC 接口验证 |
| 位置/速度/角度 | 包含理想反馈入口的历史说明 | 当前路径使用 plant 反馈，理想量与计算量须逐线确认 | 编码器计数、位置/角度换算及测速待核 | 记录实测链路与理想链路差异，留到实际反馈阶段落实延迟 |
| PWM 与死区 | 计数标度、极性、延迟由仿真链定义 | legacy 与旧 active-CMP 后端共享平均逆变器；旧指南记录旁路规则 | ePWM 比较、影子更新、死区/故障输出须查 | 区分调制量、占空比、CMP、六路门极，不重复计算延迟/死区 |
| 电机/逆变器/负载 | 仿真对象 | 仿真对象，既有自由运动工况 | 由真实硬件承担 | 不整体生成到控制器 HDL 中；保持公共测试条件 |
| 观测与日志 | MIL_Logging | Motor_Control_Monitor、具名日志和接口监测 | 实机监测/通信路径待核 | 分开仿真日志、调试寄存器和必要遥测 |

### 已能确认的参数漂移风险

2026-09-17 的旧说明记录了完整 MIL 与 DSP 的 PI 覆盖差异、PWM count 标度差异和 MIL 默认研究模式。当前 Simple 参数脚本则由 `design_PMLSM_three_loop` 生成三环增益，`CPU_Clock=200e6` 在注释中仅用于 legacy SVPWM count 换算。**不能用旧说明中的数字替代当前三个模型的实际解析值，也不能把该变量当作 FPGA 的实际工作时钟。**

M0 必须导出实际初始化后的参数来源与值，并区分“脚本中写了什么”和“模型最终使用了什么”。当前初查不统一 PI、不改默认模式、不改周期或 count 极性。

## 3. 已入库硬件资料

以下根目录文件已由远端目录确认存在；本轮未逐页重审原理图或重新确认接线。

| 类别 | 路径 |
|---|---|
| BX72 | `BX72-251215.pdf`、`BX72_装配图.pdf`、`BX72管脚分配表V2.1.xlsx`、`BX72用户测试说明.txt`、`BX72_test.zip` |
| 其他接口/板卡资料 | `ACM9238-SCH.pdf`、`MDBL4转接板.pdf` |
| 驱动板 | `YXPHM-MBDL4驱动板原理图.pdf`、`YXPHM-MDBL4电机驱动板硬件说明书.pdf` |
| DSP 核心板/底板 | `28388BGA核心板.pdf`、`28388至尊底板V1.1.pdf`、`28335BPLUS迁移至28388D注意事项.txt` |

硬件清单用于找回用户已经提供的接口事实，不等于由文件名重新推断当前 ADC、编码器、引脚或电平方案。Codex 需从材料、既有记录及本地工程提取接口依据，并标注文件/页码/表格/工程路径；不泛问用户重复描述。

## 4. 需定位的补充资料与依赖

旧 `simulink模型/FPGA_Simulink_Model_Guide.md` 引用了以下材料，但它们没有出现在本次读取的 `simulink模型/` 直接目录清单中：

- `PMLSM_MIL_Model_Notes.md`
- `PMLSM_MIL_Test_Flow.md`
- `PMLSM_Hardware_Interface_Map.md`
- `PMLSM_ePWM_Polarity_Check.md`
- `init_PMLSM_MIL_params.m`（旧说明称其为兼容入口）

这只是**定位候选，不是已确认全仓库缺失或运行必需**。Codex 先查全仓库和原始本地目录；若已改名/迁移/不再使用，记录对应关系即可；若实际需要且仅本地存在，补入相关资料。不要虚构文档内容或为了满足清单制造重复入口。

此外核查实际使用的 Model Reference、library link、MATLAB Function 辅助文件、SLDD、MAT 文件、自定义类、mask 初始化、支持包与 XPR/Tcl 引用。依赖缺失须指出具体引用者，而不是仅凭加载失败笼统宣布模型不可用。

## 5. Codex 应补的结果

在 [M0 报告](../coordination/reports/) 中给出实际模型路径与证据、各功能去向、参数来源与覆盖、资料同步清单、已查但未解决的缺项，以及 M1 的具体起点。报告文件名和验收条件见 [任务书](../coordination/tasks/m0_simulink_model_asset_audit.md)。

状态至少区分：已入库但未解析、已读取、实际工具核实、仅本地待同步、真正缺失、历史/不再需要。没有运行仿真就明确写未运行，不把静态审计升级为动态验收。

## 6. 初查依据

[旧模型说明](../simulink模型/FPGA_Simulink_Model_Guide.md)、[Simple 参数](../simulink模型/init_PMLSM_ThreeLoop_Simple.m)、[模型操作指南](PMLSM_MODEL_GUIDE_ZH.md)、[旧交接记录](../coordination/HANDOFF_LEGACY_20261021.md)，以及基线提交的根目录和 `simulink模型/` 目录清单。
