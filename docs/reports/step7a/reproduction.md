# 最小验证复现

使用本报告的 R2026b Prerelease MATLAB，初始 pwd 为 D:/Project/FPGA_XC7A200T。
以下为本次实际执行命令的文本记录；第二段把当次绝对 TEMP 路径改为第一段返回的 trial 变量。
先在同一 MATLAB 会话执行第一段，确认 WORKFLOW_GENERATED，再执行第二段。
所有 HDL 和 Wizard 输出写入 tempname 创建的系统临时目录；无需已有 FPGA 工程。
失败时保留第一处错误，不抑制版本警告。不要在第一段失败后执行第二段。

## 生成 HDL / XSI / MATLAB 接口

```matlab
fprintf('MINIMAL_BEGIN\n');
oldpwd=pwd; oldpath=getenv('PATH'); oldvivado=getenv('XILINX_VIVADO');
trial=tempname; mkdir(trial); cd(trial); fprintf('TRIAL_DIR=%s\n',trial);
fid=fopen('cosim_counter.sv','w'); fprintf(fid,'`timescale 1ns/1ps\nmodule cosim_counter(input logic clk, input logic reset_n, input logic [7:0] in_data, output logic [7:0] out_data);\nalways_ff @(posedge clk or negedge reset_n) begin\nif (!reset_n) out_data <= 0; else out_data <= in_data + 1;\nend\nendmodule\n'); fclose(fid);
try
hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');
c=cosimulationConfiguration('Vivado Simulator','MATLAB System Object','cosim_counter');
c.HDLFiles={'cosim_counter.sv','Verilog'};
c.HDLSimulatorPath='E:/AMDDesignTools/2026.1/Vivado/bin';
c.ClockPortRegularExpression='^$'; c.ResetPortRegularExpression='^$';
c.HDLTimeUnit='ns'; c.SampleTime=10;
runWorkflow(c);
fprintf('WORKFLOW_GENERATED\n'); disp(dir);
catch ME, fprintf('FIRST_ERROR_ID=%s\nFIRST_ERROR=%s\n',ME.identifier,ME.message); disp(ME.stack); end
cd(oldpwd); setenv('PATH',oldpath); setenv('XILINX_VIVADO',oldvivado); fprintf('PATH_RESTORED=%d\nMINIMAL_END\n',strcmp(oldpath,getenv('PATH')));


```

## 真实数据交换

```matlab
fprintf('EXCHANGE_BEGIN\n'); oldpwd=pwd; oldpath=getenv('PATH'); oldvivado=getenv('XILINX_VIVADO');
cd(trial);
try
hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');
h=hdlcosim_cosim_counter; tick=0;
for k=1:3, y=h(false,false,fi(0,0,8,0)); fprintf('tick=%d clk=0 reset_n=0 input=0 output=%g\n',tick,double(y)); tick=tick+1; end
assert(double(y)==0,'Reset output must be zero');
inputs=[0 1 42 127 254 255];
for x=inputs
for clk=[0 0 1 1 0]
y=h(logical(clk),true,fi(x,0,8,0)); fprintf('tick=%d clk=%d reset_n=1 input=%d output=%g\n',tick,clk,x,double(y)); tick=tick+1;
end
expected=mod(x+1,256); assert(double(y)==expected,'HDL output mismatch'); fprintf('PAIR_PASS input=%d output=%g expected=%d\n',x,double(y),expected);
end
release(h); fprintf('REAL_COSIM_EXCHANGE=PASS\n');
catch ME, fprintf('FIRST_ERROR_ID=%s\nFIRST_ERROR=%s\n',ME.identifier,ME.message); end
cd(oldpwd); setenv('PATH',oldpath); setenv('XILINX_VIVADO',oldvivado); fprintf('PATH_RESTORED=%d\nEXCHANGE_END\n',strcmp(oldpath,getenv('PATH')));

```
