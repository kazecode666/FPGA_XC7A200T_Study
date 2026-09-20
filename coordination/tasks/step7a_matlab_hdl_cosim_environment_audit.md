# Step 7A — MATLAB R2026b / AMD HDL 联合仿真环境审计

> 给 Codex：这是**只读环境审计 + 最小联通试验**，不是新控制器开发。必须在用户原始主项目目录工作，不创建 worktree/额外 clone，不修改已验收 FOC/PWM RTL，不安装/卸载软件，不改系统 PATH 或永久 MATLAB 首选项，除非用户之后明确批准。

**日期：** 2026-09-20  
**目标：** 判断当前 Windows 环境能否使用 MATLAB/Simulink R2026b 与 AMD Vivado Simulator 对已有 HDL 做联合仿真，并明确当前 Vivado 2026.1 是否可用、是否缺产品/许可/支持包、或是否需要并装官方测试版本 Vivado 2024.1。  
**用户现状：** MATLAB R2026b；已更新 SoC Blockset Support Package for AMD FPGA and SoC Devices；当前 FPGA 工程使用 Vivado 2026.1。  
**基线：** Step 6E 已合并，main=`dcbbd6f5744f5282cb00d38a301298dacb3007fe`。  
**当前官方事实：**
- R2026b 起，原 AMD HDL Coder / HDL Verifier / Embedded Coder / Deep Learning HDL Toolbox 的 AMD support-package 功能合并到 SoC Blockset Support Package for AMD FPGA and SoC Devices。
- support package 合并不等于自动拥有 HDL Verifier 产品许可；HDL co-simulation 仍属于 HDL Verifier 能力。
- MathWorks 当前 HDL Verifier 的 Vivado Simulator 推荐/完整测试版本仍为 AMD Vivado 2024.1；用户当前 Vivado 2026.1 必须以本机实测结果判断，不可默认兼容，也不可默认不兼容。

## 1. 工作目录和保护规则

先确认实际主目录与 Git 状态：

```text
D:/Project/FPGA_XC7A200T
```

记录但不修改：

```text
git rev-parse --show-toplevel
git worktree list --porcelain
git remote -v
git branch --show-current
git status --short
```

本任务**不需要创建实现分支来改 RTL**。若为了提交审计报告需要分支，可在同一 MAIN 建立 `step7a-matlab-hdl-cosim-audit`，但不新建另一个工作目录。

禁止：

- reset --hard / clean -fd；
- 自动 stash；
- 修改 C1–C4、Step6D/6E RTL/TB；
- 修改现有 FOC_Current / FOC_PWM / FOC_Gates 工程；
- 修改 Windows 全局 PATH；
- 安装/卸载 MATLAB、Vivado、support package 或许可证组件；
- 为绕过版本检查去 patch MATLAB/MathWorks 文件；
- 为了证明“能用”而降低错误级别或跳过工具的版本检测。

允许：

- 运行 MATLAB/Vivado 的只读版本、产品、许可、路径检查；
- 在系统临时目录创建最小 HDL 联通样例；
- 若 MATLAB API 需要临时设置工具路径，可先记录旧值，在当前 MATLAB 进程中修改并在结束前恢复；不得永久改变用户环境；
- 将文本结果保存到 `docs/reports/step7a/`。

## 2. 必须回答的 8 个问题

最终报告必须逐项回答：

1. 实际 MATLAB 是否确为 R2026b？完整版本/build/平台是什么？
2. 是否安装并可用：MATLAB、Simulink、SoC Blockset (for AMD)、HDL Verifier、HDL Coder、Fixed-Point Designer？
3. SoC Blockset Support Package for AMD FPGA and SoC Devices 的实际已安装版本是什么？是否被 R2026b 识别？
4. HDL Verifier 产品是否**实际可用且许可可 checkout**，而不是只看到 support package？
5. 当前机器上的 Vivado 路径和版本是什么？是否为 2026.1？是否还安装有 2024.1 或其他版本？
6. MATLAB R2026b 的本地帮助/工具检测是否接受 Vivado 2026.1 作为 HDL co-simulation simulator？
7. 一个最小、与项目无关的 HDL 示例能否完成 MATLAB/Simulink ↔ Vivado Simulator 的联合仿真握手和数据往返？
8. 根据证据，环境应分类为 A/B/C/D 哪一种：
   - **A READY_NOW**：R2026b + 当前 Vivado 2026.1 最小 co-sim 实际成功。
   - **B READY_WITH_SUPPORTED_VIVADO**：MATLAB/HDL Verifier/支持包齐全，但 2026.1 被版本检查拒绝或最小 co-sim 失败且证据指向版本兼容；建议并装官方测试的 2024.1，不替换现有 2026.1。
   - **C MISSING_COMPONENT_OR_LICENSE**：缺 HDL Verifier、Fixed-Point Designer、Simulink 或必要许可/支持包。
   - **D OTHER_BLOCKER**：其他明确环境问题，给出精确错误和最小修复方向。

