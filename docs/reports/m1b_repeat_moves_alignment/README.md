# M1B结果索引

依据已合并PR48，原checkout增量实现。MATLAB/Simulink R2026b 26.2.0.3386108；[完整验收报告](../../../coordination/reports/m1b_repeat_moves_and_alignment.md)、[操作指南](../../PMLSM_FLOAT_BASELINE_GUIDE_ZH.md)、[FOC准备](../../FOC_FIXED_POINT_READINESS.md)。

| 文件 | 证据 |
|---|---|
| source_inventory.md / workspace_preservation.json | 进入时来源、8个只读文件一致、29项无关修改保留 |
| acceptance_contract.json / baseline_behavior.json | 先冻结容差和原始默认参考，再复现旧目标编辑的两种计时行为 |
| helper_acceptance.json | 纯状态合同、原曲线V/A/J数值边界 |
| point_live.json / commands.csv / point_live.png | 最终一次Run，首段后临时提交3个新目标，含反向；真实Ready与草稿/重复/NaN/暂停继续 |
| point_aligned-live.json / aligned_commands.csv / aligned_live.png | 原对齐后同一次Run两段点位，对齐时请求拒绝 |
| alignment_source.json / alignment_source_map.md | 实际MIL/DSP导出和迁移连接映射 |
| alignment_chart_acceptance.json / alignment_acceptance.json | 五类×70001拍完整chart对照；标称物理集成分别记录 |
| source_mil_physical_corrected.json | 独立源MIL物理参照；初次错误端口观测已作废 |
| default_equivalence.csv | 生产改动前参考 vs 当前默认标准场景，12路最大差0 |
| legacy_regression/closedloop_metrics.csv | 原M1A冻结阈值，9场景及plant步长，共240指标通过 |
| interface_acceptance.json / signals.csv | 保存模型直接Run：67名唯一、原41名保留；local路由/活动端口、实际采样/绑定、PWM段中断 |
| fresh_acceptance.json | 六文件独立运行，无旧MAT/旧模型/FPGA参数依赖 |
| model_layout.png / control_layout.png / host_layout.png | MATLAB导出当前布局，新增区域整理，真实内嵌曲线绑定保留 |
| foc_blocks.csv / foc_parameters.csv / foc_compiled_interface.json / foc_core_preservation.json | 实际FOC模块/库/参数/状态与编译类型；无显式Vdc/enable端口 |
| foc_observed_ranges.csv / foc_scene_ranges.csv | 170数值端口的标准场景范围+代表性live/对齐范围；NaN/Inf另计，不当设计上限 |
| foc_audit.json | checkhdl返回值检查：1错误/11警告/3消息，DUT层次未兼容；无HDL生成 |

`live_acceptance.json`、`aligned_live_acceptance.json`、`point_regression.json`为B/C检查点结果；最终联合live以`point_live.json`与`point_aligned-live.json`为准。原始多百MB MAT/失败现场/测试日志留 `.runtime/m1b_20261024`，不提交。A参考不可覆盖；本目录不覆盖旧M1A/PR47报告。

执行入口（各用独立MATLAB -batch进程；回归脚本会临时加载只读旧来源，不保存）：

```matlab
addpath('D:/Project/FPGA_XC7A200T/scripts')
addpath('D:/Project/FPGA_XC7A200T/simulink模型')
% baseline仅在生产改动前已执行，现状再次执行会明确拒绝覆盖。
m1b_verify_point_commands('regression') % D_regression2.log：9场景240指标
m1b_verify_point_commands('live')       % D_events_corrected.log，running实际绑定提交
m1b_verify_alignment_reuse             % chart+标称闭环+aligned-live
m1b_verify_final_interface             % review_stable_source_green.log
% 新进程单独运行以下两项：
m1a_fresh_float_baseline               % review_fresh_green.log，六文件隔离
m1b_foc_readiness_audit                % E_audit_final.log，临时副本；检查完成不是HDL PASS
```

本轮C完整chart已用`m1b_verify_alignment_reuse('chart')`独立重跑；标称闭环和对齐后live另有独立进程证据，没有将仅尾部1000点的旧测试当完整等价。

API是running控制链和保存绑定证据；未自动鼠标点击。布局/曲线是MATLAB导出，名称表是API导出，均非SDI侧栏截图。未知非零安装偏置物理识别、运动中重规划、热切环、完整故障管理、定点SLX、HDL/C生成和硬件均未验收。
