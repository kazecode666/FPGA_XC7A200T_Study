"""Compare fresh D case evidence at the same times, without waveform shifts.

Input: REPORT/{scenario}/{implementation}/{case_metrics.json,trace.csv}.
Only study-owned output files are written; existing evidence is not replaced.
Uses the Python standard library. HTML plots are standalone and editable.
"""
import argparse
import csv
import hashlib
import itertools
import json
import math
from pathlib import Path

SCENARIOS = ("speed_ideal", "speed_deadtime", "convergence_prefix")
IMPLEMENTATIONS = ("original", "coder_baseline", "hand_sv")
FIELDS = ("time_s", "v_ref_mmps", "v_mmps", "speed_pi_iq_ref_A", "iq_A",
          "result_count", "new_result", "accepted_id", "active_id",
          "fault_code", "needs_reset", "x_ref_mm", "x_mm", "iq_ref_A")
COMPARISON_FIELDS = ("v_ref_mmps", "v_mmps", "speed_pi_iq_ref_A", "iq_A",
                     "x_ref_mm", "x_mm", "iq_ref_A")


def write_new(path, value):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(value)


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def load_case(folder, scenario, implementation):
    metric_path = folder / "case_metrics.json"
    trace_path = folder / "trace.csv"
    metrics = json.loads(metric_path.read_text(encoding="utf-8-sig"))
    bit_path = folder / "bit_true.json"
    bit = json.loads(bit_path.read_text(encoding="utf-8-sig"))
    assert metrics["schema"] == "study_l1_checkpoint_d_case_v1", metric_path
    assert metrics["scenario"] == scenario, metric_path
    assert metrics["implementation"] == implementation, metric_path
    assert metrics["gate_pass"] and metrics["hold_gate_pass"], metric_path
    assert bit["pass"] and bit["scenario"] == scenario and bit["implementation"] == implementation
    assert bit["port_count"] == 14 and bit["event_count"] == metrics["speed_result_count"]
    assert bit["mismatched_raw_codes"] == bit["mismatched_events"] == 0
    assert all(value == 0 for value in bit["max_absolute_raw_error"])
    assert all(value == 0 for value in bit["changes_without_result"])
    assert "actual" in bit["oracle"].lower() and "speed_pi_fixed.slx" in bit["oracle"]
    if implementation == "original":
        assert "shadow" in bit["hardware_scope"].lower()
    assert metrics["fault_code_max"] == metrics["needs_reset_max"] == 0
    assert metrics["hand_sv_50mhz_setup_pass"] is False
    assert abs(metrics["hand_sv_frozen_wns_ns"] + 1.957) < 1e-12
    data = {key: [] for key in FIELDS}
    with trace_path.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        assert tuple(reader.fieldnames) == FIELDS, trace_path
        for row in reader:
            for field in FIELDS:
                value = float(row[field])
                assert math.isfinite(value), (trace_path, field)
                data[field].append(value)
    times = data["time_s"]
    assert len(times) > 1 and times[0] == 0
    assert abs(times[-1] - metrics["cfg"]["stopTime"]) < 1e-12
    assert all(abs(b - a - 1e-4) < 1e-12 for a, b in zip(times, times[1:]))
    for field in ("result_count", "new_result", "accepted_id", "active_id",
                  "fault_code", "needs_reset"):
        assert all(value >= 0 and value == int(value) for value in data[field])
    assert data["result_count"][0] == 0
    assert data["result_count"][-1] == metrics["speed_result_count"]
    assert data["new_result"][0] == 0
    for before, after, flag in zip(data["result_count"], data["result_count"][1:], data["new_result"][1:]):
        assert after - before in (0, 1) and flag == int(after > before)
    assert not any(data["fault_code"]) and not any(data["needs_reset"])
    return metrics, data, {str(metric_path): sha(metric_path), str(trace_path): sha(trace_path),
                          str(bit_path): sha(bit_path)}


