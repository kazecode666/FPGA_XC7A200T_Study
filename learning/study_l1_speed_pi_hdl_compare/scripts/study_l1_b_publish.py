"""Publish only fresh, passing Checkpoint B evidence and untouched generated RTL."""
import csv
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]
ROOT = STUDY.parents[1]
model_run, vivado_run, xsim_run = map(lambda s: Path(s).resolve(), sys.argv[1:4])
generated = model_run / "generated/speed_pi_hdl"
report = STUDY / "reports/checkpoint_b"
baseline = STUDY / "generated_hdl/baseline"


def sha(path):
    with Path(path).open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        assert sha(source) == sha(target), f"Never overwrite an existing deliverable: {target}"
        return
    shutil.copyfile(source, target)
    assert sha(source) == sha(target)


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        assert path.read_text(encoding="utf-8") == value, f"Never overwrite: {path}"
        return
    with path.open("x", encoding="utf-8", newline="\n") as f:
        f.write(value)


preflight = json.loads((report / "workspace_preflight.json").read_text(encoding="utf-8"))
for category in ("user_files", "frozen_a_files"):
    for name, expected in preflight[category].items():
        path = ROOT / name
        assert (sha(path) if path.is_file() else None) == expected, name
compatibility = json.loads((model_run / "compatibility.json").read_text(encoding="utf-8"))
assert compatibility == []
status = json.loads((generated / "hdlcodegenstatus.json").read_text(encoding="utf-8"))
assert status["GenFileList"] == ["PI.sv", "HDLCore.sv"] and status["Latency"] == 2
model_log = (model_run / "matlab_run.txt").read_text(encoding="utf-8")
assert "FROZEN_PI_PARAMETERS_AND_WIRING_IDENTICAL" in model_log
assert "CARRIER_B1_ALL_14_RAW_CODES_EXACT rows=2580 ticks=258" in model_log
assert "PREFLIGHT_PASS" in model_log and "HDL_GENERATION_COMPLETE" in model_log
xsim_log = (xsim_run / "xsim.log").read_text(encoding="utf-8")
assert "STUDY_L1_XSIM_PASS rows=2580 ticks=258 fields=14 raw_mismatches=0" in xsim_log
assert "Fatal:" not in xsim_log and "Error:" not in xsim_log
metrics = json.loads((vivado_run / "metrics.json").read_text(encoding="utf-8"))
assert metrics["part"] == "xc7a200tfbg484-2" and metrics["clock_mhz"] == 50
assert metrics["WNS_ns"] >= 0 and metrics["WHS_ns"] >= 0
coverage = (vivado_run / "check_timing.rpt").read_text(encoding="utf-8")
for item in ("no_clock", "unconstrained_internal_endpoints", "no_input_delay", "no_output_delay", "loops", "latch_loops"):
    assert f"checking {item} (0)" in coverage
route_status = (vivado_run / "route_status.rpt").read_text(encoding="utf-8")
assert re.search(r"nets with routing errors\.+\s*:\s*0\b", route_status)
util = (vivado_run / "route_utilization.rpt").read_text(encoding="utf-8")
metrics["LUT"] = int(re.search(r"\| Slice LUTs\s*\|\s*(\d+)", util)[1])
assert int(re.search(r"\| Slice Registers\s*\|\s*(\d+)", util)[1]) == metrics["FF"]
trace = list(csv.DictReader((xsim_run / "trace.csv").open(encoding="utf-8")))
assert len(trace) == 2580 and sum(int(r["result_valid"]) for r in trace) == 258
assert all(int(r["time_ns"]) == int(r["row"]) * 100000 + 41 for r in trace)
assert all(r["result_valid"] == r["source_tick"] for r in trace)
assert all(".bit" not in p.name for p in vivado_run.iterdir())

for name in status["GenFileList"]:
    copy(generated / name, baseline / name)
copy(model_run / "speed_pi_hdl.slx", STUDY / "models/speed_pi_hdl.slx")
for name in ("compatibility.json", "generator_config.json", "pi_semantic_fingerprint.json"):
    copy(model_run / name, report / name)