不得用“看起来支持”“应该可以”作为结论。

## 3. MATLAB 安装与产品审计

优先使用 `matlab -batch`，生成纯文本日志；不要要求用户手动截图才能完成审计。

先定位 MATLAB：

Windows shell 中记录：

```bat
where matlab
where vivado
```

若 `where matlab` 找不到，按已知安装目录搜索启动器，但不要改 PATH。

运行一个 MATLAB batch 脚本，例如临时文件 `step7a_env_probe.m`，至少输出：

```matlab
fprintf("VERSION=%s\n", version);
fprintf("RELEASE=%s\n", version('-release'));
fprintf("MATLABROOT=%s\n", matlabroot);
disp(ver);

try
    a = matlab.addons.installedAddons;
    disp(a);
catch ME
    fprintf("installedAddons error: %s\n", ME.message);
end

disp(license('inuse'));
```

再对下列产品分别记录“是否出现在 ver、关键入口是否存在、能否实际调用到许可边界”：

- Simulink
- SoC Blockset
- HDL Verifier
- HDL Coder
- Fixed-Point Designer

**不要猜 MATLAB license feature 名称。** 若需要 `license('test',FEATURE)`，先从本地产品信息/MathWorks 本地帮助/实际报错中确认 feature 名称；否则以产品 `ver` + 关键 API 最小调用是否出现 license checkout 错误为依据。

保存：

```text
docs/reports/step7a/matlab_version_products.txt
docs/reports/step7a/matlab_addons.txt
docs/reports/step7a/matlab_license_observations.txt
```

不得记录序列号、license file 内容、用户名、MAC 地址等不必要信息；若日志自动包含敏感标识，提交前删去对应行。

## 4. AMD support package 审计

确认实际安装的是 R2026b 的：

```text
SoC Blockset Support Package for AMD FPGA and SoC Devices
```

记录：

- 名称；
- 版本；
- 安装状态；
- R2026b 是否将原 HDL Verifier AMD support-package 功能识别为已并入该包；
- 是否还有旧的 “HDL Verifier Support Package for AMD FPGA and SoC Devices” 残留，以及 MATLAB 如何处理它。

只读检查可使用：

- `matlab.addons.installedAddons`；
- 本地 Add-On 元数据；
- MathWorks 本地 help/doc；
- 若 `matlabshared.supportpkg.getInstalled` 在此版本公开可用，可读取；若不存在，不把它当错误。

不要卸载或重新安装 support package。

## 5. HDL Verifier / HDL co-simulation 能力探测

目标不是 FIL、AXI Manager 或板卡下载，而是：

```text
Simulink/MATLAB testbench  <->  Vivado Simulator 中已有 HDL
```

在 MATLAB 中搜索并记录当前版本实际存在的相关入口，不要依据旧版本函数名硬编码。至少通过 `which -all`、`help`、本地 doc 搜索确认：

- HDL Cosimulation / HDL Verifier app 或 block；
- Vivado Simulator 作为 simulator/toolchain 的入口；
- HDL simulator setup / tool path 配置入口；
- co-simulation daemon / wizard / generated model workflow（如果当前版本提供）。

可尝试的历史函数名只能作为探测项，例如：

```matlab
which -all hdldaemon
which -all hdlsetuptoolpath
which -all cosimWizard
```

若 R2026b 改名或改工作流，以本地文档为准，不把“旧函数不存在”直接判成“不支持”。

保存：

```text
docs/reports/step7a/hdlverifier_capabilities.txt
```

其中写明“产品能力”和“AMD board/support-package 能力”是两层，不混为一谈。

## 6. Vivado 安装与 MATLAB 兼容探测

记录所有实际 Vivado：

```bat
where vivado
vivado -version
```

若存在 AMD 安装根目录，枚举但不修改：

```text
E:/AMDDesignTools/...
C:/Xilinx/...
C:/AMD/...
```

只记录版本目录和可执行文件，不扫描无关用户文件。

重点：

1. 记录当前项目使用的 Vivado 2026.1 路径。
2. 查明机器上是否已有 2024.1。
3. 从 R2026b 本地帮助确认当前 release 对 Vivado Simulator 的推荐/支持说明；与 MathWorks 在线当前说明“推荐 2024.1”对照。
4. 让 MATLAB 对 2026.1 做其官方工具路径检测/设置试验。

若使用 `hdlsetuptoolpath` 或当前版本等价命令：

- 先读取/记录已有配置；
- 只在当前审计会话中指向 Vivado 2026.1；
- 捕获完整成功/警告/版本拒绝文本；
- 结束前恢复旧配置；
- 不改 Windows PATH。

