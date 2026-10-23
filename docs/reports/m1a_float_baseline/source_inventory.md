# M1A 来源冻结与检查点记录

2026-10-23，PR46 已合并，实际基线 `b404bea3aeacfdeb5954c983670a5fe4253f0d65`。
实施分支 `codex/m1a-float-baseline`，原工作目录 `D:/Project/FPGA_XC7A200T`。

## 来源

原 `simulink模型/PMLSM_ThreeLoop_Simple.slx`：556658 bytes。
原初始化 `init_PMLSM_ThreeLoop_Simple.m`：3055 bytes。
两者与 `.superpowers/m0_20261022/before_*` 快照逐字节相同；MIL、ControlCore、DSP 模型和 DSP 参数脚本也相同。
本地 `init_PMLSM_ThreeLoop_Simple.mat`：3696 bytes，属于来源依赖，不提交为新模型依赖。
七项时间序列的 M0 内容见 `docs/reports/m0_simulink_audit/focus_queries.json`。
原 MAT 中 load 在 0.8 s 加 0.5 N、1 s 撤除；新模型默认零负载，负载阶跃作为独立工况。

原 Model Workspace：`MATLAB File`，文件 `init_PMLSM_ThreeLoop_Simple.m`，同名参数会遮蔽 Base Workspace。
原 InitFcn：reload ModelWorkspace 后调用 `pmlsm_interactive_cosim_init(bdroot)`。
原 PreLoadFcn：`init_PMLSM_fpga_cosim_params`。
必要计算函数：已入库的 `design_PMLSM_three_loop.m`、`pmlsm_scurve_profile.m`。
来源控制器为 `Control_Task_10kHz/FOC_Algorithm`，一个 `PMLSM_Plant_Model` 和一个 `Inverter_DeadTime`；保留三环及 Reference Manager/scheduler。

## 现场保护与工具

原 tracked/untracked 状态、Git binary patch 和七份源文件快照保存在独立目录 `.runtime/m1a_20261023/`。
没有 stash/reset/clean、删除文件、clone/worktree 或修改外部原始目录。
启动前未发现正在运行的 MATLAB.exe；独立批处理进程用于本轮检查。
MATLAB 正式版 `26.2.0.3386108 (R2026b)`，实际路径 `D:/Program Files/MATLAB/R2026b/bin/matlab.exe`。
连接器指向缺失的 `R2026b_Prerelease`，因此使用已安装的本地 `model_read/model_edit/model_check` 函数批处理，不改连接器配置。
`library.settingsLookup` 返回 found=false / gatePass=true，使用标准 Simulink 块和源模型已有厂商库。

## 历史检查点进度

- `m1a_verify_float_baseline('structure')` 首次运行预期失败：`M1A_MODEL_MISSING`，batch 退出 1。
- 已从本地来源另存新 SLX，清空新副本的旧 PreLoadFcn / InitFcn；原 SLX 未保存。
- 后续结构、独立初始化、数学及闭环验收结果必须由实际运行补充。此记录不表示 PASS。

结构检查实际结果：`M1A_STRUCTURE_PASS blocks=716 Dirty=off`（R2026b，`structure_and_init_red.log`）。
原生端口检查没有闲置输入/输出。删除旧 `FPGA_HDL_Cosim` 子系统与逆变器中的四个后端选择器；保持 legacy counts、半周期更新、单死区、单 plant。
旧 FPGA 监视通道暂接显式 `Legacy_Telemetry_Disabled=0`，这些零不是 FPGA 运行结果。补终端的仅为来源已闲置的 Simple_Host 输出。

工具偏离：`model_edit(...,'incremental')` 的后台布局监听器递归进入 MCB 库；尝试 `LayoutStateManager.setEnabled(false)` 后仍复现，报 `Attempting to override parameters ... inside a library link`。
两次尝试均在保存前终止本轮自有进程，保留日志。最终以原生 MATLAB 按 SID 编辑新副本并检查端口连接；没有调用全局布局，没有改工具配置或厂商库。

初始化检查点：新 Model Workspace 为空，InitFcn 仅调用只读 `m1a_require_float_init`；四项工况时间序列显式生成并保持，旧 MAT/prepare 回调移除。
两个独立批处理 PID 45492 / 45496 的默认、重复、负位置、负载、默认恢复五组 logsout 全部逐样本相同，见 `init_acceptance.json`。
位置观察 25 ms，包含首个 9.9 ms 位置事件；负位置场景末值 -0.0028630039612365485 mm。短默认/负载观察 2 ms。此检查不替代后续完整闭环迁移验收。

调制/数学检查点：原扇区时间计算保留，仅将三路时间比例转换为 `1-2*t/T_pwm`；移除 legacy counts 转换子系统，将半周期延迟初值改为 0.5。新主链与初始化不再使用 CPU_Clock / period_counts。
115 个实际新/源 SVPWM block 向量（零矢量、六扇区及切换两侧、接近线性限幅）结果见 `modulation_vectors.csv`。max duty error=1.1102230246251565e-16，max physical voltage error=0.00072747733648981239 V。
PI/限幅块复制测试的输出、积分状态与独立逐拍 old-state/AW/reset 方程误差均为 0。源 limiter 延迟记忆没有被统一清零。
实际首次速度 tick=0.00090000000000000008 s、位置 tick=0.0099 s；command 在 0 s 改变、applied 在 50 us 改变，关闭 PWM 后平均 vd/vq 为零。见 `pi_timing_acceptance.json`。
组合入口实际输出 `M1A_MATH_PASS`（job_10.log）。完整源/新闭环迁移和步长收敛仍待执行。


上述“待执行”属于原始历史检查点。数学/迁移/收敛已于原M1A交付完成，见[最终实施报告](../../../coordination/reports/m1a_pure_simulink_float_baseline.md)。上位机操作入口随后按[PR47修订报告](../../../coordination/reports/pr47_host_interface_revision.md)更新。
