# AXU5EV 项目迁移入口

用户已选定 Cortex-R5F 作为实时运动控制核心，并已建立本地 AXU5EV 文件夹。新仓库目标为 `kazecode666/AXU5EV`；旧工程保留，不整库搬家、不复制 `.git`、不修改旧 origin。

**最新分工覆盖旧 PR54 / M4 的全部控制 HDL 化要求：R5负责外环、原对齐和上层管理；PL负责电流控制与实时采集/PWM/快速禁止。** 旧M4实验安全收口并保留，不再启动全HDL对齐取模优化。

完整可复制的初始化骨架在 `coordination/migrations/axu5ev_seed/`。先读取其中 `AGENTS.md`、`coordination/HANDOFF.md` 及正式任务：

`coordination/migrations/axu5ev_seed/coordination/tasks/ax00_project_bootstrap_migration.md`

将该seed目录的内容按相对路径复制到用户已有的AXU5EV根目录，不把seed父目录作为新工程层级。先确认用户实际目录和已有文件，不强制覆盖。源八文件、模型、RTL和资料不在seed内，由AX-00按清单迁入。

本地Codex优先通过已有授权GitHub CLI创建private仓库。当前ChatGPT连接没有create_repository动作，尚未建立新远端。CLI登录/创建受阻时完成可做的本地工作，明确报告阻塞，不索要token或擅自改为公开。

新空库只做一次文档main首提交，实际迁移在 `codex/ax00-migration` 分支，最后在**新仓库**创建开放迁移PR并提供精确SHA；不自动合并。旧新PR编号不得混用。

本桥接提交仅是文档/初始化文本，不是资产迁移、MATLAB/Vivado运行或新板部署记录。不修改旧模型/参数/生成RTL，也不自动停止本地进程。后续由新仓库承担计划、实施和Review。
