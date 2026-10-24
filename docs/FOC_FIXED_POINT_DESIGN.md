# M2独立FOC定点设计

## 转换前冻结：2026-10-24

源为本地最新PR49浮点FOC，PR50已合并1cab599。A在任何SLX改动前独立采集11个工况；B先抽取double、增加9th Vdc，并在除法前保护未选中零分母候选，108项严格迁移指标通过（duty≤1e-12，电压/状态≤1e-10）。原近似常数0.866/1.7321保留。详见[source](reports/m2_foc_fixed_point/source_acceptance.json)、[B](reports/m2_foc_fixed_point/interface_metrics.csv)。预算在定点实现前冻结于[contract](reports/m2_foc_fixed_point/acceptance_contract.json)，属于工程验证目标，不是硬件额定指标。

## 范围的四种依据

| 项 | 硬件/物理资料 | 当前配置 | 已有观察 | 首版工程验证范围 |
|---|---|---|---|---|
| 相电流/参考 | 硬件说明/YXPHM-MDBL4电机驱动板硬件说明书p1—2称12A额定；不是电机额定/完整采集链合同；p14过流约+27/-29A为保护阈值 | 速度环输出±1A，手动参考无同一全局钳位；对齐.5A | M1B及A保存波形，不能当最大值 | 相电流各±2A；id/iq参考各±2A。算法向量可不平衡，单独标注 |
| 母线 | 说明书p1输入12—60V，p2另列12—80V且额定60V；p15过压阈60V，资料有差异 | 默认48V | 默认均48V | [12,60]V，受限仿真范围，不据此批准实机60V |
| 控制电速度 | 未找到电机额定/最大速度确定记录；旧DSP标度不等于物理极限 | 位置速度限幅20mm/s→2.0944rad/s | A正负速度/闭环场景 | ±100rad/s，附显式输入条件 |
| 角度 | 真实采集/安装偏置不是本轮范围 | 控制角与真实角独立，rad | A含原标称对齐 | ±8π rad，含负值、0/2π及多周期边界 |
| 初态/时长 | 无无限时长硬件证明 | 原FOC积分/AW初值0，100µs更新 | A最长日常5s/对齐4.5s | 零状态起点、声明输入范围、60s序列；另做递推界，不宣称所有参数/硬件无限鲁棒 |

源PDF已用本地pypdf提取文本留.runtime，M0索引和实际init参数交叉核对。电机额定电流、速度、驱动持续过载/热限制、ADC硬量程仍待后续资料签定。没有要求用户重填已存在信息，没有沿用旧24bit/2500。

## 运算位增长和状态界

相电流各|i|≤2，则Clarke |alpha|≤8/3，|beta|≤4/√3。正交Park的轴界保守取 sqrt((8/3)^2+(4/√3)^2)；现有线性LUT插值位于单位圆弦内，量化小余量另由宽类型及测试覆盖。误差界 E=2+轴界，电压前馈界 F=100*(max(Ld,Lq)*轴界+psi)，圆输出界 U=.9*60/√3。原输出u_raw=Kp*e+x+ff，没有用圆限幅替代状态范围。

无复位时每轴 x[k+1]=x[k]-a*x[k-1]+b[k]，a=Kaw∈(0,.25]，b=KiTs*e[k]-a*(Kp*e[k-1]+ff[k-1]-u_lim[k-1])。零初态下特征根在(0,1)，脉冲响应非负且绝对和1/a，因此 |x|≤KiTs*E/a+Kp*E+F+U。控制复位优先将输出和次拍积分置0；AW延迟仍按原raw-minus-limited更新，不额外清零。配置函数从实际参数计算state/raw/square界；非当前Kaw条件明确拒绝，不能假称证明所有重调参数。

数据增加/乘法/平方先保证足够整数位，输出量化点明确收敛舍入。Work为64bit/40小数位，状态存储没有算法硬钳位；Square无符号64/36，最小epsilon=1e-6量化后非零。未限幅比例U/(sqrt(sum)+epsilon)在零电压时可达约3.12e7，因此单独用无符号72/40，不以随后min(1)掩盖中间溢出。

## 类型和系数单一来源

`cfg=pmlsm_foc_fixed_config(p)`，p显式来自当前Rs/Ld/Lq/psi/Kp/Ki/Kaw_d/q/Ts/Udc。配置含Types、TypeStrings、Coefficients、Ranges、Version和Convergent/Saturate fimath；不加载旧参数。所有系数从现有值一次量化，含Ki*Ts、原0.866/1.7321、epsilon及-2/T_pwm。

[实际类型表](reports/m2_foc_fixed_point/types.csv)、[系数量化表](reports/m2_foc_fixed_point/coefficients.csv)、[推导界/配置验收](reports/m2_foc_fixed_point/types_acceptance.json)。Duty无符号32/30，0、.5、1精确；算法输出限幅与数值表示饱和分开，范围内数值饱和/溢出目标为0。输入负例在测试/边界明确诊断，不新增完整保护系统。

## 后续实际实现映射和结果

D—F完成后补入实际编译类型、算子映射、状态/量化/闭环/兼容性结果；本节不预写通过。没有HDL/C生成或Vivado授权。
