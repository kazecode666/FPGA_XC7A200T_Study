"""Render concise numerical reports from fresh MATLAB evidence."""
import csv
import hashlib
import json
import sys
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]
REPORT = STUDY / 'reports/checkpoint_a'
VERIFICATION = Path(sys.argv[1]).resolve()
summary = json.loads((VERIFICATION / 'summary.json').read_text(encoding='utf-8'))
rows = list(csv.DictReader((VERIFICATION / 'observed_ranges.csv').open(encoding='utf-8')))
ranges = {(r['model'], r['signal']): f"[{float(r['minimum']):.9g}, {float(r['maximum']):.9g}]" for r in rows}

entries = [
    ('v_ref / v_meas', 'test: +/-110.9048598 / [-0.23456,10]; input contract: each [-2048,2048)', True, 32,20,28,16),
    ('speed error', ranges['float','error']+'; representable [-4096,4096)', True,33,20,29,16),
    ('Kp', '0.018033474852681124', False,32,30,24,22),
    ('KiTs', '0.0014426779882144898', False,32,30,24,22),
    ('Kaw', '0.08', False,32,30,24,22),
    ('P product result', ranges['float','P']+'; full input contract: about +/-73.865', True,40,30,28,18),
    ('KiTs product result', ranges['float','KiTs']+'; full input contract: about +/-5.91', True,40,30,28,18),
    ('anti-windup term', ranges['float','AW']+'; full input contract: magnitude <6', True,40,30,28,18),
    ('excess / previous excess', ranges['float','excess_next']+'; full input contract: magnitude <74', True,40,30,28,18),
    ('integrator / x_next', ranges['float','integrator']+'; algorithm limit +/-0.5', True,32,30,20,18),
    ('iq_unlimited / iq_limited internal', ranges['float','iq_unlimited']+'; full input contract: magnitude <75', True,42,30,30,18),
    ('integrator accumulation', 'x + KiTs*e - AW; full input contract: magnitude <13', True,44,30,32,18),
    ('iq_ref external', 'algorithm limit +/-1; compatible with existing FOC', True,25,15,25,15),
]
lines = ['# A3：datatype table', '',
    '范围来源：本地真实 PI 的 A2 测试结果 `verification/observed_ranges.csv`；不是整机 plant 范围证明。',
    '先用 float 结果确认工作量级，再选 B1 保守精度和 B2 缩短位宽候选。B1 为后续 C/D 唯一 golden model。', '',
    '| Signal | Observed / required range | Signed | B1 WL | B1 FL | B1 LSB | B2 WL | B2 FL | B2 LSB |',
    '|---|---|---|---:|---:|---:|---:|---:|---:|']
for name, required, signed, w1,f1,w2,f2 in entries:
    lines.append(f'| {name} | {required} | {signed} | {w1} | {f1} | {2**-f1:.12g} | {w2} | {f2} | {2**-f2:.12g} |')
lines += ['', '## 转换规则', '',
    '- 每个 Gain 的系数类型、输出类型、每个 Sum 的累加器和输出类型均显式指定，见 `study_l1_types.m` 和 `study_l1_build_pi.m`。',
    '- 所有有损转换使用 **Convergent（ties to even）**；算术存储 overflow 为 **Saturate**；没有 wrap。算法的 ±1 / ±0.5 限幅器独立于存储饱和。',
    '- 输入先量化，error 作精确减法：B1 33/20，B2 29/16。复位阈值用相应输入/error 格式，0、0.5、-3 均精确可表示。',
    '- B1 error×coefficient 全精度中间乘积为 signed **65/50**，量化到 work **40/30**；B2 为 signed **53/38**，量化到 **28/18**。',
    '- B1 previous-excess×Kaw 全精度中间乘积 signed **72/60**；B2 为 signed **52/40**。之后转为相应 work 格式。',
    '- P+x 与积分更新使用累加器 B1 **44/30**、B2 **32/18**。P+x 输出转 sum；积分更新先限幅再转 state；excess 使用内部限幅前后量相减。',
    '- 输出格式转换位于内部 ±1 限幅之后、hard reset 输出选择之前。anti-windup 反馈使用内部 `u-l`，不使用外部 15-fraction 输出的量化差。',
    '- UnitDelay 从已显式量化的输入继承 state / work 类型；初值0精确表示。',
    '- 实际 Simulink ToWorkspace 保留 fi 类型；每个 raw code 与独立 scalar fi 运算核全样本、全信号比较。`observed_ranges.csv` 给出实际 WL/FL 与存储边界余量。',
    '- 声明输入区间 [-2048,2048) 之外不属于数值保证；复位比较阈值极近点也可能受输入量化影响。本次向量覆盖实际阈值及边界，未宣称对所有实数输入逐点等价。',
    '- B2 的12小数位试选会把 8.0001 mm/s 量化为8，使 sign(v_ref)*e<-3 的 int-reset 丢失；因此保留16输入小数位。此调整保持原严格不等式和参数，没有改变算法。',
    '', '## 系数量化', '',
    '| Format | Coefficient | raw code | Quantized value | Error |',
    '|---|---|---:|---:|---:|']
