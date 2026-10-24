# M3证据索引

当前PR53 p3核心门禁PASS，等待Review。[机器结论](acceptance_result.json)、[合同](cycle_contract.json)、[逐态映射](state_mapping.csv)、[复验说明](pr53_pipeline_revision/REPRODUCE_ZH.md)。

当前证据在[pr53_pipeline_revision/](pr53_pipeline_revision/)：实际配置SLX、生成gm/validation、source/gm逐位CSV、RTL计数/日志、OOC、重复生成、源快照、寄存/布局审计。当前发布SV/TB/数据见`generated/m3_foc/`。

本目录原有B_generated_manifest.json、model/、rtl/、ooc/、repro/及其他首轮报告均保留原字节，代表B3历史构建cfd8b1d...（274拍、WNS−58.833ns），不能用于声称当前p3通过。更新前的当前文档另存[baseline_B3_current_documents/](pr53_pipeline_revision/baseline_B3_current_documents/)。完整MAT/DCP及失败现场保留.runtime。

范围：独立FOC核心数值/状态/理想时钟RTL及布线前OOC；外部I/O、外围适配、布线后时序和硬件尚未签核，未进入M4。M2受限例外不豁免M3。
