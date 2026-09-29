# SDI 通道名称完善（2026-09-29）

原因：`Motor_Control_Log` 和 `FPGA_Interface_Log` 使用 Mux 向量，SDI 显示 `motor_control_monitor(1..25)` 与 `fpga_interface_monitor(1..22)`，无法直接辨认物理量。基于用户当天最新保存的 R2026b SLX（as-found 基线提交 `666d8ff`），分别为主监测器 25 路、FPGA 接口 11 路和量化范围标志 11 路开启独立信号日志。主监测器条目以 `motor_` 开头，接口条目以 `fpga_if_` 开头，避免与已有场景运行器的同名 `logsout` 信号冲突。

原向量 To Workspace 变量及列顺序保留，旧分析脚本继续使用。打开 SDI 时展开 **“信号”** 分组选择具名通道；向量分组仍会存在，可折叠。参见 [模型中文指南](../../../PMLSM_MODEL_GUIDE_ZH.md)。

[47 路完整映射与数值核对](channel_check.txt)：实际 Vivado/XSI `fresh_start` 20 ms 运行通过；每条新信号与旧向量对应列逐点最大差异 0，SDI API 查到了全部 47 个名称。`step7d_run_scenario` 正常通过。

[结构审计](structure.txt)：相对当天修改前的本地 SLX，控制器、plant、线路、Stateflow、solver、Inport/Outport 参数及几何不变；仅增加信号日志元数据。没有修改 RTL、PI、控制周期和后端选择。先将用户最新 SLX 及相关初始化文件原样记录成基线提交，再单独提交 SDI 命名，方便 Review 区分来源。