copy(STUDY / ".runtime/b_final_preflight.json", report / "part_clock_preflight.json")
for name in ("synth_utilization.rpt", "synth_timing.rpt", "route_utilization.rpt", "route_timing.rpt",
             "critical_paths.rpt", "check_timing.rpt", "route_status.rpt", "drc.rpt"):
    copy(vivado_run / name, report / "verification" / name)
copy(xsim_run / "xsim.log", report / "verification/xsim.log.txt")
copy(xsim_run / "trace.csv", report / "verification/trace.csv")
copy(xsim_run / "trace.csv.cycles.csv", report / "verification/edge_trace.csv")
copy(xsim_run / "latency_reset.png", report / "verification/latency_reset.png")
copy(xsim_run / "hdl_carrier.png", report / "verification/hdl_carrier.png")
copy(model_run / "vectors.txt", report / "verification/vectors.txt")
copy(generated / "hdlcodegenstatus.json", report / "codegen/hdlcodegenstatus.json")
copy(generated / "HDLCore_map.txt", report / "codegen/HDLCore_map.txt")
copy(generated / "html/pages/speed_pi_hdl_sid_map.js", report / "codegen/speed_pi_hdl_sid_map.js")
for name in ("HDLCore_report.html", "speed_pi_hdl_trace.html", "speed_pi_hdl_clock.html",
             "speed_pi_hdl_bill_of_materials.html", "speed_pi_hdl_dut_information.html",
             "speed_pi_hdl_delay_balancing.html", "speed_pi_hdl_clock_rate_pipelining.html",
             "speed_pi_hdl_distributed_pipelining.html", "rtwreport.css", "rtwshrink.js"):
    copy(generated / "html/pages" / name, report / "codegen" / name)
write(report / "codegen/generator_parameters.txt", status["ModelGenStatus"]["CLI"])
write(report / "verification/generation_excerpt.txt", "\n".join(
    line for line in model_log.splitlines() if line.startswith(("MATLAB=", "FROZEN_", "CARRIER_", "CLOCK_", "RESET_", "PREFLIGHT_", "HDL_GENERATION_", "###"))))

anchors = {}
def line(file, token):
    rows = (baseline / file).read_text(encoding="utf-8").splitlines()
    return next(i + 1 for i, row in enumerate(rows) if token in row)

mapping = [
    ("Error", "PI.sv", "assign Error_out1", "v_ref - v_meas; signed33/20"),
    ("P", "PI.sv", "assign P_mul_temp", "Kp raw=19363296; convergent cast to signed40/30"),
    ("KiTs", "PI.sv", "assign KiTs_mul_temp", "KiTs raw=1549064; signed40/30 increment"),
    ("PreviousExcess", "PI.sv", "begin : PreviousExcess_process", "UnitDelay of unlimited-limited; semantic reset does not clear it"),
    ("AW", "PI.sv", "assign AW_mul_temp", "Kaw raw=85899346 times previous excess"),
    ("Update", "PI.sv", "assign Update_op_stage1", "old integrator + KiTs - AW; signed44/30 accumulation"),
    ("Integrator", "PI.sv", "begin : Integrator_process", "sample-event CE state register; int-reset selection before update"),
    ("IntegratorLimit", "PI.sv", "assign IntegratorLimit_out1", "clip integral candidate to +/-0.5 A"),
    ("Unlimited", "PI.sv", "assign Unlimited_add_temp", "P + old integrator; signed42/30 output"),
    ("OutputLimit", "PI.sv", "assign OutputLimit_out1", "clip to +/-1 A before excess and external output conversion"),
    ("OutputFormat", "PI.sv", "assign OutputFormat_out1", "convergent signed25/15 FOC boundary"),
    ("Hard", "PI.sv", "assign Hard_out1", "angle_init | pi_reset | test_mode | !enable"),
    ("Int", "PI.sv", "assign Int_out1", "hard | ref-zero | strict overspeed predicate"),
    ("HardReset", "PI.sv", "assign HardReset_out1", "hard reset forces iq reference zero on that valid transaction"),
    ("Tick", "PI.sv", "begin : Tick_delay", "rising-edge tick detector; initialization reset has priority"),
    ("CE", "PI.sv", "assign enb_gated", "clk_enable AND detected speed event; idle state hold"),
    ("OutputHold", "PI.sv", "begin : iq_ref_A_hold_process", "registered output, configured output pipeline absorbed into hold register"),
    ("InputPipeline", "HDLCore.sv", "begin : in_0_pipe_process", "one physical input-register stage, all controls/data aligned"),
    ("ce_out", "HDLCore.sv", "assign ce_out", "global CE; use delayed sample-event valid for result qualification"),
]
for block, file, token, description in mapping:
    anchors[block] = dict(file=file, line=line(file, token), token=token, meaning=description)
