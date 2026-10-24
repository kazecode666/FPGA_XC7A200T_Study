# M2 结果索引

实际源/模型和操作：[整合验收](../../../coordination/reports/m2_foc_fixed_point_implementation.md)、[设计](../../FOC_FIXED_POINT_DESIGN.md)、[操作指南](../../PMLSM_FOC_FIXED_POINT_GUIDE_ZH.md)。本目录小结果入库，大MAT和失败SLX保留本地`.runtime/m2_20261024`。不能将单元通过替代闭环，或把checkhdl通过当成代码生成/硬件时序验收。

**已知Review阻塞：** 连续点位 `paired_moves_acceptance.json` 为false，电流/速度差超冻结预算。11类共享场景通过与该失败分别保留。

| 阶段 | 证据 |
|---|---|
| A 来源和预算 | [来源清单](source_inventory.json)、[原始场景摘要](source_acceptance.json)、[原FOC块/库](source_blocks.csv)、[预先冻结预算](acceptance_contract.json) |
| B 独立double适配 | [结果](interface_acceptance.json)、[108项迁移指标](interface_metrics.csv) |
| C 范围与类型 | [配置和范围](types_acceptance.json)、[采用类型](types.csv)、[系数量化](coefficients.csv) |
| D 实际固定类型 | [活动编译端口](compiled_types.csv)、[同拍/状态/负例](unit_acceptance.json)、[逐信号量化分解](unit_metrics.csv) |
| D 边界与时长 | [12/24/60V](bus_acceptance.json)、[母线指标](bus_metrics.csv)、[60s微误差积分](long_acceptance.json) |
| E 共享11场景 | [验收](closedloop_acceptance.json)、[原Float不变/Fixed差分](closedloop_metrics.csv)、[有效FOC输入](effective_inputs.csv) |
| E 纹波及跟随 | [固定late20%窗均值/峰峰值](steady_metrics.csv)、[跟随误差及来源标记](tracking_metrics.csv)、[算法限幅与数值饱和区分](observations.json) |
| E 连续点位 | [预设时刻前提失败](paired_initial_failure.json)、[浮点预演冻结命令表](paired_command_plan.json)、[最终命令/Ready及预算结果](paired_moves_acceptance.json)、[连续点位差分](paired_move_metrics.csv) |
| E 实际运行中指令 | [单Run/API结果](live_acceptance.json)、[两次新目标事件](live_commands.csv)；不声称鼠标点击 |
| E/F 正常交付依赖 | [八文件独立目录，两实现直接Run](fresh_acceptance.json) |
| F 兼容性 | [实际checkhdl摘要](hdlcheck_acceptance.json)、[全部7条Message](hdl_checks.json)、[同父层local映射](local_routing.csv) |
| F 文件及静态检查 | [本地快照/dirty保护](preservation.json)、[MATLAB代码分析](code_analysis.json) |

11场景共享曲线均使用原始时间轴，分别展示位置、电流、速度增量和真实选择的参考/复位：

- [标准1mm](scene_standard.png)、[日常10mm](scene_daily.png)、[负位置](scene_position_neg.png)
- [正电流](scene_current_pos.png)、[负电流](scene_current_neg.png)、[正速度](scene_speed_pos.png)、[负速度](scene_speed_neg.png)
- [理想死区对照](scene_ideal.png)、[0.5N负载](scene_load.png)、[PWM/PI复位](scene_reset.png)、[原标称对齐](scene_alignment.png)

late20%是固定统计窗，短场景不一定已稳态。跟随表明确标记物理dq/解析重建控制dq、记录参考/原S曲线重建参考，解析三角值不冒充固定LUT内部反馈。电机1µs日志抽取和100µs控制时间戳的浮点差<1ps，跟随分析检查整数tick一致；Float/Fixed动态预算使用各自同类信号的完全一致时间轴，不插值/不平移。

布局已检查：[根层](fixed_root_layout.png)、[完整DUT](fixed_dut_layout.png)、[适配层](fixed_adapter_layout.png)、[圆限幅/AW](limiter_layout.png)、[SVPWM](svpwm_layout.png)、[共享控制层](shared_control_layout.png)。只整理新增实现和必要接线，不递归排版原浮点、Host、外环或原对齐。

验收脚本在独立进程中后台加载，在`.runtime`唯一目录创建与正式SLX逐字节相同的副本、写入provenance后运行，避免临时观测/自动保存影响正式模型；代码和参数仍从同一配置源派生，不维护第二套算法。普通用户仍只执行一个init、打开原工程主模型并Run。
