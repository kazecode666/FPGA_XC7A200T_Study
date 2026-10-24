# 同一死区符号序列的受控诊断与受限验收裁决

2026-10-24，按用户授权，仅在临时测试副本把Float/Fixed三相`delta_d`的符号输入改为原Float完整0–4s记录。正式SLX、PI、Current32/24等类型、1µs死区及其比率、100µA阈值、50µsPWM更新、1µs对象、100µs控制、冻结命令表和原预算均不改。原Sign计算保留为未使用观测，原duty修正/限幅/电压方程仍执行。

## 预先确定的方法和实际结果

[运行前判读计划](diagnostic_plan.json)先要求Float自回放13类输出/状态逐值一致，再判定iq/速度峰值及RMSE是否至少收敛90%。90%是本次因果诊断的判读条件，不是新增生产验收预算。只选原Float整段三相符号，不依据峰值选择片段、不平移时间、不从中途重置状态。每相4,000,001个1µs样本均直接回放；实际使用的三相符号在两次仿真中与录制逐拍一致，错位/不同值均0。

[Float自回放](float_self_replay.json)13类输出/状态最大差0；[Fixed回放](fixed_replay.json)完整序列验证通过。[命令/Ready对照](command_and_ready.csv)中目标、分段起点、接受数、拒绝数、状态和Ready均逐样本一致，仍为4个接受目标和1次Busy拒绝。

| 指标 | 原生产场景Float/Fixed差 | 共用符号的诊断差 | 降幅 |
|---|---:|---:|---:|
| iq最大差 | 0.00639943163 A | 8.98909e−8 A | 99.998595% |
| iq RMSE | 0.000569616651 A | 2.42389e−8 A | 99.995745% |
| 速度最大差 | 0.188900207 mm/s | 1.80614e−6 mm/s | 99.999044% |
| 速度RMSE | 0.0201413712 mm/s | 5.24458e−7 mm/s | 99.997396% |
| 位置最大差 | 0.000324572594 mm | 9.50210e−9 mm | 99.997072% |

完整[指标](convergence_metrics.csv)、[原差异与干预差异曲线](original_vs_common_sign.png)、[诊断结论](diagnostic_conclusion.json)。所有差值用相同原生时间轴，未移事件或曲线。图中共用符号残差接近横轴，数值并非0，以CSV为准。

只替换符号这一因素，Float可逐值自复现，iq/速度峰值和RMSE差异随符号反馈分叉的消除均下降超过99.99%；结合此前首次阈值分歧的约0.48V直接局部关系及完整九路同输入FOC重放，**足以支持既有死区符号阈值分叉是本冻结场景新增闭环差异的主要放大机制**。这不是对所有输入/内部事件的唯一因果证明；强制使用外部符号是反事实诊断，不是应交付的控制算法。

## 原生产场景的运动指标与限制

[原运动指标对照](original_motion_metric_comparison.csv)重新整理提交中既有真实跟踪/保持数据；不是用诊断场景替代生产场景评价。全4s内实际Park电流反馈对最终iq参考的RMSE：Float=0.00422983124A、Fixed=0.00422945113A，差3.80111e−7A；最大跟踪误差分别0.0153562/0.0156489A。位置对实际S曲线的RMSE分别0.0268068968/0.0268051725mm，差1.72433e−6mm。原位置逐样本max/RMSE差0.000324573/0.000108628mm，继续通过原0.005/0.001预算。

[原四次到位](original_arrival_evidence.csv)首次Ready时刻相同：0.7199/1.6699/2.5199/2.9599s；两种实现全部满足原0.02+1e−9mm窗。最坏Ready误差Float=0.0199606681mm、Fixed=0.0198200459mm。初始自动目标的接受计数从0s开始记录，不冒充新的UI提交事件。

规划完成至下一目标前，四段保持的平均误差最大增量约2.54e−5mm、RMSE最大增量约2.48e−5mm，Ready占比逐段相同。但前三段的绝对最大误差在两实现中均会超过0.02mm，最坏约0.04682mm；这些窗口含收敛，不是全程稳态。首次Ready不等于永久保持。此前峰值±1ms小窗的iq跟随RMSE也不同，例如Float约0.003154A、Fixed约0.006544A，仍见[原小窗口表](../pr51_revision/tracking_metrics.csv)，不因全程统计接近而隐藏局部差异。

## 明确的受限例外

技术判断：**支持仅对这个冻结场景提出受限验收例外，提交PR51 Review确认。** [M2-E-REPEAT-001](acceptance_exception.json)明确列出恰好三项超限的原实测值、原门槛、诊断证据、仍须通过的指标和失效条件。范围是相同模型/参数/类型/初态/时序和冻结命令表下的定点迁移仿真验证；不声称电机系统本身已经满足实际定位/纹波性能合同。

原`acceptance_contract.json`、`paired_move_metrics.csv`、`paired_moves_acceptance.json`和正常`closedloop/all`的失败退出均保留：**严格验收仍FAIL，受限例外不是“完整M2严格PASS”。** 单元/同输入重放预算不豁免，id/位置原逐样本预算不豁免，命令/状态/到位不豁免，也不外推到其他场景或硬件。参数、类型、死区法则、时基、对象、序列或初态变化须重新审查。PR保持开放，不自动合并、不进入M3或HDL/Vivado。

## 可复核性与保护

模板来自最新本地八文件的逐字节副本。仅用MCP `model_edit`在SID814/829/844按[明确操作](template_operations.json)添加FromWorkspace和Terminator、换三条符号输入；局部自动布局只影响临时三相小子系统。连线检查healthy，保存前断言FileName在临时目录。[保护审计](preservation.json)证明除三相重接和根层SID计数外，所有原块数值参数/其余子系统不变，固定DUT字节不变；34个正式入口文件和31段用户dirty差异不变。

[默认隔离回归](default_isolation.json)确认不传干预参数的测试工厂仍从正式目录取副本、三相仍使用自身Signum；未标记的来源覆盖被拒绝，诊断不泄漏到普通Run。原有脚本编辑器和用户文件未动，不打开重复模型图窗，不使用computer use或删除文件。[代码分析](code_analysis.json)覆盖6个相关MATLAB函数，0 error。

本机保留模板指针`.runtime/pr51_common_sign_20261024/template.json`、符号MAT和两次完整大MAT；模板SLX仅留临时目录，不提交为生产模型。[来源/大文件SHA-256](raw_evidence_manifest.json)供复核。现有本地证据可执行：

```matlab
addpath('D:/Project/FPGA_XC7A200T/scripts');
m2_common_sign_diagnostic('analyze');  % 从已保存MAT重建小表和曲线
m2_check_common_sign_default;         % 只验证默认副本绑定和自身符号来源
```

新录制依次为prepare→float→fixed→analyze，前提是先从新本地快照用MCP操作建立且标记临时模板。已有符号/运行MAT会明确拒绝覆盖，应选择新的本地证据目录并保留首份证据。正常Run完全不依赖这些开发MAT。一次分析阶段误用Dataset.removeElement的名称参数，被API拒绝；改为倒序整数索引后从同一已保存MAT完成分析，没有重跑仿真或改变数据。既有Float未选中0/0、MCB量化提示保留；没有为此次诊断重新跑无改动的11场景、60s或HDL检查。
