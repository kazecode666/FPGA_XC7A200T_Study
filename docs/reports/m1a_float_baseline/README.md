# M1A 精简结果索引

详细实施与边界：[实施报告](../../../coordination/reports/m1a_pure_simulink_float_baseline.md)。

| 文件 | 内容 |
|---|---|
| source_inventory.md | 来源版本、保护、结构/初始化/数学检查点与工具偏离 |
| acceptance_config.json | 闭环前冻结的迁移/数学/步长/事件门槛 |
| init_acceptance.json | 参数组织检查点的两个独立 MATLAB 进程配对 |
| modulation_vectors.csv | 115 个实际新/源 SVPWM block 点，旧 counts、新 duty、独立电压重构 |
| transform_vectors.csv / transform_acceptance.json | 32 个实际 Clarke/Park/反 Park 点，对照独立解析公式与往返重构 |
| pi_timing_acceptance.json | 实际 PI/AW/复位、首 tick、半周期更新与禁止电压 |
| closedloop_metrics.csv | 九迁移场景加一个步长对照，240 行 max-abs/RMSE、单位、门槛和 pass |
| closedloop_acceptance.json | 场景、实际源 backend 与结果摘要 |
| fresh_acceptance.json | 最终五文件隔离模型，两个新进程 1.2 s 默认工况的 11 路输出完全一致 |
| connectivity_acceptance.json | 清理 21 段悬空线，全部有效连接保持相同 |
| code_analyzer.json | 八个新增 MATLAB 文件的实际 Code Analyzer 输出 |
| preservation_check.json | 原 34 项 tracked 修改、666 项 untracked 路径和七份源文件保留；最终 SLX 与两次 fresh 副本逐字节相同 |

原始 batch/job 日志、受保护源快照、全部场景 MAT 和 fresh 隔离模型保留在原仓库 `.runtime/m1a_20261023/`，不提交工具缓存或完整仿真数据。新模型的独立运行不使用这些记录；源迁移复核仍需要所选本地 Simple/MAT 配对。
