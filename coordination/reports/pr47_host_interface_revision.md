# PR47 上位机与具名观测修订

任务：`coordination/tasks/pr47_host_interface_and_logging_revision.md`。在原分支、原工程实施，PR保持OPEN；不合并、不进入M1B/M2。

## 起点及保护

- 以本地已保存的新浮点SLX为起点，而非远端旧模型。相对4b00300本地SLX有用户修改；完整快照为`.runtime/pr47_revision/user_start.slx`，初始35条tracked脏状态及binary patch保留。
- MCP首次检查本会话没有已加载模型，打开本地文件后Dirty=off。没有关闭或覆盖其他MATLAB进程中的窗口；不能据本连接断言其他进程无未保存修改。
- 原Simple/MIL/ControlCore/DSP、旧初始化/MAT、RTL/硬件资料均未编辑。无stash/reset/clean/worktree/文件批量删除。

## 实施

- 清除新模型的Legacy_Telemetry_Disabled、8类伪FPGA事务/故障/cmp监测分支和旧Monitor19列。保留实际三相归一化command/applied duty。Monitor为真实信号的具名Scope入口，不参与控制计算。
- 中文初始化按常用命令、物理参数、时基、PI、逆变器、轨迹分节。固定默认增益断言移到开发验收。标识首先置0，最后成功才置当前版本。InitFcn只检查，不初始化、不覆盖命令。StopTime引用M1A_StopTime_s。
- Simple_Host包装原Host数学为Host_Core：显式Constant输入承接默认手动命令；需要回放时Speed/PWM/Reset先在Host内选择，最终经同一输出边界。环境负载独立单来源，末值保持。
- 三模式启动校验避免位置/速度/iq测试组合冲突；不增加热切环/运动中目标重规划承诺。速度模式使用直接Host_Speed_mmps，默认0与原基线相同；原隐式速度平滑不再作为速度操作入口。
- 顶层Dashboard编辑框绑定唯一实际Base命令变量；轨迹Scope显示规划/反馈，预览复用原pmlsm_scurve_profile标量算法。
- 默认保存具名信号记录。直接sim无需m1a_verify临时日志设置；推荐SDI/out.logsout，不再输出旧motor_control_monitor向量。

## 验证证据

结果在`docs/reports/pr47_host_revision/acceptance.json`，实际运行MAT数据保留本地.runtime/结果目录但不提交大体积MAT缓存。

- 已观察修订前负例：Host_PWM_EN不存在；普通初始化含硬编码Kp/Ki断言；Host的speed/PWM/reset输出终止且被顶层旁路。
- 本地修订前/后默认30ms同工况：id/iq逐样本误差0。默认完整1.2s位置仍为0.9849676863605962mm（1mm目标、原0.02mm死区）。默认PI/FOC/plant数学和时基未改。
- 三闭环1.2s、速度+电流10mm/s 0.1s、独立电流id=.05A/iq=.2A 0.03s已实际通过；速度模式末位置.24906855mm。独立电流测试自由机械体移动属于预期，不添加位置限制。
- 直接sim得到41路唯一名称，包含实际选中id_ref/iq_ref而非仅测试入口。源端口/单位/采样见signals.csv；使能及复位不抽取采样。
- PWM禁止时平均vd/vq为0；PI请求/有效复位及x_d/x_q、速度积分、AW状态记录在本地reset_run.mat。电流积分按原有效复位处理；AW延迟仍更新前拍限幅差，不强制清零，速度环保持原关闭/测试模式的原状态逻辑。未添加统一清故障功能。
- 通过SimulationCommand实际start→pause（约5.1ms）→绑定目标Constant调PWM=0/Reset=1→continue（约14.1ms）→stop；实际日志确认PWM=0、请求=1且vq=0。恢复变量表达式及默认pacing。此项验证绑定对象与真实可调参数，不宣称自动鼠标点击了Dashboard控件。
- 轨迹正/负目标在相同采样时刻比较，短/长停止时间、完整负载场景及布局导出结果随最终验收记录更新。

## 工具、失败和限制

使用正常`mcp__matlab`连接执行实际MATLAB R2026b；`mcp__matlab_r2026b`仍指向缺失Prerelease路径，未改配置。全程未使用computer use。

保留用户布局的任务约束优先于工具包自动布局要求。先前已验证model_edit结构修改会递归布局MCB链接库；本轮按SID用原生MATLAB结构/日志API通过MCP修订，未全局排版、未改工具包。后续按用户明确要求只整理新增命令/观测区域并检查连线。

本轮开发中曾遇Dashboard库路径不匹配，查询真实库后改为simulink_hmi_blocks/Edit；初次参数绑定遗漏VarName，update警告后补上VarName/base，重新update无警告。预览验收首次把100us预览与1us实际数组直接按索引比较，报长度错误；改为同一时间采样点比较。MATLAB缓存旧测试函数曾导致旧代码再次执行，显式clear该测试函数后重跑；未修改模型数值或放宽容差。