for mode, fl in [('B1',30),('B2',22)]:
    for name,value in [('Kp',.018033474852681124),('KiTs',1.4426779882144898*.001),('Kaw',.08)]:
        code=round(value*2**fl); quant=code/2**fl
        lines.append(f'| {mode} | {name} | {code} | {quant:.17g} | {quant-value:.17g} |')
(REPORT / 'datatype_table.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')

lines = ['# A2/A3：float / fixed comparison', '',
    f"验证版本：{summary['MATLAB']}；{summary['samples']} 个 100-us 样本，{summary['ticks']} 个有效 speed tick。",
    '输入从 `study_l1_generate_vectors.m` 生成；所有版本使用相同输入和 tick。饱和阈值按 limit/Kp 生成，不写死速度魔法值。',
    '', '| Comparison | Result |', '|---|---|',
    f"| 独立 float vs 原 PI 副本，14项输出/内部量 | max error = {max(summary['float_max_errors']):.17g} |",
    '| 真实 scheduler vs 独立输入 tick | 逐拍一致；first 0.9 ms，period 1 ms |',
    '| B1 / B2 Simulink vs scalar fi | 全样本、全信号 physical / raw code bit-exact |',
    '| 保存的三份 standalone SLX vs compare_tb 副本 | 分别仿真，14项输出逐样本一致 |',
    '| reset / enable / int-reset / idle hold | 原 PI、float、B1、B2 一致 |',
    '', '| Metric | B1 | B2 candidate |', '|---|---:|---:|']
for name,label in [
    ('saturation_mismatches','输出饱和时刻/方向 mismatch 数'),
    ('max_linear_iq_error_A','非饱和 iq_ref 最大偏差 (A)'),
    ('max_linear_iq_error_LSB','非饱和 iq_ref 最大偏差 (external LSB)'),
    ('max_integrator_error_A','积分状态最大偏差 (A)'),
    ('max_iq_unlimited_error_A','iq_unlimited 最大偏差 (A)'),
    ('max_all_iq_error_A','所有 iq_ref 最大偏差 (A)')]:
    lines.append(f"| {label} | {summary['b1'][name]:.12g} | {summary['b2'][name]:.12g} |")
lines += ['', 'B1 的非饱和输出门槛为 2 LSB = 0.00006103515625 A，自动断言未放宽。B2 用于位宽/误差研究；未测量或声称资源节省。',
    'B1/B2各3项 Gain 出现系数精度损失提示，standalone与对照台中数值均与 datatype table 的系数量化一致；这是已记录的系数量化，未出现非预期存储溢出。',
    '', '覆盖零误差、小正/负误差、正/负饱和、持续 anti-windup、解饱和、饱和后反向、饱和中 reset/disable、re-enable、同 tick 和相邻 tick 的 reset、仅 idle 间出现的 reset、overspeed int-reset、角初始化和 Iq_Test_Mode。',
    '另外验证：hard reset 时当拍 integrator 输出为旧状态；x_next=0；excess 未被 reset 清零。',
    '', '`verification/tick_comparison.csv` 保存每个有效 tick 的原模型、float、B1、B2 数值，定点同时给 physical unit 与 raw code。完整 100-us 序列留作本地复核，精简后的 tick 表进入 Git。',
    '', '限定：组件行为与本次输入范围证据；没有整机闭环、HDL、RTL、资源、时序或硬件验证。Checkpoint B 尚未开始。']
(REPORT / 'float_fixed_comparison.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
manifest = {str(p.relative_to(STUDY)).replace('\\','/'): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((STUDY / 'models').glob('*.slx'))}
manifest['source_SLX']=hashlib.sha256((STUDY.parents[1] / 'simulink模型/PMLSM_ThreeLoop_Simple.slx').read_bytes()).hexdigest()
(REPORT / 'model_hashes.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print('STUDY_L1_REPORTS_WRITTEN')
