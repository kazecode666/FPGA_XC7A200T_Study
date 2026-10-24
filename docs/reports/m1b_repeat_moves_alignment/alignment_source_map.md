# 原MIL对齐直接迁移表

| 对象 | 原来源 | 新连接/保留方式 |
|---|---|---|
| 状态图 | ControlCore_Block/PMLSM_ControlCore/Angle_Init，SID128 | 原块复制入Alignment_Task_10kHz/Enabled_Original_MIL，状态动作、转移端点/优先级、输出初值不改 |
| 调度 | 父ControlCore100us事件 | 独立同相100us调用源，优先于原控制调用源；实际阶段切换.0001/1.0001/4.0001/4.2001s |
| Signal接口 | 原输出必须ResolveToSignalObject | 唯一init显式提供六个double/0初值Signal对象，未调用DSP参数链 |
| theta | Caculate_measurement的x转换/2pi/Tau/AddOffset/mod/固定角Switch2 | 精确复制必要上游块，不复制速度差分/IIR；旁路选原理想角，物理逆变器/plant角不变 |
| id对齐 | Reference_Manager/Switch3，fault Switch5 | 加在现有参考选择后、FOC前，不改变FOC数学 |
| iq禁止 | Reference_Manager/Switch2，fault Switch4 | 对齐时选0；未完成时Host关闭外环并禁止测试iq |
| 外环放行 | Reference_Manager/Switch9及Angle_Init_EN复位 | Init_Done或显式旁路放行v_ref；原位置/速度环的对齐复位输入接原Angle_Init_EN |
| omega | 原测量链对齐时置0 | 固定角期间选0；正常仍用既有理想omega，不新增差分/滤波 |
| 物理角 | plant输出 | 继续送真实相电流/平均逆变器坐标；控制角另记theta_control_rad |
|故障/复位| Init_Start/Init_Reset/travel_fault_latch | 显式端口，仿真注入默认0；未宣称行程检测/完整故障锁存恢复 |

MIL五态：IDLE0→RAMP_ID1→HOLD_ALIGN2→RAMP_DOWN_ID3→DONE4。DSP实际保存图无RAMP_DOWN_ID且DONE3，仅核对不复制。Ramp10000/Hold30000/Release2000、IdTarget.5A、thetaAlign0、Tau60mm与原值一致。

源图Reset不清除已存Theta_Offset_auto数值，但Init_Done变0；不能把残留值当有效完成，也不能人为清零掩盖原语义。五类chart对照含完成后的Reset，每路全部70001点，误差0。初次ToWorkspace默认只保留1000点的问题已发现并改为inf，旧尾部捕获仅保留本地审计，不作为逐拍证明。

名义物理来源为原MIL静止电流默认场景（位置/角度显式冻结0）。在source-only独立进程运行原模型及其原初始化，与新基线会话隔离；未把旧PI引入新模型。源DPCC模式保持误差约.01757A，新PI保持段误差0、iq0、角差0。这里不证明未知非零初始角的标定鲁棒性。

初次源模型采集把ModelReference端口8/9/10误读成电流/角度（实际是duty），原始错误记录保留.runtime；核对真实接口3/4/5后独立重跑通过，未放宽判据。
