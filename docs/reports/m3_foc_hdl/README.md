# M3 证据索引

**M3未接受：A/B/C/D/F PASS，E 20ns综合时序FAIL，WNS−58.833ns。** [整合报告](../../../coordination/reports/m3_foc_systemverilog_rtl_verification.md)、[机器结论](acceptance_result.json)、[操作指南](../../PMLSM_FOC_HDL_GUIDE_ZH.md)。

| 内容 | 实际证据 |
|---|---|
| 来源/用户改动保护 | [source_identity.json](source_identity.json)、[本地与基线](local_vs_base_source.json)、[交互保护](interactive_guard_result.json) |
| B生成与普通TB | [manifest](B_generated_manifest.json)、[clock report](B_generated_clock_report.json)、[ordinary xsim](B_ordinary_xsim_result.json) |
| C原定点→gm | [model结果](model/model_result.json)、[定向](model/directed_probe/case_result.json)、[1024帧](model/boundary_random/case_result.json)、[1536帧](model/actual_prefix/case_result.json) |
| D独立xsim | [严格聚合](rtl/rtl_result.json)、[原始日志/SHA索引](rtl/evidence_index.json) |
| E核心OOC | [分项结果](ooc/ooc_result.json)、[热点/警告](ooc/analysis_zh.md)、[timing](ooc/timing_summary.rpt)、[utilization](ooc/utilization.rpt) |
| F重复与迁移 | [结果](repro/repro_result.json)、[31文件精确比较](repro/repeat_identity.json) |
| 实际端口/提交/预算 | [合同](../../FOC_HDL_TIMING_CONTRACT.md)、[ports](hdl_ports.csv)、[state](state_mapping.csv)、[cycles](cycle_contract.json) |
| 工具正/负门禁 | [fixture汇总](tool_tests_report.json)；fixture不冒充FOC验证 |
| 最终审查2项修订 | [18/18门禁、真实PID及负例](review_fixes/evidence_index.json) |
| 小证据总SHA索引 | [final_evidence_index.json](final_evidence_index.json) |

完整SLX派生模型、源快照、大MAT、DCP和缓存留在 `.runtime/m3_20261024_001/`；不纳入发布包。实际原样SV、普通TB和数据见 [generated/m3_foc](../../../generated/m3_foc/manifest.json)，独立位串fixture在 [verification/m3_foc/vectors](../../../verification/m3_foc/vectors/)。

脚本的计数为0、timeout、缺文件、SHA不符、日志Fatal或关键阶段未执行都不写PASS。负例自己的原始结果保留FAIL；严格包装器实际非零才算“负例被拒绝”。理想20ns时基中的274拍不代表物理实现已经达到50MHz。