def shared_contract(metrics):
    cfg = metrics["cfg"]
    effective = metrics["effective_config"]
    config_keys = ("name", "purpose", "backend", "commTs", "stopTime",
                   "deadtime_s", "host", "signals", "windows", "thresholds")
    runtime_keys = ("CONTROL_BACKEND", "FPGA_Cosim_Enable", "FPGA_Cosim_Input_Mode",
                    "FPGA_Reference_Mode", "PMLSM_Ts_s", "PMLSM_deadtime_s",
                    "PMLSM_deadtime_ratio", "Ts", "Ts_ACR", "Ts_ASR", "Ts_POS",
                    "Udc", "Kp_ASR", "Ki_ASR", "Kaw_s", "Kp_pos", "Kp_ACR",
                    "Ki_ACR", "Speed_loop_Iq_Limit", "Iq_int_limit", "STEP7C_PI_PROFILE")
    assert cfg["backend"] == effective["CONTROL_BACKEND"] == 1
    return ({**{key: cfg[key] for key in config_keys}, "shared_fingerprint": cfg["shared_fingerprint"]},
            {key: effective[key] for key in runtime_keys})


def differences(a, b):
    assert len(a["time_s"]) == len(b["time_s"])
    assert all(abs(x - y) < 1e-12 for x, y in zip(a["time_s"], b["time_s"]))
    result = {}
    for field in COMPARISON_FIELDS:
        delta = [x - y for x, y in zip(a[field], b[field])]
        result[field] = {"max_abs": max(map(abs, delta)),
                         "rmse": math.sqrt(sum(x * x for x in delta) / len(delta))}
    for field in ("accepted_id", "active_id", "fault_code", "needs_reset"):
        result[field] = {"identical": a[field] == b[field]}
        assert result[field]["identical"], f"FOC timing/status changed: {field}"
    return result


def figure_data(data):
    # Charts retain every 100 us trace sample. No interpolation, resampling,
    # smoothing, event relocation, or latency compensation is applied.
    return {key: data[key] for key in FIELDS}