write(report / "traceability.json", json.dumps(anchors, ensure_ascii=False, indent=2))
created = re.search(r"// Created: (.+)", (baseline / "HDLCore.sv").read_text())[1]
summary = dict(status="PASS", checkpoint="B", base_main=preflight["main"],
               MATLAB="26.2.0.3386108 (R2026b)", HDL_Coder="26.2", HDL_Verifier="26.2",
               language="SystemVerilog", generation_local_time=created, timezone="Asia/Hong_Kong",
               golden_B1_sha256=sha(STUDY / "models/speed_pi_fixed.slx"),
               carrier_sha256=sha(STUDY / "models/speed_pi_hdl.slx"),
               generated_sha256={n: sha(baseline / n) for n in status["GenFileList"]},
               vector_sha256=sha(model_run / "vectors.txt"),
               semantic_graph_identical=True, carrier_all_14_raw_exact=True,
               xsim_rows=2580, xsim_ticks=258, xsim_fields=14, raw_mismatches=0,
               first_tick_us=900, update_period_us=1000, pipeline_cycles=2,
               launch_to_valid_ns=40, update_interval_physical_cycles=50000,
               sustain_high_tick_single_event=True, global_CE_idle_hold=True,
               metrics=metrics, user_files_preserved=len(preflight["user_files"]),
               frozen_A_files_preserved=len(preflight["frozen_a_files"]),
               model_run=str(model_run), vivado_run=str(vivado_run), xsim_run=str(xsim_run),
               timing_scope="OOC registered IP core; package/board I/O routing not claimed",
               checkpoint_C_started=False, handwritten_PI=False, bitstream=False, hardware=False)
write(report / "summary.json", json.dumps(summary, ensure_ascii=False, indent=2))
manifest = f"""# HDL Coder baseline manifest

Generated SystemVerilog is copied byte-for-byte from the passing fresh run. Do not edit these files; change the HDL-facing model/configuration and regenerate.

| Item | Recorded value |
|---|---|
| MATLAB | R2026b GA / 26.2.0.3386108 |
| HDL Coder / HDL Verifier / Simulink | 26.2 / 26.2 / 26.2 |
| Language | SystemVerilog |
| Frozen numerical source | `models/speed_pi_fixed.slx` from merged PR38 |
| B1 SHA256 | `{summary['golden_B1_sha256']}` |
| HDL-facing source | `models/speed_pi_hdl.slx` |
| DUT / top | `speed_pi_hdl/HDLCore` / `HDLCore` |
| Part | `xc7a200tfbg484-2`, audited from all four existing XPR files and installed Vivado part database |
| Clock | one physical 50 MHz / 20 ns clock; speed events first at 0.9 ms, then every 1 ms |
| Clock/reset ports | `clk`, synchronous active-high `init_reset`, `clk_enable`; sampled `pi_reset`, `enable`, `sample_tick` |
| Boundary pipeline | InputPipeline=1, OutputPipeline=1; Coder reports 2 cycles |
| Valid alignment | source launch just after edge k -> input capture k+1 -> PI/output hold k+2; 40 ns in the testbench |
| Update interval | 50,000 physical clocks; sustained-high tick is one event |
| Generation timestamp | {created}, Asia/Hong_Kong |
| Generation base commit | `{preflight['main']}`; generator script/config are included in this checkpoint commit |
| Timing scope | non-project OOC IP core, 2 ns interface budgets, BUFGCTRL_X0Y0 clock-source assumption |

Generation: `study_l1_run_hdlcoder(freshRunDirectory)` calls `checkhdl('speed_pi_hdl/HDLCore')` before `makehdl`. [Exact configuration](../../reports/checkpoint_b/generator_config.json), [all effective parameters](../../reports/checkpoint_b/codegen/generator_parameters.txt), [native generation status/latency](../../reports/checkpoint_b/codegen/hdlcodegenstatus.json).

TargetLanguage=SystemVerilog, TargetFrequency=50, TriggerAsClock=off, ResetType=Synchronous, Traceability=on, GenerateValidationModel=on. Resource sharing/adaptive/distributed pipelining are not enabled. Delay balancing/absorption handles the two boundary pipeline settings. EDAScriptGeneration=off avoids the default unrelated-device EDA sample template; execution uses `scripts/study_l1_vivado_baseline.tcl` with the audited part.

| Untouched output file | SHA256 |
|---|---|
"""
for name, digest in summary["generated_sha256"].items():
    manifest += f"| [{name}]({name}) | `{digest}` |\n"
