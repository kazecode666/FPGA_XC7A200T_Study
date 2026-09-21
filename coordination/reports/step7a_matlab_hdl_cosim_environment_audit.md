# Step 7A — MATLAB / Vivado HDL co-simulation 环境审计

审计日期：2026-09-21。主分类：**A READY_NOW**。

本机 **MATLAB 26.2.0.3340147 (R2026b) Prerelease Update 3 + Vivado Simulator 2026.1** 已完成真实 MATLAB ↔ HDL 数据往返。不是 R2026b 正式版验证，也不是完整 FOC/Simulink 联合仿真验收。

## 1. 工作目录与保护范围

- 唯一主工作树：`D:/Project/FPGA_XC7A200T`；远端 `https://github.com/kazecode666/FPGA_XC7A200T_Study.git`。
- 初始分支 `step6e-complementary-pwm`，提交 `e1c5dd4`。fetch 后确认与远端 main 的内容差异仅为 HANDOFF 和 Step 7A 任务书；在同目录正常切换到 `step7a-matlab-hdl-cosim-audit`，基于 `9844229ec0057dadbea9af7af1cef7020bebdec5`。
- 初始已有资料文件删除、四个 XPR 修改以及旧仿真未跟踪结果；均保留，不纳入本 PR。未创建 worktree/clone，未修改已有 RTL/TB/FOC/PWM 工程。
- 最小示例仅在系统 TEMP 的独立目录创建。报告在本仓库；没有安装/卸载软件、修改全局 PATH、永久 MATLAB 首选项或清理文件。

## 2. Environment matrix

| Component | Installed/version | License usable | Required for current co-sim? | Result |
|---|---|---|---|---|
| MATLAB | R2026b Prerelease Update 3 / 26.2.0.3340147 / PCWIN64 | batch 与真实交换成功 | 是 | PASS，非正式版 |
| Simulink | 26.2 (R2026b) | checkout=1；load_system 成功 | Simulink 路径需要；本次交换使用 MATLAB | PASS |
| SoC Blockset | 26.2 (R2026b) | SoC_Blockset checkout=1 | 此最小 HDL 仿真不需要 | 产品可用，AMD 专用集成未验证 |
| SoC Blockset Support Package for AMD FPGA and SoC Devices | 当前 release 未识别，版本不可取得 | 不适用 | 本次无板卡 XSI 仿真未依赖它 | 缺失/未注册，需单独澄清 |
| HDL Verifier | 26.2 (R2026b) | EDA_Simulator_Link checkout=1；实际 co-sim 成功 | 是 | PASS |
| HDL Coder | 26.2 (R2026b) | Simulink_HDL_Coder checkout=1 | 已有 HDL 的 co-sim 不要求重新生成 HDL | PASS，未做代码生成 |
| Fixed-Point Designer | 26.2 (R2026b) | fixed_point_toolbox checkout=1；fi 与交换成功 | 本次定点端口需要 | PASS |
| Vivado Simulator | 2026.1 / SW Build 6511674 | Vivado 识别 BASIC 许可；仿真成功 | 是 | PASS，带版本警告 |
| Vivado 2024.1 / 2025.1.1 | 受检安装根目录与卸载注册表均未发现 | 未测试 | 当前最小验证不需要替换版本 | 未安装证据限于受检位置 |
| Vitis | 2026.1 / CLI SW Build 6497934 | 未做功能许可 checkout | 否 | 版本库存已确认 |

MATLAB 安装根：`D:/Program Files/MATLAB/R2026b_Prerelease`。PATH 中还存在 R2026a，所有本轮 batch 均显式调用 R2026b 启动器。Vivado/Vitis 启动器分别为 `E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat` 与 `E:/AMDDesignTools/2026.1/Vitis/bin/vitis.bat`。

许可启动提示本次 Prerelease 许可将在 **9 天后到期**；READY_NOW 仅指审计时刻，不保证到期后仍可运行。Vivado BASIC 提示有效至 2027-07-27。未读取或提交许可证文件、序列号、MAC、用户或主机标识。

## 3. AMD 支持包与产品能力

`matlab.addons.installedAddons`、`matlabshared.supportpkg.getInstalled`、实际支持包根目录的 `appdata/prodcontents.json` 三者一致：当前 `C:/ProgramData/MATLAB/SupportPackages/R2026bPrerelease` 仅登记 **MATLAB Support for MinGW-w64 C/C++/Fortran Compiler 26.2.2**。没有新 AMD 包，也没有旧 HDL Verifier AMD 包登记。R2026a 默认根元数据同样仅有 MinGW；未据此推断任意其他磁盘位置都不存在离线包。

这与用户“已更新支持包”的预期不一致：准确结论是**当前被审计 R2026b 会话未识别该包，不能报告其安装版本**。没有自动安装或修复。

HDL Verifier 产品层的 `cosimWizard`、`cosimulationConfiguration`、`hdlcosim`、`hdlverifier.VivadoHDLCosimulation`、`vivadosimlib.slx` 和 XSI MEX 均存在。`hdldaemon` 也存在，但本次采用 Vivado XSI/设计 DLL，不要求手工启动 daemon。板卡支持包与这些 simulator 能力分属两层；本次交换成功证明缺少 AMD 板卡包没有阻止这个最小无硬件用例。

