# M3 SystemVerilog与RTL验证 — 当前PR53 p3

2026-10-25，R1—R4技术门禁完成，PR53保持开放等待Review，不自动合并。完整根因、候选与寄存边界见[本轮报告](pr53_critical_path_pipeline_revision.md)；[验收JSON](../../docs/reports/m3_foc_hdl/acceptance_result.json)、[中文操作](../../docs/PMLSM_FOC_HDL_GUIDE_ZH.md)、[当前发布清单](../../generated/m3_foc/manifest.json)。

|检查点|当前实际结果|
|---|---|
|A来源/合同|保留最新本地布局、8源快照；50MHz/20ns、100us/5000拍、2500拍应用边界不变|
|B实际生成|p3实际配置SLX、gm/validation、29SV+普通TB+4data，源/配置/合同与manifest绑定|
|C原定点→gm|17/1024/1536帧，18039值0位差；68下一态0位差；原生短validation17帧；长原生validation未运行|
|D RTL|2613正例帧/52289123检查；无位/状态/XZ/协议/deadline错；1bit和真实313拍负例均被拒绝|
|E核心OOC|20ns WNS+5.317/WHS+0.135ns，TNS/THS0；70983LUT/83278FF/439DSP/0BRAM；内部结构检查0异常|
|F重复/兼容|独立进程重复34原始文件、配置及8源SHA相同；普通TB/换目录/实际发布状态smoke通过|

新输出314拍，PI/AW观察提交下一帧1，原旧态消费pre5000不变。不是删状态检查或移动golden；实际结构及每拍D/保持/CE/reset共同验证。正常输入需整帧保持，没有实现共同capture、frame-valid或输出提交适配。仅核心布线前估算，不代表板级deadline或布线后时序，不进入M4。

首轮B3报告及其FAIL结论原字节保留在[历史报告](../../docs/reports/m3_foc_hdl/pr53_pipeline_revision/baseline_B3_current_documents/coordination/reports/m3_foc_systemverilog_rtl_verification.md)，原ooc/model/rtl/repro目录未覆盖。首轮−58.833ns和274拍仍是真实失败历史。M2例外没有用于本轮。