manifest += "\nHDL report pages, traceability, latency and resource metadata are preserved under `reports/checkpoint_b/codegen/`. The complete interactive report and generated/validation SLX remain locally under the fresh run's `generated/speed_pi_hdl/` directory (temporary runtime contents are not committed).\n"
write(baseline / "MANIFEST.md", manifest)

table = "\n".join(f"| {block} | [{file}:{anchors[block]['line']}](../../generated_hdl/baseline/{file}#L{anchors[block]['line']}) | {description} |"
                  for block, file, _, description in mapping)
walkthrough = f"""# Study-L1 Checkpoint B：从冻结 B1 读到生成 RTL

本次 baseline 已通过 fresh verification。生成 RTL 对同一组 2580 样本 / 258 speed tick 的 14 项 B1 raw code 全部一致；50 MHz OOC 核级布线 WNS={metrics['WNS_ns']:+.3f} ns。B1 数值模型、previous excess、reset/enable 和 anti-windup 均保持冻结。

## 先打开这四个入口

1. [冻结 B1 datatype table](../checkpoint_a/datatype_table.md)：先看位宽、小数位、Convergent 舍入和 Saturate 溢出。
2. [HDL-facing Simulink 模型](../../models/speed_pi_hdl.slx)：打开 `speed_pi_hdl/HDLCore/PI` 阅读与 B1 相同的图。
3. [生成顶层 HDLCore.sv](../../generated_hdl/baseline/HDLCore.sv)：看输入寄存器和时钟接口。
4. [生成 PI.sv](../../generated_hdl/baseline/PI.sv)：看运算、状态寄存器与输出保持。

![HDL-facing carrier](verification/hdl_carrier.png)

Carrier 复制冻结 B1，仅显式规定根输入类型、把 tick 承载改为 boolean、把外部算法 reset 命名为 `pi_reset`，并增加可选为 DUT 的 `HDLCore`。PI 内部所有模块参数及连线逐项一致，见 [semantic fingerprint](pi_semantic_fingerprint.json)。新模型在 Simulink 中与 B1 的全部 14 项输出逐样本 raw-exact；B1 文件没有保存或重建。

## 先分清时钟、sample tick 和两个 reset

`clk` 始终是 50 MHz。`clk_enable` 是全局流水线 CE，本测试常态为 1。`sample_tick` 是输入事务的 rising-edge 事件：第一拍 0.9 ms（45,000 个物理周期），之后 1 ms（50,000 周期）。保持 tick 为高不会重复积分；没有 tick 时，`pi_reset` 或 disable 不更新 PI 状态。

生成头部的 100 us 是源模型的 logical base rate。`TreatRatesAsHardwareRates=off`；RTL 每个物理时钟可承载一个逻辑输入，testbench 每 5000 clocks 才更换一个原测试向量。1 ms 的积分系数 `Ki_ASR*Ts_ASR` 保持原值，不因 50 MHz 而改成 `Ki/50e6`。

`init_reset` 是 HDL 同步上电/初始化 reset：优先于 CE，清初始化状态及流水线。算法的 `pi_reset` 与 `enable` 是随输入数据对齐的命令，只在 speed 事件上参与 hard/int reset。日常算法 reset 应送 `pi_reset`，它不清 PreviousExcess；使用 `init_reset` 会重新初始化整个核。

上电期间保持 `sample_tick=0`，释放 `init_reset` 后先运行至少两个 CE 周期，再开始首 speed 事件。这使输入 pipeline 和初始化为 1 的内部 tick-delay 完成低电平建立；本测试在 0.9 ms 首事件前完成该建立过程。

`ce_out` 直接等于全局 CE，并不是“每 1 ms 有新结果”。testbench 把源 tick 的 rising-edge 事件经过两个受 CE 控制的 valid 寄存器，形成 `result_valid`，与 Coder 的两级边界 latency 对齐。global CE 暂停时必须以 CE 同步保持这个 valid 管线。

## 沿数值路径阅读

有效事务仍计算：`e=ref-meas`、`u=Kp*e+x_old`、`l=clip(u,±1)`、`d_next=u-l`、`candidate=clip(x_old+KiTs*e-Kaw*d_old,±0.5)`。`iq_ref=hard?0:l`，`x_next=int_reset?0:candidate`。状态更新使用上一 tick 的 excess；输出使用旧积分状态。

| Model 中的对象/功能 | 生成 RTL 入口 | 阅读重点 |
|---|---|---|
{table}

乘法后的长表达式先检查饱和，再取小数位、guard/sticky/保留最低位实施 ties-to-even。比如 P 的 `[19]` 是 guard bit，`[20]` 是保留的最低位，`|[18:0]` 表示丢弃部分是否还含 1。负数按补码和符号扩展处理，不能把切片视为无符号截断。三个 coefficient 的 raw 值分别为 19363296、1549064、85899346，与冻结 B1 完全相同。

内部 `OutputLimit_out1` 保持 signed42/30 的 ±1 A，Excess 从这个内部限幅结果相减。外部 signed25/15 的 iq_ref 转换位于其后；外部舍入误差没有被反馈到 anti-windup。积分 candidate 在 signed44/30 上累加/相减，先限到 ±0.5 A，再转 signed32/30。

## 两级 latency 如何对齐

源数据在边沿 k 后推出；k+1 输入寄存器同时捕获 data、tick、enable、pi_reset；k+2 检测内部 tick 事件，提交状态并把使用旧状态计算的结果写入 output-hold register。该保持寄存器吸收了配置的输出 pipeline。对齐定义是从源 launch 到有效结果两个时钟周期，即 40 ns；从输入实际捕获边沿 k+1 到 k+2 则是一周期。XSim 在 k+2 后再等 1 ns 消除 NBA 观察竞争，CSV 因而记录 41 ns，额外 1 ns 是测试观察延迟。

首源 tick 仍在 0.9 ms，首有效输出在 0.900040 ms。后续有效输出仍每 1 ms 一次。没有增加一个 1 ms 状态延迟，也没有改变 previous-excess 的 tick 序号。

![实际 XSim 逐边沿记录](verification/latency_reset.png)

左图是首次 +2 mm/s 命令：输出为 1182 raw / 32768 ≈0.03607 A，积分寄存器此时提交下一状态。右图是饱和 reset：iq_ref 从 1 A 归零，积分寄存器从 0.5 A 归零，previous-excess 寄存器仍约 1.5 A。图使用 [edge_trace.csv](verification/edge_trace.csv) 的实际边沿记录（edge+2 ns），未重构 PI 波形。

## 从生成 HDL 到实际 FPGA 资源

器件取自四个现有工程 XPR 的 `Part` 属性，并通过 Vivado 2026.1 的安装 part 数据库预检，见 [part/clock preflight](part_clock_preflight.json)。本模块保留 14 个诊断输出，因此执行 non-project OOC 核级 synthesis → opt → place → route；不加入板级引脚。数据/控制输入及输出预算各 2 ns，clock source 假设为 BUFGCTRL_X0Y0，所有内部路径按 20 ns 单周期检查，无 false/multicycle path。

| Fresh post-route 项目 | 数值 |
|---|---:|
| LUT | {metrics['LUT']} |
| FF（Slice Registers） | {metrics['FF']} |
| DSP48E1 | {metrics['DSP48']} |
| BRAM | 0 |
| WNS / WHS | {metrics['WNS_ns']:+.3f} / {metrics['WHS_ns']:+.3f} ns |
| Coder latency | 2 cycles / 40 ns launch-to-valid |
| 有效 PI update interval | 50,000 clocks / 1 ms |

确实使用了 10 个 DSP48E1，数量来自布线后的 netlist。宽乘法可以拆成多个 DSP；不能将一个 Simulink Gain 当作一个 DSP。Vivado 还可把状态寄存器吸收到 DSP 输入寄存器，因此 Slice FF 数不等于生成文件中所有 logic 位宽的简单总和。

最差路径是输入寄存器 `v_ref_mmps_1_reg[1]/C` 到 `u_PI/AW_mul_temp__1/A[13]` 的寄存器路径；数据延迟 19.368 ns、36 级逻辑。沿 error/P、output limit、excess 的反馈路径到 DSP 中的状态寄存器，见 [critical_paths.rpt](verification/critical_paths.rpt)。[route_utilization.rpt](verification/route_utilization.rpt)、[route_timing.rpt](verification/route_timing.rpt)、[check_timing.rpt](verification/check_timing.rpt)、[route_status.rpt](verification/route_status.rpt) 是实际报告。

时钟缺失、内部 unconstrained endpoints、输入/输出 delay 缺失、组合环与 latch loop 均为 0；所有可路由内部 net 已布线、routing errors=0。OOC 仍报告端口未绑定 HD.PARTPIN_LOCS，因此这些数字用于核内部的注册边界；不宣称 package/board I/O routing 的时序。

首次无寄存器边界检查暴露了输入→excess 组合路径；完整输入/输出延迟约束下 WNS=-2.622 ns。只通过 InputPipeline=1/OutputPipeline=1 建立明确边界，未调整运算、位宽或 PI 参数，未开启 adaptive/resource sharing/distributed pipelining。早期 XDC 输入约束被拒绝的结果已排除；最终门槛同时检查 coverage 和 slack。Coder 默认 EDA sample template 的其他器件设置也已从生成配置禁用，实际执行的是 [核级 Tcl](../../scripts/study_l1_vivado_baseline.tcl)。

## Report / 复现 / 停止点

[原始 HDL compatibility report](codegen/HDLCore_report.html)、[traceability report](codegen/speed_pi_hdl_trace.html)、[clock report](codegen/speed_pi_hdl_clock.html)、[Coder resources](codegen/speed_pi_hdl_bill_of_materials.html)、[delay balancing/absorption](codegen/speed_pi_hdl_delay_balancing.html) 已保留。完整交互 HTML、生成模型 `gm_speed_pi_hdl.slx`、验证模型 `_vnl.slx` 保留在本机 `.runtime/b_fresh_final_02/generated/speed_pi_hdl/`；该目录的全部缓存不会提交。验证模型已生成，本次 bit-exact 验收使用实际 XSim RTL。

复现命令和 vectors 字段见 [CHECKPOINT_B.md](../../CHECKPOINT_B.md)。生成文件的 SHA256、版本、源模型及配置见 [MANIFEST](../../generated_hdl/baseline/MANIFEST.md)。[summary.json](summary.json) 与 [XSim log](verification/xsim.log.txt) 记录 fresh 结果。

287 项用户本地文件和 34 项 Checkpoint A 文件全部保持原哈希/缺失状态。只完成 Checkpoint B；提交与 GitHub 汇报后 STOP，等待 ChatGPT Review。没有 Hand SV speed PI、Checkpoint C、bitstream 或硬件操作。
"""
write(report / "hdl_coder_walkthrough.md", walkthrough)
print("CHECKPOINT_B_PUBLISHED", json.dumps(metrics), "generated files byte-identical")
