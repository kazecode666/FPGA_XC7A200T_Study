# PR53 局部流水线续办

R1 实测原 DCP `fa572493...`，其 OOC manifest 与 B3 `cfd8b1d...` 相同。导出100条最差setup和5类各20条路径，共200条，以及20条hold、check_timing、439个DSP的寄存属性。见 `docs/reports/m3_foc_hdl/pr53_pipeline_revision/`。完整报告/DCP保留在 `.runtime/pr53_20261025/`。

| 路径类 | 原WNS ns | 逻辑/估算连线 ns | 级数 |
|---|---:|---:|---:|
| 限幅Divide→反Park→XYZ/扇区→T1除法输入 | -58.833 |57.113/21.675|154|
| 反Park内部DSP→T1除法输入 | -39.979 |44.742/15.191|120|
| XYZ内部DSP→T2除法输入 | -14.241 |25.501/8.695|72|
| PI d旧态→限幅sqrt | -7.122 |19.660/7.280|84|
| PI q旧态→限幅sqrt | -6.581 |19.674/6.725|84|

原配置 DistributedPipelining=off；相关InputPipeline/OutputPipeline=0。439个DSP均MREG/PREG=0，其中327个连AREG/BREG也为0。InversePark的165级sin/cos匹配链没有切分dcos/qsin乘加。单给输出延时不会切开这条路径。

最新本地定点SLX SHA `ec14e246...` 与首轮不同；逐成员检查表明模型XML差异是Position/Points，算法内部成员未变。候选复制最新本地布局；旧DCP只作原算法基线。用户文件不保存、不替换。Float参考字节相同。

候选p1假设：为限幅后半段、反Park以及XYZ/扇区局部提供寄存预算并启用对应分布式流水线；局部乘加链被重新分段，旁路由HDL Coder自动平衡。不会修改算法UnitDelay。后续候选只依据实际新路径决定，最多3个。配置on不等于网表生效，必须查实际报告。

官方方法依据：[Clock-rate FOC示例](https://www.mathworks.com/help/hdlcoder/ug/clockratepipelining.html)、[Distributed pipelining](https://www.mathworks.com/help/hdlcoder/ug/distributed-pipelining.html)。本机示例模型不在默认路径，未执行示例初始化。旧手写六扇区只借鉴寄存分段；没有替换六扇区算法、查表、位宽或输出极性。

当前仍 NOT_ACCEPTED，R2—R4待实测。原−58.833ns、274拍和首轮全部生成/失败报告保留。
