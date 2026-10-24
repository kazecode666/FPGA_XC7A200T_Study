# PR51 评论修订证据

2026-10-24，对应 Review `5637860337`、P2 `4366797498`、P3 `4366797500`。保留原失败、冻结命令表和预算，不改 PI、死区、Init_Start、原对齐或生产类型，不进入 M3。正式 SLX 本轮没有改动；使用最新本地文件的逐字节副本。

- [异常清理](interface_cleanup.json)：在 interface 创建源参考后注入异常；专属 onCleanup 关闭该模型，同一进程重建同名参考并仿真5拍；另一未保存测试模型保持不变。
- [首次分支分歧](branch_divergence.csv)、[峰值](failure_peaks.csv)、[定位范围](localization.json)：完整0–4s回放与旧失败的13类输出差为0，命令/Ready逐样本一致。死区符号最早B相0.132679s、C相0.132680s、A相0.213042s；扇区最早0.302s。所记录的延迟限幅标志和PI复位没有分歧。这是这些具名分支的搜索，不冒充穷尽全部库内部条件。
- [算术差首次出现](arithmetic_divergence.csv)另列最早非零差，不能把首次符号分歧误称为首次任何数值差。三相command duty在0s已有共同约−5.59e−9差；物理电流差从0.12s出现。
- [首次分歧逐信号值](first_branch_point.csv)、[局部分支等式](first_branch_local_identity.json)、[1µs放大图](first_branch_zoom_1us.png)：B相Float电流0.0001000114731A、Fixed 0.00009999596455A，差−15.5086nA，跨原1e−4A阈值。实际Sign为1/0、delta duty为0.01/0。上次PWM更新均0.13265s，applied duty仅差−6.75755e−9；B极点电压差+0.4799996756V，`Δv0=48*(Δd_applied−Δdelta_d)`残差4.996e−16V。本式只证明此瞬时未饱和分支的局部关系，不证明整个4s闭环误差已全部归因。
- [参考跟随](tracking_metrics.csv)、[规划完成后的保持](holding_metrics.csv)：使用实际Park反馈/最终参考及实际S曲线日志；独立于原float/fixed差值。保持窗为轨迹完成至下一次接受目标之前，含到位前的收敛，不称为全部稳态或实机精度。Ready占比也不是到位首次到达时间。
- [本地文件保护](preservation.json)：本轮入口34个本地文件、31段原有dirty差异保持；旧SLX、用户手动布局和日志修改不回退、不提交。

窗口命名 `first_branch`、`peak_iq`、`peak_v_mmps`。`*_control_100us.csv`保留最终九路FOC入口、实际Park、PI原始电压、圆限幅电压、积分和前拍AW、command duty、物理电流/速度/位置、命令与Ready；`*_plant_1us.csv`保留实际相电流、DeadZone输出、实际Sign、delta duty、有效duty/极点电压和最终dq电压；`*_applied_50us.csv`单列原PWM更新输出。不同速率不混成一个“同拍”表，不平移或插值比较动态数据。母线若被常量折叠，仅从实际记录的常值明确展开。图使用各信号原生时间戳。

完整4s/40001拍Float实际九路输入录制和同初态重放存于本地`.runtime/pr51_review_20261024`，小指标和曲线入库。重放从0s零PI/前拍AW状态开始，不在峰值窗口重新初始化；原参考仍复制实际Float FOC，原Vdc参数与第九路实际48V记录一致。输入量化和内部/系数量化分别列出。相同输入重放通过也不替代原闭环预算。

[同输入指标](same_input_replay_metrics.csv)、[重放结论](same_input_replay.json)、[完整前缀曲线](same_input_full_prefix.png)：原参考重放与闭环实际Float的13项输出/状态最大差0；最大Park差3.43722e−8A、原始/限幅dq电压差7.90074e−6V、duty差1.56092e−7，AW差0。只有duty和限幅dq电压应用原D预算；表中Inf的Park/状态只作诊断，不声称新增验收合同。`pass_for_frozen_DUT_output_budgets=true`与`closed_loop_acceptance_pass=false`同时保留，未把重放PASS改写为M2总PASS。

同一输入的算术差远小于各自闭环中的电压/电流差，且已记录到近零阈值的离散分支放大。这支持反馈与非光滑切换敏感性解释；尚未证明所有峰值/RMSE仅来自死区，更未证明新的容差或实机精度。原iq最大差6.39943mA、速度最大差/RMSE 0.18890021/0.02014137mm/s继续超限。

[小窗口验收](window_evidence.json)确认完整0–4s运行后只限制日志时间窗，所有共同日志对应值与完整录制差为0。[代码分析](code_analysis.json)覆盖6个新增/修改MATLAB函数，0 error；剩余提示包括必须保留的onCleanup句柄、旧格式/预分配建议，不把句柄改成`~`导致立即析构。修复了分析函数误嵌套导致共享循环变量的警告，并重新生成/核对分析结果。Python保护脚本语法检查通过。

在没有主/定点模型加载的独立MATLAB会话，先把原工程`scripts`加入path，再依次执行：

```matlab
m2_pr51_revision('cleanup');
m2_pr51_revision('collect');
m2_pr51_revision('windows');
m2_pr51_revision('replay');
```

脚本只后台加载八文件测试副本，核实两模型实际FileName，结束关闭本测试模型并恢复cwd/path；不打开同名图窗，不使用computer use。`collect`保留已有完整录制；窗口/重放已存在时明确拒绝覆盖，应保留首份证据并自行选择新的证据目录后复验，不删除原始文件。`m2_pr51_analyze(stage)`可仅从已保存MAT重新生成小表和图。清理试验需要原有11场景参考文件清单，正常Run不需要开发MAT。

本轮不增加类型/算子候选；既有Current40/32试验仍维持“接受轨迹不同，不能用于原预算”的结论。未批准新验收口径；原iq及速度逐样本预算失败继续阻塞完整M2合并。

[修订状态](revision_summary.json)明确区分P2定位检查点完成、P3修复、DUT重放通过和闭环预算未过。[大MAT清单与SHA-256](raw_evidence_manifest.json)对应本地259386037字节证据，不把大MAT提交入库；[退出会话](session_exit.json)确认本次MCP会话没有残留模型，未打开测试图窗或保存正式文件。
