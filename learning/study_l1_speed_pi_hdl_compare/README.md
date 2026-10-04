# Study-L1 / Checkpoint A

只完成 A1（真实 PI 审计）、A2（独立浮点对照）、A3（B1/B2 定点模型）。等待 ChatGPT Review 才能进入 B。

| 文件 | 用途 |
|---|---|
| models/speed_pi_float.slx | 独立 double PI，以原模型旧状态/上一 excess 语义重建 |
| models/speed_pi_fixed.slx | B1，后续 HDL Coder / 手写 SV 唯一 golden model |
| models/speed_pi_fixed_b2.slx | B2，缩短位宽的数值候选 |
| models/speed_pi_compare_tb.slx | 保存真实 PI 副本、真实 scheduler/function-call 源，与三种独立实现共用输入 |
| reports/checkpoint_a/current_speed_pi_audit.md | 来源路径、SID、离散方程、复位与调度 |
| reports/checkpoint_a/datatype_table.md | 每个信号的范围、位宽、小数位、舍入、溢出规则 |
| reports/checkpoint_a/float_fixed_comparison.md | A2/A3 数值验收结果 |
| reports/checkpoint_a/verification/ | 最终 fresh verification 的精简证据 |

## 运行已有模型

在独立 MATLAB R2026b 进程执行，避免影响用户当前打开或未保存的模型：

```matlab
addpath('D:/Project/FPGA_XC7A200T/learning/study_l1_speed_pi_hdl_compare/scripts');
study_l1_probe;
study_l1_run_checkpoint_a; % 每次创建全新 fresh_ 时间戳报告目录
```

需要 Simulink 和 Fixed-Point Designer；本阶段不调用 HDL Coder。
本次 R2026b MCP 指向已不存在的 Prerelease 可执行文件，验证改用真实 `D:/Program Files/MATLAB/R2026b/bin/matlab.exe` 的独立 batch 进程；正式版、版本和许可证检查通过，未修改 MCP 或用户全局配置。
输入由 `study_l1_generate_vectors` 产生，并通过 SimulationInput 显式注入，不依赖 base workspace 的历史数据。
保存的三个学习模型具有7个输入：速度参考、速度反馈、enable、reset、sample_tick、angle_init、test_mode。
后两个默认使用0向量；reset 对应原模型有效 PI_Reset_EN_cmd，包含整机 PWM disable 门控后的意义。
sample_tick 是脉冲上升沿，与实际 speed task 同相：首拍0.9 ms、周期1 ms。

输出同时给出当拍旧 `integrator_A` 和已计算但下一 tick 才作为状态输出的 `integrator_next_A`。
这一区分解释了为什么 reset 当拍输出会清零，而旧积分状态观测值仍可能非零。
`iq_limited_A` 位于 hard reset 门控之前；`iq_ref_A` 位于其之后。
饱和检测基于内部限幅，而非输出转换后的 raw code 是否恰好等于 ±32768。
回归脚本还分别运行三份 standalone SLX，采用 Dataset 明确提供 boolean 控制量和 double tick；float速度为double，fixed速度先按相应输入格式量化为fi，以匹配根级端口约束。

## 从实际源 SLX 重建（可选）

```matlab
study_l1_build_models('D:/Project/FPGA_XC7A200T/learning/study_l1_speed_pi_hdl_compare/.runtime/my_unique_build');
study_l1_run_checkpoint_a( ...
 'D:/Project/FPGA_XC7A200T/learning/study_l1_speed_pi_hdl_compare/reports/checkpoint_a/fresh_my_unique_run', ...
 'D:/Project/FPGA_XC7A200T/learning/study_l1_speed_pi_hdl_compare/.runtime/my_unique_build');
```

必须选择新目录；构建器拒绝覆盖已有模型。它只加载真实源 SLX、读取实际 ModelWorkspace 数值、复制 PI 与调度器，不保存源模型。
构建器先验证 float/A2 并记录范围，再建立、验证 B1，B1 通过后才建立 B2；这些中间证据写入新构建目录的 `stage_verification/`。
源 SLX 已在用户本地修改，Git 的旧源模型可能具有不同快照哈希；保存的 compare_tb 是本次已验证源副本，后续 Review 可以直接复跑。
源码生成器保留同一参数检查，若新的源参数不同就明确报错。

## 学习要点

1 ms 是状态更新周期，不代表 FPGA 需要1 kHz物理时钟。之后会把同相 sample_tick 作为50 MHz时钟域内的有效事件。
Ki 是连续增益，KiTs 才是每个离散速度样本的积分增量系数。
x 和上一拍 excess 都是状态；idle 时都保持。当前 reset 只门控下一 x 和 iq_ref，不能顺手清掉 excess。
B1 用内部30小数位降低累计量化误差，再显式转换为现有FOC的 signed25/15边界；B2 用较少位宽观察误差。
所有有损转换 convergent、存储溢出 saturate；算法限幅与存储限幅分别记录。
本阶段没有资源、RTL latency、时序或整机闭环结论。

## 工作树保护

`workspace_preflight.json` 记录原 branch、HEAD、main、status 与287个 tracked/untracked文件的哈希或缺失状态。
`study_l1_workspace_audit.py verify` 在提交前后逐文件检查这些用户本地内容。
只提交本目录，未执行 stash、reset、clean、删除、worktree 或 clone。
仿真缓存定向到本目录 `.runtime/`；初期产生在外层目录的本任务缓存已移入 `.runtime/early_cache/`，未移动任何 preflight 中已有的用户文件。