SoC 产品中存在 Zynq/Zynq UltraScale+ MPSoC 相关入口/示例，但未证实 AMD 板卡注册和 SoC 工具链可用。Vitis 只执行版本查询，没有创建 workspace、XSA、BSP 或迁移工程。

## 4. Official-vs-local compatibility

- [MathWorks R2026b 变更说明](https://www.mathworks.com/products/new_products/pr-transition.html)及[AMD 支持包页面](https://www.mathworks.com/add-ons/XILINX_BLOCKSET/)说明旧 AMD support-package 能力并入 SoC Blockset AMD 包；合并不替代 HDL Verifier 产品许可。
- [公开 HDL Verifier 支持工具表](https://www.mathworks.com/help/hdlverifier/gs/supported-eda-tools.html)在本次查询时仍推荐/完整测试 **Vivado 2024.1**。
- 本机 R2026b 本地 `help` 明确列出 Vivado Simulator、MATLAB System Object 和 Simulink 工作流。完整本地 HTML 文档未安装，不能声称读过其支持版本表。
- `hdlsetuptoolpath` 对 2026.1 设置成功；这只证明路径可设置，不等同版本支持。
- **实际 `cosimulationConfiguration/runWorkflow` 版本检测推荐 2025.1.1**，对 2026.1 给出未充分测试警告后继续。没有 hard reject，没有抑制警告、patch 或绕过检查。该本地 prerelease 结果与公开表应分别保留，不能把 2024.1 当作本机唯一版本规则。
- `PATH` 和 `XILINX_VIVADO` 旧值在各 batch 中保存并恢复；PATH 恢复断言为 1。官方[工具路径说明](https://www.mathworks.com/help/hdlcoder/ref/hdlsetuptoolpath.html)说明该函数只影响当前 MATLAB 会话；未写 startup.m 或用户/系统 PATH。

原始检测文本见 [matlab_vivado_detection.txt](../../docs/reports/step7a/matlab_vivado_detection.txt)，完整脱敏流程见 [minimal_workflow_log.txt](../../docs/reports/step7a/minimal_workflow_log.txt)。

## 5. Minimal co-sim proof

采用本地可用的命令行 Wizard 等价接口，流程为 `cosimulationConfiguration('Vivado Simulator','MATLAB System Object','cosim_counter')` → `runWorkflow` → 生成 `hdlcosim_cosim_counter` → MATLAB 调用对象 → XSI 运行 Vivado 生成的 `xsim.dir/design/xsimk` → 返回真实 HDL 输出。未拿 MATLAB 计算值冒充 simulator 输出。

HDL 为 8 位寄存器：下降沿异步低有效复位，时钟上升沿 `out_data <= in_data + 1`。复位/时钟由 MATLAB 作为普通输入端口显式驱动。对象 SampleTime 为 10 ns，HDL 精度 1 ps：tick 0–2 保持复位低和时钟低，确认返回 0；tick 3 开始释放复位。每个输入执行 clk=`0,0,1,1,0`，保持数据稳定，在上升沿后检查。上升沿调用 tick 为 5、10、15、20、25、30，相隔 50 ns。tick 是对象调用索引，不声称为额外测量的 HDL 时间戳。

| MATLAB 输入 | HDL 返回 | 断言 |
|---|---|---|
| 0 | 1 | PASS |
| 1 | 2 | PASS |
| 42 | 43 | PASS |
| 127 | 128 | PASS |
| 254 | 255 | PASS |
| 255 | 0 | PASS，8 位回绕 |

结果标记：`REAL_COSIM_EXCHANGE=PASS`。逐调用输入/输出见 [minimal_cosim_result.txt](../../docs/reports/step7a/minimal_cosim_result.txt)，复现步骤见 [reproduction.md](../../docs/reports/step7a/reproduction.md)。这证明 **MATLAB ↔ Vivado Simulator** 路径；Simulink 产品和许可已验证，但没有另运行 Simulink co-sim 模型，不扩展此结论到完整电机闭环。

首轮由审计脚本生成数值常量时错误处理转义，导致 `VRFC 10-9623 unexpected non-printable character 0xe2`。修正为普通整数后，在全新 TEMP 示例目录重跑通过；该已排除的示例错误不是版本兼容根因。未改 MathWorks 或项目 RTL。TEMP 原始产物保留，未提交 HDL/cache。

## 6. Classification 与下一步

**A READY_NOW**：本次 R2026b Prerelease + 当前 Vivado 2026.1 最小真实数据交换成功，因此不归为 B，也没有证据要求立即并装旧 Vivado。AMD 支持包未识别是独立缺项，未阻止本次 simulator 用例，因此不把它当成本次必需依赖而归为 C。

建议保留 2026.1。后续若用户启动新阶段，再设计 Simulink/HDL 接口并独立验证 Simulink 路径；在需要 AMD 板卡/SoC 功能前澄清支持包安装所属 release。Prerelease 许可到期或更换 MATLAB build 后应重测。

本轮仅提交审计报告与文本证据，停在开放 PR。未开始完整 FOC/Simulink 联合仿真、Vitis/SoC 迁移或硬件操作。

提交前检查：`git diff --check` 与 `git diff --cached --check` 均通过；暂存区仅包含本报告及 10 个 Step 7A 文本/Markdown 证据文件。暂存内容已检查用户路径标识并脱敏 TEMP 路径。原始 batch 日志和辅助命令文本留在本地未跟踪，不进入 PR。
