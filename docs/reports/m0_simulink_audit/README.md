# M0 精简证据索引

日期：2026-10-22；源提交 `361c2c6`；实际用户模型位于原始工作树，Simple保留未提交修改。解释与范围见 [整合报告](../../../coordination/reports/m0_simulink_model_asset_audit.md)。

| 文件 | 含义/证据等级 |
|---|---|
| `model_summary.json` | 四模型真实加载配置、回调、ModelWorkspace来源、库解析和Dirty；首轮查询块数不包含全部variant |
| `model_hierarchy.csv` | 保存SLX中全部子系统/Model Reference路径、SID；不等于编译执行层级 |
| `key_blocks.json` | 真实get_param输入连接、PI/状态/限幅、库mask参数；研究算法只保留边界，不发布无关原始XML |
| `stateflow_semantics.json` | 实际归档中的状态动作、转移及MATLAB Function源码；没有运行状态图 |
| `parameter_stages.json` | 隔离base中的DSP/MIL逐层结果、Simple模型工作区及slResolve遮蔽证明 |
| `focus_queries.json` | 全variant数量、六个变换库mask、已安装库路径、七个timeseries、Simple加载后base配置与空交互状态、Code Analyzer结果 |
| `simple_as_found_vs_main.json` | 当前本地Simple与源提交的结构/参数/回调/四条信号改接对照；不是动态等价性证据 |
| `sync_manifest.json` | 8个补齐文件的外部来源、目标、字节比较及用途；外部源保持只读 |
| `hardware_assets.json` | 12个硬件资产远端路径与本地移动后路径、字节/文本/单元格比较；不重复上传 |
| `xpr_sources.json` | 10个本地XPR的136个File引用存在性/跟踪状态，其中9个XPR在Git；未运行构建 |
| `tool_environment.json` | MATLAB实际版本、已安装产品/支持包；Vivado仅版本banner，命令退出码1 |
| `preservation_check.json` | 原用户tracked二进制diff未变、原untracked路径存在、六个源快照未变；不是功能哈希验收 |
| `document_validation.json` | JSON解析、7个文档的本地链接、72个矩阵路径和Python语法检查；不代替模型运行 |

复现审计使用 `scripts/m0_static_audit.py`、`scripts/m0_readonly_model_audit.m`、`scripts/m0_focus_queries.m`，必须在独立MATLAB批处理进程中执行。具体命令见整合报告。脚本仅写 `.superpowers/m0_20261022/` 的审计输出，不调用update/sim/build/save_system；若用户更改模型/回调，应先重新静态检查，不能直接沿用本次执行安全结论。

首次主查询提示find_system默认variant过滤；后续focus用allVariants补查，当前主脚本也明确使用该过滤器。静态归档包含链接保存内部内容，FollowLinks=off的工具查询不展开全部库内部，数量差异不作为通过/失败依据。

完整原始JSON、日志、PDF渲染、vendor ZIP条目、Git保护patch留在本地 `.superpowers/m0_20261022/`；没有提交模型、MAT、缓存或构建树。所有“存在/解析”只支持当前层级，不表示闭环、RTL、板级或实机通过。