def make_html(data):
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    payload = payload.replace("<", "\\u003c")
    return """<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Study-L1 Checkpoint D 系统对比</title>
<style>body{font:15px system-ui,sans-serif;margin:24px;color:#172434;background:#f7f9fc}h1{font-size:24px}button,select,input{font:inherit}label{margin-right:20px}.legend span{display:inline-block;margin:12px 20px 12px 0}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(440px,1fr));gap:14px}.panel{background:white;border:1px solid #dce2eb;border-radius:6px;padding:12px}canvas{width:100%;height:210px}h2{font-size:16px;margin:0 0 8px}.note{max-width:1100px;line-height:1.7}.cursor{font-variant-numeric:tabular-nums;min-height:26px}input[type=number]{width:110px}strong.warning{color:#a32121}</style>
<h1>Study-L1 Checkpoint D：三种速度 PI，同一 FOC 和电机模型</h1>
<p class="note">原始采样时刻直接比较，没有平移波形。曲线为相同 100 μs 观察网格；new_result 表示“自上一个图表采样点后观察到新结果”，不是 20 ns 的硬件 valid 脉冲。每个精确 launch / physical completion / observed completion 的时间见各 case 的 speed_events.csv。</p>
<p class="note"><strong class="warning">Hand SV 的冻结 50 MHz WNS = −1.957 ns，setup 未通过。系统联合仿真通过只能证明数值/接口/调度行为，不证明其已满足 50 MHz 上板条件。</strong></p>
<label>场景 <select id="scenario"><option>speed_ideal</option><option>speed_deadtime</option><option>convergence_prefix</option></select></label>
<label>起点/s <input id="start" type="number" value="0" min="0" step="0.001"></label>
<label>终点/s <input id="end" type="number" value="1.2" min="0" step="0.001"></label><button id="apply">应用范围</button>
<div class="legend"><span style="color:#222">● Original Simulink</span><span style="color:#1765ba">● HDL Coder baseline</span><span style="color:#d35b10">● Hand SV</span></div>
<div id="cursor" class="cursor">移动鼠标查看相同时刻的三组数值。</div><div id="plots" class="grid"></div>
<script id="data" type="application/json">""" + payload + """</script>
<script>
const data=JSON.parse(document.getElementById('data').textContent), names=['original','coder_baseline','hand_sv'], colors=['#222','#1765ba','#d35b10'];
const fields=[['v_ref_mmps','v_ref / mm·s⁻¹'],['v_mmps','v / mm·s⁻¹'],['speed_pi_iq_ref_A','speed PI held iq_ref / A'],['iq_A','iq / A'],['result_count','speed PI cumulative result count'],['new_result','new speed result since previous 100 μs sample'],['accepted_id','FOC accepted_sample_id'],['active_id','FOC active_command_id'],['fault_code','fault_code'],['needs_reset','needs_reset'],['x_ref_mm','Host position reference / mm'],['x_mm','Plant position / mm'],['iq_ref_A','Reference_Manager iq_ref delivered to FOC / A']];
const panel=document.getElementById('plots'), cursor=document.getElementById('cursor');let canvases=[];
for(const [field,title] of fields){const box=document.createElement('div');box.className='panel';const h=document.createElement('h2');h.textContent=title;const c=document.createElement('canvas');c.dataset.field=field;box.append(h,c);panel.append(box);canvases.push(c);}
function bounds(){const scenario=document.getElementById('scenario').value,d=data[scenario],last=d.original.time_s.at(-1);let start=Math.max(0,Number(document.getElementById('start').value)),end=Math.min(last,Number(document.getElementById('end').value));if(!(end>start)){start=0;end=last;}return {d,start,end};}
function paint(){const {d,start,end}=bounds();for(const c of canvases){const ratio=devicePixelRatio||1,w=c.clientWidth,h=c.clientHeight;c.width=w*ratio;c.height=h*ratio;const g=c.getContext('2d');g.scale(ratio,ratio);let lo=Infinity,hi=-Infinity;for(const n of names){const x=d[n].time_s,y=d[n][c.dataset.field];for(let i=0;i<x.length;i++)if(x[i]>=start&&x[i]<=end){lo=Math.min(lo,y[i]);hi=Math.max(hi,y[i]);}}if(lo===hi){lo-=.5;hi+=.5;}const pad=(hi-lo)*.06;lo-=pad;hi+=pad;const L=68,R=w-10,T=10,B=h-32;g.font='11px system-ui';g.lineWidth=1;for(let k=0;k<5;k++){const y=T+(B-T)*k/4;g.strokeStyle='#e2e8f0';g.beginPath();g.moveTo(L,y);g.lineTo(R,y);g.stroke();g.fillStyle='#536171';g.fillText((hi-(hi-lo)*k/4).toPrecision(4),3,y+4);}g.fillText(start.toFixed(4),L,B+22);g.fillText(end.toFixed(4),Math.max(L,R-65),B+22);names.forEach((n,k)=>{const x=d[n].time_s,y=d[n][c.dataset.field];g.strokeStyle=colors[k];g.lineWidth=1.4;g.beginPath();let began=false;for(let i=0;i<x.length;i++)if(x[i]>=start&&x[i]<=end){const px=L+(x[i]-start)/(end-start)*(R-L),py=B-(y[i]-lo)/(hi-lo)*(B-T);if(!began){g.moveTo(px,py);began=true;}else g.lineTo(px,py);}g.stroke();});c.onmousemove=e=>{const q=start+Math.max(0,Math.min(1,(e.offsetX-L)/(R-L)))*(end-start),i=Math.min(d.original.time_s.length-1,Math.max(0,Math.round(q/1e-4)));cursor.textContent='t='+d.original.time_s[i].toFixed(6)+' s | '+c.dataset.field+' | '+names.map(n=>n+': '+d[n][c.dataset.field][i].toPrecision(7)).join(' | ');};}}
document.getElementById('apply').onclick=paint;document.getElementById('scenario').onchange=()=>{document.getElementById('start').value=0;document.getElementById('end').value=data[document.getElementById('scenario').value].original.time_s.at(-1);paint();};addEventListener('resize',paint);paint();
</script></html>
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report-dir", type=Path, required=True)
    args = parser.parse_args()
    report = args.report_dir.resolve()
    assert report.is_dir(), report
    outputs = [report / name for name in ("comparison.json", "comparison.md", "comparison.html")]
    assert not any(path.exists() for path in outputs), "Use fresh comparison output paths."
    summary = {"schema": "study_l1_checkpoint_d_comparison_v1",
               "time_alignment": "Same original 100 us observation grid; no waveform shifts.",
               "new_result_scope": "Observed completion count increment since previous 100 us plot sample; not literal hardware valid pulse.",
               "hand_sv_50mhz_setup_pass": False, "hand_sv_frozen_wns_ns": -1.957,
               "scenarios": {}, "input_sha256": {}}
    plots = {}
    markdown = ["# Study-L1 Checkpoint D system comparison", "",
                "All values use the same 100 us observation grid without time shifts. "
                "The new_result plot marks observed completion count increments; exact per-event times are in speed_events.csv.", "",
                "Hand SV retains its Checkpoint C 50 MHz setup failure (WNS −1.957 ns). "
                "System co-simulation does not establish 50 MHz hardware readiness.", ""]
    for scenario in SCENARIOS:
        cases, traces = {}, {}
        for implementation in IMPLEMENTATIONS:
            folder = report / scenario / implementation
            metrics, data, hashes = load_case(folder, scenario, implementation)
            cases[implementation], traces[implementation] = metrics, data
            summary["input_sha256"].update(hashes)
        contract = shared_contract(cases["original"])
        assert all(shared_contract(cases[name]) == contract for name in IMPLEMENTATIONS), scenario
        pairs = {}
        for a, b in itertools.combinations(IMPLEMENTATIONS, 2):
            pairs[f"{a}_vs_{b}"] = differences(traces[a], traces[b])
        # Same RTL numerical contract and same carrier boundary must produce
        # identical closed-loop traces; original float comparisons remain descriptive.
        rtl_pair = pairs["coder_baseline_vs_hand_sv"]
        assert all(rtl_pair[field]["max_abs"] == 0 for field in COMPARISON_FIELDS), scenario
        summary["scenarios"][scenario] = {"cases": cases, "unshifted_pairwise_difference": pairs,
                                           "shared_configuration_pass": True}
        plots[scenario] = {name: figure_data(traces[name]) for name in IMPLEMENTATIONS}
        markdown += [f"## {scenario}", "", "All three case gates and common configuration checks passed.", "",
                     "| Implementation | Speed results | Physical latency / ns | Worst speed-window RMSE / mm/s | iq RMSE / A |",
                     "|---|---:|---:|---:|---:|"]
        for implementation, case in cases.items():
            acceptance = case["step7d_acceptance"]
            speed = acceptance.get("speed", [])
            if speed and isinstance(speed[0], (float, int)):
                speed = [speed]
            speed_rmse = max((row[2] for row in speed), default=None)
            current_rmse = acceptance.get("iq_rmse_A")
            fmt = lambda value: "prefix sanity" if value is None else f"{value:.9g}"
            markdown += [f"| {implementation} | {case['speed_result_count']} | {case['physical_latency_s'] * 1e9:.9g} | {fmt(speed_rmse)} | {fmt(current_rmse)} |"]
        markdown += ["", "| Unshifted pair | Max Δv / mm/s | Max Δspeed PI iq_ref / A | Max Δiq / A |",
                     "|---|---:|---:|---:|"]
        for label, pair in pairs.items():
            markdown += [f"| {label} | {pair['v_mmps']['max_abs']:.9g} | {pair['speed_pi_iq_ref_A']['max_abs']:.9g} | {pair['iq_A']['max_abs']:.9g} |"]
        markdown += ["", "FOC accepted/active IDs and fault/reset status are identical on the common trace grid. "
                     "Full-rate timing/coverage was checked by the unchanged Step7D evaluator. "
                     "Coder baseline and Hand SV are also exactly identical in all seven compared numerical fields without time shifts.", ""]
    summary["comparison_gate_pass"] = True
    write_new(outputs[0], json.dumps(summary, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
    write_new(outputs[1], "\n".join(markdown) + "\n")
    write_new(outputs[2], make_html(plots))
    print("STUDY_L1_D_COMPARISON_PASS cases=9 time_shifts=0 hand_50mhz_setup_pass=0")


if __name__ == "__main__":
    main()
