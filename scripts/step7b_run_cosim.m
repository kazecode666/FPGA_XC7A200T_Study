function step7b_run_cosim(mode)
% Assertions read simulator outputs, never a MATLAB-only replacement.
if nargin==0, mode='minimal'; end
root=fileparts(fileparts(mfilename('fullpath')));
assert(strcmp(version('-release'),'2026b'));
if any(strcmp(mode,{'foc','legacy'}))
    step7b_run_foc(mode); return;
end
assert(strcmp(mode,'minimal'),'Unsupported test mode');
file=fullfile(root,'simulink模型','PMLSM_HDL_Cosim_Minimal.slx');
assert(isfile(file),'STEP7B_MISSING_MINIMAL_MODEL');
oldpwd=pwd; oldpath=getenv('PATH'); oldvivado=getenv('XILINX_VIVADO');
restore=onCleanup(@() localRestore(oldpwd,oldpath,oldvivado)); %#ok<NASGU>
hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');
cd(fullfile(root,'.Xil','step7b_minimal_cosim'));
load_system(file); mdl='PMLSM_HDL_Cosim_Minimal';
closeModel=onCleanup(@() close_system(mdl,0)); %#ok<NASGU>
fid=fopen(fullfile(root,'docs','reports','step7b','minimal_cosim_result.txt'),'w');
closeLog=onCleanup(@() fclose(fid)); %#ok<NASGU>
inputs=[0 1 42 127 254 255]; expected=[1 2 43 128 255 0];
for k=1:numel(inputs)
    si=Simulink.SimulationInput(mdl);
    si=si.setBlockParameter([mdl '/Input'],'Value',sprintf('%d',inputs(k)));
    out=sim(si); y=out.get('hdl_output');
    values=double(y.Data);
    assert(values(1)==0,'Reset did not hold output at zero');
    assert(values(end)==expected(k),'Unexpected HDL output for input %d',inputs(k));
    fprintf(fid,'input=%d output=%d reset_output=%d PASS\n',inputs(k),values(end),values(1));
end
fprintf(fid,'STEP7B_SIMULINK_MINIMAL_COSIM_PASS\n');
fprintf('STEP7B_SIMULINK_MINIMAL_COSIM_PASS\n');
end
function localRestore(p,e,v)
cd(p); setenv('PATH',e); setenv('XILINX_VIVADO',v);
end