如果 MATLAB 明确输出“unsupported version but may continue”与“hard reject”，报告中必须区分。

保存：

```text
docs/reports/step7a/vivado_inventory.txt
docs/reports/step7a/matlab_vivado_detection.txt
```

## 7. 最小 HDL 联通试验

只有在以下条件满足时执行：

- HDL Verifier 产品存在且许可可用；
- Simulink 和 Fixed-Point Designer 等所需产品可用；
- MATLAB 能找到一个 Vivado Simulator；
- 不需要安装新软件。

**不要拿完整 FOC 作为第一个联通测试。**

在系统临时目录创建一个独立最小工程，例如：

```systemverilog
module cosim_counter(
    input  logic       clk,
    input  logic       reset_n,
    input  logic [7:0] in_data,
    output logic [7:0] out_data
);
  always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) out_data <= 8'd0;
    else         out_data <= in_data + 8'd1;
  end
endmodule
```

要求：

- HDL 在 Vivado Simulator 中运行；
- MATLAB/Simulink 提供至少 4 个已知输入；
- 输出必须逐项得到 `input+1`；
- 明确记录时钟和 reset 的时间关系；
- 联通成功必须来自真实 co-simulation 数据交换，不是 MATLAB 单独计算 + HDL 单独仿真各自通过。

优先使用 R2026b 本地文档推荐的 HDL Verifier/Vivado co-sim 工作流。可以通过 GUI Wizard 配置一次，但尽量把可复现命令/模型保存为文本说明；不要改主项目。

如果 Vivado 2026.1 失败：

- 保存第一处根因错误；
- 不 patch 版本检测；
- 如果机器已经有 2024.1，可在**不改变默认 Vivado 2026.1 项目环境**的情况下，用 2024.1 对同一最小样例再试一次；
- 如果机器没有 2024.1，不自动安装，分类为 B 或其他合适状态并停止。

保存：

```text
docs/reports/step7a/minimal_cosim_result.txt
```

若未执行，必须写明未执行原因，而不是留空。

## 8. SoC / Vitis 只做库存，不展开实施

本轮只记录：

- 当前 Vitis 是否安装、版本和路径；
- SoC Blockset for AMD 能否识别现有 AMD toolchain；
- 是否有 Zynq/MPSoC 相关支持入口。

不要：

- 新建 Vitis workspace；
- 导出/修改 XSA；
- 配 Linux/BSP；
- 建 AXI/PS-PL 工程；
- 开始 MPSoC 迁移。

这只是为了后续路线图知道本机环境，不影响本轮 HDL co-sim 判定。

保存：

```text
docs/reports/step7a/vitis_soc_inventory.txt
```

## 9. 最终报告

创建：

```text
coordination/reports/step7a_matlab_hdl_cosim_environment_audit.md
```

必须包含：

### A. Environment matrix

| Component | Installed/version | License usable | Required for current co-sim? | Result |
|---|---|---|---|---|

至少包括 MATLAB、Simulink、SoC Blockset (for AMD)、AMD support package、HDL Verifier、HDL Coder、Fixed-Point Designer、Vivado 2026.1、Vivado 2024.1（若存在）、Vitis。

### B. Official-vs-local compatibility

明确写：

- R2026b support-package 合并事实；
- HDL co-sim 是否仍需要 HDL Verifier 产品；
- 当前 MathWorks 官方测试 Vivado 版本；
- 本机 2026.1 的实际探测结果。

### C. Minimal co-sim proof

写清：

- 是否真正完成 MATLAB/Simulink ↔ Vivado Simulator 数据交换；
- 使用哪个 Vivado；
- 输入/输出；
- 失败则给第一根因错误，不给一堆次生错误。

### D. Classification

只能给 A/B/C/D 中一个主分类；如果有次要问题另列。

### E. Recommended next action

只能基于证据建议，例如：

- A：保留 2026.1，下一步开始设计 Simulink 电机模型 ↔ HDL FOC 的接口；
- B：保留 2026.1 做正常 Vivado 开发，另并装 2024.1 专供 HDL Verifier co-sim；
- C：补齐具体缺失产品/许可后再测；
- D：修复具体环境问题再复测。

**不要自动执行建议中的安装/许可变更。**

## 10. 完成方式

这是环境审计，不修改控制器源码。

完成后：

1. `git diff --check`；
2. 仅提交审计任务范围内的 Markdown/文本报告，不提交临时 HDL/Vivado/MATLAB cache；
3. 若产生大量机器绝对路径日志，只保留必要工具路径；删除用户名等敏感信息；
4. 开 PR：

```text
Step 7A: Audit MATLAB R2026b HDL co-simulation environment
```

5. 停在开放 PR 等待 ChatGPT Review；
6. 不开始把完整 FOC 接进 Simulink，除非环境审计 PR 合并并由用户明确启动下一阶段。
