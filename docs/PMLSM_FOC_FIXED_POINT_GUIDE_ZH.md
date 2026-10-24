# M2 FOC 定点模型操作

日常仍打开同一个 `PMLSM_PI_FOC_Float_Baseline.slx`。只在停止状态执行一次：

本轮实现待Review：11类场景/独立单元已通过，连续点位的电流和速度差仍超冻结预算，未宣称全部验收通过。正常操作及失败指标见[整合验收](../coordination/reports/m2_foc_fixed_point_implementation.md)。

```matlab
addpath('D:/Project/FPGA_XC7A200T/simulink模型');
init_PMLSM_PI_FOC_Float_Baseline;
FOC_Impl_Select=1; % 0原浮点参考（默认），1新定点FOC
open_system('PMLSM_PI_FOC_Float_Baseline');
```

然后正常点 Run。初始化保留 10 mm、5 s、V10/A100 的日常默认。停止后设置 `FOC_Impl_Select=0` 再 Run 即可比较浮点。实现选择在编译时生效，运行中不支持热切；在线发送新位置时不要重新执行初始化。

依赖共八个文件，均在 `simulink模型`：主 SLX、`PMLSM_FOC_FixedPoint.slx`、上述 init、`m1a_require_float_init.m`、`pmlsm_foc_fixed_config.m`、`design_PMLSM_three_loop.m`、`pmlsm_scurve_profile.m`、`pmlsm_point_move_step.m`。不依赖旧 MAT、XSI 或开发验收数据。已在独立目录/新 MATLAB 进程逐一运行两种实现。

## 指令、轨迹和对齐

继续使用 Simple_Host 原面板：目标值是草稿，到位后切换 `Host_Move_Request` 的 0/1 值才提交。Busy 时拒绝，不排队；参考 S 曲线、接受目标、Ready 和命令计数仍可在旁边的原 Monitor/Scope 观察。Ready 会随既有未补偿纹波退出到位窗，发送时以当前 Ready 为准；首次到过 Ready 不代表以后一直为 Ready。

连续发目标、反向、PWM/PI 复位及暂停/继续沿用原操作。调试模式在停止后设置。原对齐默认旁路；启用时仍按 Start=0→1→完成→0，不新增边沿协议。未知非零偏置识别没有新增验收。三环 PI、默认死区和原到位窗均未调整。

## 具名数据与类型

Run 后在 Workspace 的 `out.logsout`、Monitor 或 SDI 查看具名信号：`id`、`iq`、`x_mm`、`x_ref_mm`、`v_mmps`、`vd_cmd`、`vq_cmd`、`x_d`、`x_q`、`du_d_z`、`du_q_z`、三相 command/active duty，以及 `target_accepted_mm`、`move_ready`、命令计数。一次仅有活动实现的同名 FOC 日志，不需要按列序号找变量。

例如查看电流，定点数据作图时显式转 double：

```matlab
iq=out.logsout.get('iq').Values;
plot(iq.Time,double(iq.Data)); grid on; xlabel('s'); ylabel('Apeak');
```

比较两个 Run 时先将第一次的 `out` 保存为另一个变量，停止后改变实现再 Run；按同一时间轴比较，不能平移曲线。开发验证图和量化增量见[结果索引](reports/m2_foc_fixed_point/README.md)，同时列出原有纹波本身。

唯一类型来源为 `FOC_Fixed_Config=pmlsm_foc_fixed_config(FOC_Fixed_Parameters)`，由 init 在成功标识前建立。物理参数和 PI 仍来自原初始化。改变这些参数后需停止并重新派生一致配置；检查回调只检查，不默默恢复默认。实际采用类型、系数误差和库内部编译类型见[设计记录](FOC_FIXED_POINT_DESIGN.md)。

进入 `Control_Task_10kHz/FOC_Implementation/Fixed/FOC_Model` 可打开唯一引用源 `PMLSM_FOC_FixedPoint/FOC_DUT`。根层独立 DUT 输入前八个顺序保留，第九个为 Vdc_V。角度 rad、电速度 rad/s、电流 Apeak、电压 V；输出是 [0,1] 的上管 command duty，0、0.5、1 可精确表示。外部浮点环境通过显式编码/解码连接；DUT 内部实际 fixed/integer/boolean，DataTypeOverride=Off。

首版验证条件为各相电流/各参考±2 A、theta±8π rad、omega±100 rad/s、Vdc 12–60 V、零初态、60 s；不是板卡或电机额定部署范围。共享环境默认 Vdc=48 V。独立向量测试会拒绝越界/非有限值，这不构成完整在线保护系统。

## 开发复验边界

在新的独立 MATLAB 进程调用 `scripts/m2_verify_foc_fixed_point(stage)`，阶段为 interface/types/unit/closedloop/hdlcheck/fresh/all。`all` 首先验收独立八文件包，不重建或覆盖修改前 source；closedloop/all目前应因连续点位预算失败非零退出，独立阶段继续并汇总失败。A 的原始大 MAT 在本地 `.runtime/m2_20261024`，需要这些参考的阶段在缺失时应报错；普通 Run 和 fresh 不需要它们。不要在有用户未保存模型的交互会话运行开发验收。

本轮只执行 checkhdl，未生成 HDL/C、未运行 Vivado。100 µs 是控制调用周期；M3 还需验证除法/开方/LUT的硬件流水线、真实延迟及 PWM 生效时限。详见[整合验收](../coordination/reports/m2_foc_fixed_point_implementation.md)。