模型图由MATLAB原生图导出；轨迹由实际记录绘制；SDI原生snapshot接口已尝试，但未产生PNG文件；改为从SDI API导出实际名称表，未伪造侧栏截图。没有桌面截图/鼠标操作证据，操作说明应按此边界理解。没有Vivado/HDL/硬件验收。


最终补充：优化后的Host验收输出PR47_HOST_PASS，正/负目标0.45s的预览与实际Host在相同时间戳误差<1e-12，1.3s负载工况通过。先前逐1us反复evalin的验收触发600s MCP超时；终止本轮MCP专用执行子进程26988后重连，未终止用户桌面41528/23532，未损坏已保存模型。优化只减少冗余比较点，不改控制/轨迹或容差。

独立审查识别并修正：编辑框隐藏标签、干净会话验收未加载模型、旧初始化测试的负载token失效。静态比较确认FOC/PI/plant共同内部system XML（排除日志元数据）与用户起始模型一致。布局检查发现Monitor与逆变器重叠，已移到右侧独立区；删除11个失去用途的From观测副本，Host内部仅作局部排版；顶层Host输出到邻近Goto，原控制/plant内部位置保留。最终编译及活动端口无悬空检查见layout_connectivity.json。

审查图：[顶层](../../docs/reports/pr47_host_revision/model_top.png)、[Host](../../docs/reports/pr47_host_revision/host.png)、[Monitor](../../docs/reports/pr47_host_revision/monitor.png)、[真实日志名称列表](../../docs/reports/pr47_host_revision/named_signals.png)。名称列表为实际运行结果的MATLAB表格导出，不冒充SDI侧栏桌面截图。


最终受影响回归：独立进程39396得到M1A_INIT_PASS、M1A_MATH_PASS、9个迁移场景+步长收敛240项PASS，PR47_FINAL_REGRESSION_PASS。closedloop_metrics.csv与原已接受数据完全相同，closedloop_acceptance.json更新本次运行路径。物理默认值/增益保持不变。初始化第2行NASGU是故意使成功标识失效，已加定点说明；随后Code Analyzer复核。

SDI API实际确认本次Run 2506有50路具名记录：41路正式logsout及9路Dashboard自动记录的手动参数。见[sdi_names.json](../../docs/reports/pr47_host_revision/sdi_names.json)及[实际SDI名称表导出](../../docs/reports/pr47_host_revision/sdi_signal_names.png)。Dashboard参数记录与Host实际选中输出分别命名，回放时应看PWM_EN/v_ref_cmd等实际输出，不能只看Host_*手动参数。

未完成的UI证据项：未用鼠标点击Dashboard；原生SDI快照调用返回但没有生成图片，提交的是实际SDI API名称的MATLAB表格图。模型/Host/Monitor原生图和实际轨迹图均已生成并检查，最终更新与端口连接检查通过。上述UI证据限制不扩大为完整桌面交互验证。
另以临时初始化文本将相电阻改为2.5 ohm，正常入口及只读检查接受随设计函数得到的Ki_ACR=12500，随后显式恢复默认11850；证明已解除固定PI数字锁而未改变默认值。


### 后续：旁置S曲线和严格同层局部标签

以用户随后保存的最新SLX为起点（快照.runtime/pr47_local_curve/user_start.slx），该文件的Goto已是local，保留其修改。严格同父层匹配测试仍发现Monitor内11个From依赖跨层标签。现改为Monitor的11个显式Inport，顶层局部From紧靠端口；全模型Goto强制local，From/Goto均方括号Tag显示。跨层只走输入输出端口。

在输入面板右侧新增大尺寸Dashboard Scope S_Curve_Reference_Actual，绑定真实Simple_Host输出1（规划x_ref_mm）及plant输出6（实际x_mm）。默认TimeSpan=auto；Run后直接显示。原Scope仍保留作可选放大查看。没有重新实现轨迹公式。

实际接入时确认Dashboard Scope的Binding需要SignalSpecification的cell数组，TimeSpan不接受工作区表达式，LegendPosition区分大小写，最终采用合法默认图例位置Top。均在保存前修正并update检查。

验收：scripts/m1a_verify_local_routing.m检查全部局部路由、同层唯一匹配、11个Monitor显式输入、显示绑定，再运行1.2s默认场景，与已接受默认运行的12路实际信号逐样本精确比较。结果见local_curve_acceptance.json，最终画布见local_curve_top.png。仅改新模型显示/观测边界；旧模型及控制数学不改。

本轮最终结果：66个local Goto、95个同层唯一匹配From、Monitor11输入，默认1.2s的12路信号逐样本max_abs_error=0。新验收脚本支持传入修订前MAT参考路径；默认使用本机保留的default_run.mat，大体积MAT未提交，因此该数值对照需本机参考数据，正常模型Run和布局检查不依赖它。顶层导出图已目视检查，曲线实际可见，新增区域无重叠。
