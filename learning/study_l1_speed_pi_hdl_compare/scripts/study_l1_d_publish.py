"""Publish completed fresh D evidence; never replace source or user files.

Run only after all nine final system simulations and fresh actual-B1 replays
have completed. Native models, MAT files, caches and XSI binaries stay local.
"""
import argparse
import csv
import hashlib
import json
import math
import re
import subprocess
import sys
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]
ROOT = STUDY.parents[1]
SCENARIOS = ("speed_ideal", "speed_deadtime", "convergence_prefix")
IMPLEMENTATIONS = ("original", "coder_baseline", "hand_sv")
CASE_FILES = ("case_metrics.json", "trace.csv", "speed_events.csv", "foc_command_events.csv", "bit_true.json", "bit_true.csv")


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_new(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        assert path.read_text(encoding="utf-8") == value, f"Never replace existing evidence: {path}"
        return
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(value)


def json_new(path, value):
    write_new(path, json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n")


def copy_new(source, destination):
    assert source.is_file(), source
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        assert sha(source) == sha(destination), f"Never replace existing evidence: {destination}"
        return
    with source.open("rb") as incoming, destination.open("xb") as outgoing:
        while chunk := incoming.read(1024 * 1024):
            outgoing.write(chunk)
    assert sha(source) == sha(destination)


def protected_verify():
    result = subprocess.run([sys.executable, str(STUDY / "scripts/study_l1_d_workspace.py"), "verify"],
                            cwd=ROOT, text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout


def verify_case(folder, scenario, implementation):
    for name in CASE_FILES:
        assert (folder / name).is_file(), folder / name
    case, bit = load(folder / "case_metrics.json"), load(folder / "bit_true.json")
    expected_events = 200 if scenario == "convergence_prefix" else 1200
    expected_accepted = 2000 if scenario == "convergence_prefix" else 12000
    assert case["schema"] == "study_l1_checkpoint_d_case_v1"
    assert case["scenario"] == bit["scenario"] == scenario
    assert case["implementation"] == bit["implementation"] == implementation
    assert case["gate_pass"] and case["hold_gate_pass"]
    assert case["fault_code_max"] == case["needs_reset_max"] == 0
    assert case["cfg"]["backend"] == case["effective_config"]["CONTROL_BACKEND"] == 1
    assert case["speed_launch_count"] == case["speed_result_count"] == expected_events
    assert abs(case["speed_first_launch_s"] - .0009) < 1e-12
    assert abs(case["speed_update_interval_s"] - .001) < 1e-12
    assert case["foc_accepted_count"] == expected_accepted
    assert case["foc_active_count"] == expected_accepted - 1
    assert abs(case["foc_accepted_first_s"] - 51e-6) < 1e-12
    assert abs(case["foc_active_first_s"] - 101e-6) < 1e-12
    assert abs(case["foc_transaction_interval_s"] - 100e-6) < 1e-12
    assert abs(case["foc_accepted_to_active_s"] - 50e-6) < 1e-12
    assert case["hand_sv_50mhz_setup_pass"] is False
    assert abs(case["hand_sv_frozen_wns_ns"] + 1.957) < 1e-12
    assert bit["pass"] and bit["port_count"] == 14
    assert bit["event_count"] == expected_events
    assert bit["raw_comparisons"] == expected_events * 14
    assert bit["mismatched_raw_codes"] == bit["mismatched_events"] == 0
    assert all(value == 0 for value in bit["max_absolute_raw_error"])
    assert all(value == 0 for value in bit["changes_without_result"])
    assert "actual" in bit["oracle"].lower() and "speed_pi_fixed.slx" in bit["oracle"]
    assert abs(bit["first_source_event_s"] - .0009) < 1e-12
    assert abs(bit["speed_period_s"] - .001) < 1e-12
    assert bit["input_capture_to_result_cycles"] == 1
    assert "no fitted or arbitrary waveform shift" in bit["alignment"]
    if implementation == "original":
        assert "shadow" in bit["hardware_scope"].lower()
        assert abs(case["physical_latency_s"]) < 1e-12
    else:
        assert 20e-9 < case["physical_latency_s"] <= 40e-9 + 1e-12
        assert case["clock_evidence"]["acceptance_to_result_clocks"] == 1
        assert case["clock_evidence"]["fabric_counter_gate_pass"]
        assert all(abs(value - case["physical_latency_s"]) < 1e-12 for value in bit["source_to_result_s"])
    with (folder / "speed_events.csv").open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    assert len(rows) == expected_events
    for index, row in enumerate(rows):
        source = float(row["source_time_s"])
        physical = float(row["physical_result_time_s"])
        observed = float(row["observed_result_time_s"])
        assert all(math.isfinite(value) for value in (source, physical, observed))
        assert abs(source - (.0009 + index * .001)) < 1e-12
        assert abs(physical - source - case["physical_latency_s"]) < 1e-12
        assert -1e-12 <= observed - physical <= 1e-6 + 1e-12
    with (folder / "bit_true.csv").open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        ports = bit["ports"]
        assert len(ports) == 14
        count = 0
        for row in reader:
            count += 1
            assert int(row["event_id"]) == count
            for port in ports:
                golden, observed = float(row["golden_" + port]), float(row["observed_" + port])
                assert golden == observed == math.trunc(golden), (folder, count, port)
        assert count == expected_events
    with (folder / "foc_command_events.csv").open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        assert reader.fieldnames == ["command_id", "accepted_time_s", "active_time_s",
                                     "active_within_horizon", "id_ref_A", "iq_ref_A"]
        count = active_count = 0
        for row in reader:
            count += 1
            assert int(row["command_id"]) == count
            accepted, active = float(row["accepted_time_s"]), float(row["active_time_s"])
            assert abs(accepted - (51e-6 + (count - 1) * 1e-4)) < 1e-12
            assert row["active_within_horizon"].lower() in ("true", "false", "1", "0")
            active_inside = row["active_within_horizon"].lower() in ("true", "1")
            if active_inside:
                active_count += 1
                assert abs(active - accepted - 50e-6) < 1e-12
            else:
                assert count == expected_accepted and active == 0
            assert all(math.isfinite(float(row[field])) for field in ("id_ref_A", "iq_ref_A"))
            assert abs(float(row["iq_ref_A"])) <= 1 + 1e-12
        assert count == expected_accepted and active_count == expected_accepted - 1
    return case, bit


def max_speed_rmse(case):
    speed = case["step7d_acceptance"].get("speed", [])
    if speed and isinstance(speed[0], (int, float)):
        speed = [speed]
    return max((row[2] for row in speed), default=None)


def fmt(value):
    return "prefix sanity" if value is None else f"{value:.9g}"


def datatype_tables():
    text = (STUDY / "reports/checkpoint_a/datatype_table.md").read_text(encoding="utf-8")
    lines = text.splitlines()
    def table(header):
        first = next(i for i, line in enumerate(lines) if line.startswith(header))
        end = first
        while end < len(lines) and lines[end].startswith("|"):
            end += 1
        return "\n".join(lines[first:end])
    return table("| Signal |"), table("| Format |")


def final_report(a, b, c, d, comparison):
    datatype, coefficients = datatype_tables()
    fair = c["metrics"]
    labels = ("baseline", "csd", "hand")
    rows = ["| Metric | HDL Coder baseline | HDL Coder optimized（AW CSD，仅 C） | Hand SV |",
            "|---|---:|---:|---:|"]
    for field in ("LUT", "FF", "DSP48"):
        rows.append(f"| {field} | " + " | ".join(str(fair[name][field]) for name in labels) + " |")
    rows.append("| BRAM | " + " | ".join(str(fair[name]["RAMB18"] + fair[name]["RAMB36"]) for name in labels) + " |")
    rows += ["| Register boundaries / accepted-input latency | 2 stages / 1 clock | 2 stages / 1 clock | 2 stages / 1 clock |",
             "| Update interval | 50000 clocks / 1 ms | 50000 clocks / 1 ms | 50000 clocks / 1 ms |",
             "| WNS @ 50 MHz / ns | " + " | ".join(str(fair[name]["WNS_ns"]) for name in labels) + " |",
             "| RTL LOC（含空行、注释） | " + " | ".join(str(c["RTL_physical_LOC_including_comments"][name]) for name in labels) + " |"]
    system_rows = ["| Scenario | Speed PI | Worst speed-window RMSE / mm/s | iq RMSE / A | Speed events | FOC accepted / active | Physical latency / ns |",
                   "|---|---|---:|---:|---:|---:|---:|"]
    for scenario in SCENARIOS:
        for implementation in IMPLEMENTATIONS:
            case = d["cases"][scenario][implementation]["case"]
            system_rows.append(f"| {scenario} | {implementation} | {fmt(max_speed_rmse(case))} | "
                               f"{fmt(case['step7d_acceptance'].get('iq_rmse_A'))} | {case['speed_result_count']} | "
                               f"{case['foc_accepted_count']} / {case['foc_active_count']} | {case['physical_latency_s'] * 1e9:.9g} |")
    transport_rows = ["| Speed PI | Observed physical-result → managed-reference delay / us |",
                      "|---|---:|"]
    for implementation in IMPLEMENTATIONS:
        delays = []
        for scenario in SCENARIOS:
            values = d["cases"][scenario][implementation]["case"]["managed_reference_events"]["managed_transport_delay_s"]
            delays.extend(values if isinstance(values, list) else [values])
        assert delays and all(math.isfinite(value) and value >= -1e-12 for value in delays)
        lo, hi = (0 if abs(value) < 1e-12 else value * 1e6 for value in (min(delays), max(delays)))
        transport_rows.append(f"| {implementation} | {lo:.9g} … {hi:.9g} |")
    protected = d["protected_content_preserved"]
    bit_comparisons = sum(evidence["bit_true"]["raw_comparisons"] for scenario in d["cases"].values() for evidence in scenario.values())
    source_phases = sorted({round(evidence["case"]["physical_latency_s"] * 1e9, 6)
                            for scenario in d["cases"].values() for name, evidence in scenario.items() if name != "original"})
    return f"""# Study-L1：速度 PI 的 HDL Coder 与手写 SystemVerilog 最终报告

Checkpoint D 的三组系统比较完成，状态为 `COMPLETE_D_WITH_HAND_SETUP_VIOLATION`。三组都通过原 Step7D 的 speed acceptance 和本次调度、hold、故障与实际 B1 raw-code 检查。**Hand SV 仍保留 Checkpoint C 的 50 MHz WNS = -1.957 ns，setup 未通过；系统联合仿真通过不能说明它已有 50 MHz 上板条件。** 等待本次 GitHub / ChatGPT Review，不自动开始后续任务。

主系统比较仅为原 Simulink Speed PI、Checkpoint B HDL Coder baseline 和 Hand SV，三组都接同一份 handwritten FOC RTL。C 的 AW CSD 只出现在历史单选项资源对比表中，没有第四个系统 case。

## 原控制器：从真实 SLX 得到的方程

原工作树 SLX 的审计及实际连接见 [A1 原 PI 审计](checkpoint_a/current_speed_pi_audit.md)；冻结 B1 的逐级 cast 规则见 [共同 RTL 契约](checkpoint_c/rtl_contract.md)。一次有效速度事件内，`x_old` 和 `d_old` 都是上一事件留下的状态：

```text
e = v_ref - v_meas
P = Kp * e
inc = (Ki * Ts_ASR) * e
AW = Kaw * d_old
u = P + x_old
l = clip(u, -1 A, +1 A)
d_next = u - l
candidate = clip(x_old + inc - AW, -0.5 A, +0.5 A)
hard = angle_init OR pi_reset OR test_mode OR NOT enable
int_reset = hard OR (abs(v_ref) < 0)
            OR (abs(v_ref) > 0.5 AND sign(v_ref)*e < -3)
iq_ref = hard ? 0 : quantize_to_25_FL15(l)
x_next = int_reset ? 0 : candidate
```

Kp=0.018033474852681124，Ki=1.4426779882144898，Ts_ASR=0.001 s，Kaw=0.08；原 friction compensation 已被注释，其输出为 0。AW 使用 **previous excess**，当前输出使用 **old integrator**，不能改成当拍新积分或当拍 excess。积分复位单独发生时，当拍输出仍使用旧 x；hard reset 令当拍输出与下一 x 为 0，**不清除 d_next**。阈值 `abs(ref)<0` 永远为假，零参考保留保持电流所需的积分。

原 scheduler 在 t=0 开始 100 us function-call，计数先加一，因此首速度事件为 **0.9 ms**，以后每 **1 ms**。位置事件首相位 9.9 ms，周期 10 ms。语义 reset/disable 只在有效速度事件采样；空闲 clock 不更新状态。FPGA 初始化 reset 与这些算法 reset 不同：同步初始化优先于 global CE，并清除寄存器/流水状态。

## Float 与 Fixed：类型、系数量化和误差

独立 float 对原 PI 副本的全部 14 项输出最大误差为 {max(a['float_max_errors']):.9g}；A 使用 {a['samples']} 个样本、{a['ticks']} 个真实速度事件。B1 是所有后续 RTL 的唯一 numerical golden，B2 只研究缩短位宽产生的误差，没有用于系统闭环。

{datatype}

所有有损转换采用 Convergent / ties-to-even，存储溢出采用 Saturate，没有 wrap。算法 ±1 A / ±0.5 A 限幅与存储饱和分别保留。全精度 error×coefficient 为 signed65/FL50，AW 乘积为 signed72/FL60，逐级转换到 work40/FL30；积分更新保留 44 位累加与 45 位减法再饱和。输出 Q15 只在内部限幅之后转换；previous excess 来自内部 u-l，不能改用量化后的外部 iq。

{coefficients}

| A 测试误差指标 | B1 | B2 candidate |
|---|---:|---:|
| 非饱和 iq_ref 最大误差 / A | {a['b1']['max_linear_iq_error_A']:.12g} | {a['b2']['max_linear_iq_error_A']:.12g} |
| 非饱和 iq_ref 最大误差 / 外部 LSB | {a['b1']['max_linear_iq_error_LSB']:.12g} | {a['b2']['max_linear_iq_error_LSB']:.12g} |
| integrator 最大误差 / A | {a['b1']['max_integrator_error_A']:.12g} | {a['b2']['max_integrator_error_A']:.12g} |
| 饱和时刻/方向 mismatch | {a['b1']['saturation_mismatches']} | {a['b2']['saturation_mismatches']} |

B1 在该组件测试中的输出误差约半个 Q15 LSB；B2 的误差超过 1 LSB。上述值是已运行向量的实测结果，不能扩大为所有实数或所有电机工况的误差上界。[A2/A3 完整对照](checkpoint_a/float_fixed_comparison.md)说明复位阈值、量化和 overflow 范围。

## HDL Coder 与 Hand SV：结构、可读性和 traceability

HDL Coder carrier 从 B1 复制相同 PI 运算块，只改变可生成 HDL 的承载结构和寄存器边界。冻结文件为 `generated_hdl/baseline/HDLCore.sv` 和 `PI.sv`；没有编辑生成的数学表达式。输入寄存阶段后，事件输出寄存器同时保持数值和诊断。global CE 不是算法 enable，ce_out 不是 result_valid。[HDL Coder walkthrough](checkpoint_b/hdl_coder_walkthrough.md)给出配置、SID mapping、原块→RTL 路径和 Vivado DSP48 报告，便于从熟悉的 Simulink 算法追到生成结果。

Hand SV 的 [speed_pi_sv.sv](../handwritten/speed_pi_sv.sv)用显式状态寄存器、全宽乘积、guard/sticky/retained-LSB 的偶数舍入及逐级饱和实现同一契约。一个输入阶段加一个事件输出保持阶段，不新增算法延迟。代码物理行数 {c['RTL_physical_LOC_including_comments']['hand']}，比 baseline 的 {c['RTL_physical_LOC_including_comments']['baseline']} 行更紧凑；紧凑并没有自动带来更低资源或更好的时序。复位、previous excess、overspeed 边界与 signed minimum 取负饱和都需要人工维护和证明。

## Bit-true：组件覆盖和真实系统输入重放

B 的生成版在 {b['xsim_rows']} 行 / {b['xsim_ticks']} 事件 / 14 项 raw code 上零差异。C 的公平比较在每版 {c['rows_per_implementation']} 行、{c['valid_events_per_implementation']} 事件上验证 baseline、AW CSD 和 hand 全部 14 项零差异，覆盖正负线性区、饱和、anti-windup、解饱和、反向、reset/disable、连续上升事件、长空闲、global CE stall 和初始化 reset 优先级。

D 又使用各次真实系统导出的输入、实际 source event 顺序和测得的物理 capture/result cycle，重新运行冻结 `models/speed_pi_fixed.slx`。共 {bit_comparisons} 项 raw code 对照，mismatch=0；每一项中间量也验证两次有效结果之间保持。[九组 bit_true.csv/json](checkpoint_d/verification/)保存 actual B1 与观察到的 RTL raw code。original case 的 B1 检查对象是 **未选中的 baseline shadow**，没有把原 float PI 宣称为对 B1 bit-exact。真实重放 oracle、完整整数网格及实际对齐说明以各组 fresh `bit_true.json` 的 `oracle` / `alignment` 为准；不通过移动曲线或修改 PI 消除差异。

重放工具出现过一个已定位的输入时间网格问题。四组受控诊断中，`colon_default` 有 200 项 raw mismatch / 2 个 ingress mismatch（事件 154、155）；`colon_explicit_zoh` 有 343 项 / 6 个 ingress mismatch；相同输入采用整数索引构造的 `integer_default` 和 `integer_explicit_zoh` 都为 0 / 0。Colon 时间向量与离散求解器 n×Ts 向量有 119 个 timestamp 不同，最大仅 2.7755575615628914e-17 s，却足以让 FromWorkspace 在边界选到前一个 100 us 输入。直接记录 B1 的输入 Ref/Meas 证明问题发生在 oracle ingress，不是 PI 运算或 RTL 延迟。最终只把新重放 helper 的时间向量改为 `(0:round(stop/Ts))' * Ts`，匹配离散 solver 的网格；冻结 B1 参数/SLX、RTL、真实系统波形和算法都未更改。[四组原始 CSV 与诊断 summary](checkpoint_d/verification/replay_input_diagnostic/summary.json)保留失败和通过的数据。

## Vivado 公平资源和时序比较

下表来自已合并 C 的同一次边界设计：同一真实 `xc7a200tfbg484-2`、50 MHz、同一 input/output register boundary、全部 14 项诊断、同一 XDC / OOC synthesis→implementation，无 false/multicycle path。D 没有重跑或覆盖这份冻结资源结果。

{chr(10).join(rows)}

每版另有同一份 {c['RTL_physical_LOC_including_comments']['common_adapter']} 行薄 valid/CE adapter。C 的 CSD 只对 AW Gain 的 `ConstMultiplierOptimization` 从 none 改为 csd；DSP48 从 10 降为 6，LUT 从 685 增为 1049，WNS 从 +0.331 ns 变为 +0.862 ns，没有更改算法或 latency。Hand 同样用了 10 个 DSP48，LUT=705，WNS=-1.957 ns，关键路径从 ref_q_reg 到 d_reg，52 级逻辑 / 21.632 ns data delay。[公平比较与关键路径](checkpoint_c/final_rtl_comparison.md)区分结构选择与工具映射，并保留未解释到门级的归因限制。

B 早期单核心报告的 683 LUT / 472 FF 与 C 的 685 LUT / 555 FF 来自不同薄适配器/诊断边界；不能拿两个边界的数字直接当作工具优劣。最终公平比较以本表的 C 同边界结果为准。OOC IP 内部时序通过不等同于 board I/O signoff。

## 系统联合仿真：同一 Host、Position、FOC、inverter 和 plant

三组均为 CONTROL_BACKEND=1。仅 Study copy 内的速度来源选择不同，选择后仍经共同 Reference_Manager 和原 FPGA_Input_Adapter 进入同一 FOC。正式主 SLX、FOC/PWM RTL、控制周期、PI 参数、plant 和 inverter 算法没有保存或改写。average inverter 在 ideal 用 0 deadtime，在 deadtime 用 1 us；同一场景的三组值完全相同。每次模型配置前后的 shared fingerprint 都相同，包含原块计算参数及内部 Line 连接；九组 metrics 的 `cfg.shared_fingerprint` 保存相同 Host、Position、原 PI、scheduler、Reference_Manager、FOC、plant、inverter、adapter 的图结构证据。

{chr(10).join(system_rows)}

每组 speed case 完整运行 1.2 s，position prefix 为 0.2 s。speed 的固定窗口、MAE/RMSE/max 和 current gates 使用未修改的 `step7d_assert_result.m`；prefix 只确认 Host trajectory→Position→speed→FOC→plant 的方向、有限性和电流/故障/调度，不宣称完整位置 settling。

RTL physical source→result 的实测值为 {source_phases} ns，来自第一 posedge `$time` 和 actual cycle ordinal，而不是强加的时间平移。冻结 RTL 的 accepted input→result 仍为 1 个 20 ns clock。1 us XSI communication 观察到计数变化，再经显式 1 us feedback hold、共同 100 us Control_Task / Reference_Manager 消费；新增 carrier transport 与原 RTL pipeline 分开记录，通常在下一 100 us task 发布参考。各组 metrics 的 `managed_reference_events` 保存实测发布、FOC accepted 与配对 active 时刻，仅对数值发生变化的结果测量 transport；连续相同数值仍由结果计数覆盖。

{chr(10).join(transport_rows)}

RTL physical result 的 30 ns 相位与后续约 99.97 us 的管理器消费延迟是不同的量：source→managed publish 为 100 us。Original float 在同一 speed task 中发布，测得管理器 transport 为 0。Coder baseline 与 Hand SV 在相同承载边界下，全部七项数值比较字段的未移位差异都是 0；原 float 与 fixed 的差异只描述实际测量，不要求其 raw code 相等。

FOC 在每组保持 accepted 首观察 51 us、active 首观察 101 us、后续 100 us transaction、accepted→active 50 us。内部电流计算延迟与 PWM 时序未变。全部 fault_code / needs_reset / range flags 为 0。当前波形不要求 float 与 fixed 逐点相同，量化、实际 pipeline 与 carrier consumption 的小差异没有通过重新整定隐藏。

[D 逐组数值与未移位差异表](checkpoint_d/verification/comparison.md)、[交互式同时间曲线](checkpoint_d/verification/comparison.html)和 [系统 walkthrough](checkpoint_d/system_walkthrough.md)提供 v_ref、v、speed PI iq_ref、iq、新结果、accepted/active、fault/reset、位置与实际管理后参考。图表网格为 100 us；new_result 表示自上一图表样本后观察到的 completion-count 增量，不冒充一个 20 ns valid pulse。

## 学习结论和可复现边界

算法快速迭代时，HDL Coder 更便于把已冻结的 Simulink 定点模型、datatype 和 SID traceability 连接起来；每次改模型都必须重新验证 raw code、资源与时序。手写 SV 更适合明确控制 CE、valid、接口协议和寄存器布局，但这次 hand 实现没有获得预期的资源/时序优势：baseline 的 LUT 更少且 50 MHz 通过，hand 尚未通过。

资源选择取决于约束：AW CSD 节省 4 个 DSP48，却多用 364 个 LUT；若 DSP 紧张值得评估，若 LUT 更紧张则 baseline 更合适。这一个实验不能推广为所有乘法都改 CSD。之后可讨论在已固定类型的独立控制/运算核上尝试 HDL Coder；FOC transaction、PWM、安全复位、握手和最终 scheduler 这类时序协议仍适合保留明确的手写 RTL，且需要另行任务授权。

1 ms 是 PI **状态更新间隔**，不是 FPGA 的 physical clock 周期。50 MHz clock 运行所有寄存器，外部 sample_tick/CE 只允许规定事件改变状态；不必生成 1 kHz 新时钟。Ki 是连续增益，Ki×Ts 才是每事件积分增量；积分器与 previous excess 必须作为状态寄存器保留。整数位来自真实输入/内部范围，小数位决定 LSB；舍入及饱和必须与模型中的逐级转换相同。DSP48 的使用依据是实际 Vivado utilization，而不是仅看 RTL 中是否有乘号。

模型算法修改时优先改模型并重新生成，不修改生成文件；握手或架构修改时显式改手写 carrier并重新证明同一数值边界。两种 RTL 能组合是因为 FPGA RTL 模块按共同 clock / fixed-point 端口互连，HDL 来源不改变接口规则；系统闭环成功仍不能代替实现时序验收。

此次保护核验保留 {protected['user_files']} 个用户本地文件/缺失状态、{protected['frozen_abc_files']} 个冻结 A/B/C 文件、{protected['frozen_other_tracked']} 个其他 tracked 源文件；源 SHA 和 fresh runtime snapshot/log 见 [D summary](checkpoint_d/summary.json)及 [verification provenance](checkpoint_d/verification/provenance.json)。仅使用原工作树和独立 runtime/model copies；无 worktree/clone、stash、reset/clean、批量删除、bitstream 或硬件操作。

复现先阅读 [系统 walkthrough 的命令](checkpoint_d/system_walkthrough.md)，用从未存在的新 run 名生成 XSI，运行三种 speed PI 的三个场景并重放实际 B1，再调用 `study_l1_d_publish.py` 的明确参数发布。MATLAB={d['MATLAB']}，Vivado={d['Vivado']}。全部数学/接口证据与 Hand timing 失败同时保留；本次 completion 不构成下一阶段或上板授权。
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generation-run", default="d_xsi_fresh_01")
    parser.add_argument("--generation-console", default="d_generate_fresh01.txt")
    parser.add_argument("--case-prefix", default="d_final")
    parser.add_argument("--worker-prefix", default="d_fresh")
    parser.add_argument("--ingress-diagnostic", default="d_golden_ingress_probe01")
    parser.add_argument("--preflight-probe", default="d_probe_fresh_01")
    parser.add_argument("--fresh-verification-console", default="d_fresh_saved_verify.txt")
    args = parser.parse_args()
    runtime = STUDY / ".runtime"
    generation = runtime / args.generation_run
    report = STUDY / "reports/checkpoint_d"
    verification = report / "verification"
    pre = load(report / "workspace_preflight.json")
    protection_log = protected_verify()
    a = load(STUDY / "reports/checkpoint_a/verification/summary.json")
    b = load(STUDY / "reports/checkpoint_b/summary.json")
    c = load(STUDY / "reports/checkpoint_c/summary.json")
    assert a["float_vs_original_pass"] and a["standalone_models_match_testbench"]
    assert b["raw_mismatches"] == c["raw_mismatches"] == 0
    assert c["metrics"]["baseline"]["timing_met"] and not c["metrics"]["hand"]["timing_met"]
    assert abs(c["metrics"]["hand"]["WNS_ns"] + 1.957) < 1e-12
    diagnostic_dir = runtime / args.ingress_diagnostic
    diagnostic = load(diagnostic_dir / "summary.json")
    assert diagnostic["colon_vs_integer_different_timestamps"] == 119
    assert abs(diagnostic["maximum_timestamp_difference_s"] - 2.7755575615628914e-17) < 1e-30
    diagnostic_runs = {entry["name"]: entry for entry in diagnostic["runs"]}
    assert diagnostic_runs["colon_default"]["raw_mismatches"] == 200
    assert diagnostic_runs["colon_default"]["ingress_mismatched_event_ids"] == [154, 155]
    assert diagnostic_runs["colon_explicit_zoh"]["raw_mismatches"] == 343
    assert diagnostic_runs["colon_explicit_zoh"]["ingress_mismatched_events"] == 6
    for name in ("integer_default", "integer_explicit_zoh"):
        assert diagnostic_runs[name]["pass"] and diagnostic_runs[name]["raw_mismatches"] == diagnostic_runs[name]["ingress_mismatched_events"] == 0
    probe = runtime / args.preflight_probe / "probe.txt"
    probe_text = probe.read_text(encoding="utf-8-sig")
    assert b["MATLAB"] in probe_text
    assert all(marker in probe_text for marker in
               ("LICENSE Simulink 1", "LICENSE Fixed_Point_Toolbox 1", "LICENSE EDA_Simulator_Link 1",
                "FROZEN Kp_ASR 0.018033474852681124", "FROZEN Ki_ASR 1.4426779882144898",
                "FROZEN Ts_ASR 0.001", "FROZEN Iq_int_limit 0.5"))
    fresh_console = runtime / args.fresh_verification_console
    fresh_text = fresh_console.read_text(encoding="utf-8-sig")
    assert "D_FRESH_ALL_NINE_SAVED_VERIFY_PASS" in fresh_text
    assert fresh_text.count("D_FRESH_SAVED_VERIFY_PASS ") == 9
    generation_console = runtime / args.generation_console
    console = generation_console.read_text(encoding="utf-8-sig")
    assert "D_XSI_GENERATION_PASS" in console and "D_XSI_MASK_PASS" in console
    compile_log = generation / "vivado.log"
    native_log = compile_log.read_text(encoding="utf-8-sig")
    vivado = re.search(r"Vivado v([^\s]+)", native_log).group(1)
    assert vivado == "2026.1"
    source_manifest = generation / "source_manifest.txt"
    sources = [Path(line) for line in source_manifest.read_text(encoding="utf-8-sig").splitlines() if line]
    assert len(sources) == 24 and not any("aw_csd" in str(path) for path in sources)
    source_sha = {str(path.resolve().relative_to(ROOT)).replace("\\", "/"): sha(path) for path in sources}
    assert source_sha["learning/study_l1_speed_pi_hdl_compare/generated_hdl/baseline/PI.sv"] == b["generated_sha256"]["PI.sv"]
    assert source_sha["learning/study_l1_speed_pi_hdl_compare/generated_hdl/baseline/HDLCore.sv"] == b["generated_sha256"]["HDLCore.sv"]
    assert source_sha["learning/study_l1_speed_pi_hdl_compare/handwritten/speed_pi_sv.sv"] == c["sources_sha256"]["handwritten/speed_pi_sv.sv"]
    cases, locations, worker_manifests = {}, {}, {}
    for implementation in IMPLEMENTATIONS:
        worker = runtime / f"{args.worker_prefix}_{implementation}"
        manifest = load(worker / "snapshot_manifest.json")
        assert Path(manifest["source"]).resolve() == generation.resolve()
        for relative, expected in manifest["files"].items():
            assert sha(worker / relative) == sha(generation / relative) == expected, (implementation, relative)
        worker_manifests[implementation] = manifest
        case_console = runtime / f"{args.case_prefix}_{implementation}.txt"
        assert "D_SYSTEM_RUN_PASS" in case_console.read_text(encoding="utf-8-sig"), case_console
        for scenario in SCENARIOS:
            folder = runtime / f"{args.case_prefix}_{implementation}" / scenario / implementation
            case, bit = verify_case(folder, scenario, implementation)
            cases.setdefault(scenario, {})[implementation] = {"case": case, "bit_true": bit}
            locations[(scenario, implementation)] = folder
    # All completed-run gates are inspected before any evidence is published.
    for scenario in SCENARIOS:
        fingerprints = [cases[scenario][name]["case"]["cfg"]["shared_fingerprint"] for name in IMPLEMENTATIONS]
        assert all(value == fingerprints[0] for value in fingerprints), scenario
    first_fingerprint = cases[SCENARIOS[0]][IMPLEMENTATIONS[0]]["case"]["cfg"]["shared_fingerprint"]
    assert all(evidence["case"]["cfg"]["shared_fingerprint"] == first_fingerprint
               for scenario in cases.values() for evidence in scenario.values())
    protection_counts = {category: len(pre[category]) for category in
                         ("user_files", "frozen_abc_files", "frozen_other_tracked")}
    summary = dict(checkpoint="D", status="COMPLETE_D_WITH_HAND_SETUP_VIOLATION", base_main=pre["main"],
                   MATLAB=b["MATLAB"], Vivado=vivado, HDL_Verifier=b["HDL_Verifier"],
                   primary_coder="Checkpoint B frozen baseline; AW CSD not compiled into system runtime",
                   golden_B1_sha256=b["golden_B1_sha256"], cases=cases,
                   system_case_count=9, raw_mismatches=0, protected_content_preserved=protection_counts,
                   source_sha256=source_sha, generation_run=str(generation),
                   hand_sv_50mhz_setup_pass=False, hand_sv_frozen_wns_ns=-1.957,
                   permanent_primary_model_changes=False, existing_foc_changes=False,
                   speed_pi_retuned=False, control_backend_semantics="0 legacy current, 1 RTL current; all system cases use 1",
                   current_loop_period_s=100e-6, bitstream=False, hardware=False,
                   next_checkpoint_started=False, review_state="Awaiting GitHub / ChatGPT Review",
                   shared_block_and_internal_line_fingerprints_equal=True,
                   replay_input_grid_diagnostic=diagnostic,
                   replay_input_grid="(0:round(stop/Ts))' * Ts; same frozen model and actual source-event order",
                   actual_license_feature="EDA_Simulator_Link=1")
    evidence_hashes = {}
    for (scenario, implementation), source in locations.items():
        destination = verification / scenario / implementation
        names = list(CASE_FILES)
        if (source / "speed_shadow_events.csv").is_file():
            names.append("speed_shadow_events.csv")
        for name in names:
            target = destination / name
            copy_new(source / name, target)
            evidence_hashes[str(target.relative_to(report)).replace("\\", "/")] = sha(target)
    native = verification / "runtime"
    for name, exported in (("source_manifest.txt", "source_manifest.txt"),
                           ("vivado.log", "vivado_compile_console.txt"),
                           ("vivado.jou", "vivado_compile_journal.txt"),
                           ("hdlverifier_compile.tcl", "hdlverifier_compile.tcl"),
                           ("hdlverifier_gendll.tcl", "hdlverifier_gendll.tcl")):
        copy_new(generation / name, native / exported)
    copy_new(generation / "xsim.dir/design/Compile_Options.txt", native / "Compile_Options.txt")
    copy_new(generation_console, native / "generation_console.txt")
    copy_new(probe, native / "preflight_model_probe.txt")
    copy_new(fresh_console, native / "fresh_saved_verification_console.txt")
    for name in ("summary.json", "colon_default.csv", "colon_explicit_zoh.csv", "integer_default.csv", "integer_explicit_zoh.csv"):
        copy_new(diagnostic_dir / name, verification / "replay_input_diagnostic" / name)
    for implementation in IMPLEMENTATIONS:
        copy_new(runtime / f"{args.worker_prefix}_{implementation}" / "snapshot_manifest.json",
                 native / f"worker_snapshot_{implementation}.json")
        copy_new(runtime / f"{args.case_prefix}_{implementation}.txt", native / f"system_console_{implementation}.txt")
    write_new(native / "protected_content_verification.txt", protection_log)
    # The comparison helper checks all three common configurations and writes
    # plots directly from original timestamps; it performs no shifts.
    compare = subprocess.run([sys.executable, str(STUDY / "scripts/study_l1_d_compare.py"),
                              "--report-dir", str(verification)], cwd=ROOT, text=True, capture_output=True)
    assert compare.returncode == 0, compare.stdout + compare.stderr
    comparison = load(verification / "comparison.json")
    assert comparison["comparison_gate_pass"]
    summary["comparison_gate_pass"] = True
    provenance = dict(base_main=pre["main"], source_sha256=source_sha,
                      golden_B1_sha256=b["golden_B1_sha256"], worker_snapshots=worker_manifests,
                      evidence_sha256=evidence_hashes,
                      scope="Native MAT/cache/private SLX/XSI binaries stay local; compact actual-run evidence is copied without mutation.")
    json_new(verification / "provenance.json", provenance)
    json_new(report / "summary.json", summary)
    write_new(STUDY / "reports/STUDY_L1_FINAL_REPORT.md", final_report(a, b, c, summary, comparison))
    assert protection_log == protected_verify()
    print("STUDY_L1_D_PUBLISH_PASS cases=9 raw_mismatches=0 hand_50mhz_setup_pass=0")
    print(compare.stdout.strip())


if __name__ == "__main__":
    main()
