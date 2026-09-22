function result=step7c_capture_legacy_baseline(stage)
% Deterministic legacy test; temporary taps never saved to the native model.
if nargin==0, stage='before'; end
assert(any(strcmp(stage,{'before','after'})));
root=fileparts(fileparts(mfilename('fullpath'))); oldpwd=pwd; mp=path;
restore=onCleanup(@() restoreSession(oldpwd,mp)); %#ok<NASGU>
cd(root); addpath(fullfile(root,'simulink模型'));
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m),'Close model first');
load_system(m); cm=onCleanup(@() close_system(m,0)); %#ok<NASGU>
outdir=fullfile(root,'docs','reports','step7c'); if ~isfolder(outdir), mkdir(outdir); end
if strcmp(stage,'before')
    assert(getSimulinkBlockHandle([m '/FPGA_HDL_Cosim/HDL_Cosimulation'])>0,'Already refactored');
    ph=get_param([m '/FPGA_HDL_Cosim'],'PortHandles'); assert(isempty(ph.Outport));
    % Remove ONLY the disconnected Step7B monitor in memory to avoid XSI setup.
    delete_block([m '/FPGA_HDL_Cosim']);
end
groups={'Control_Task_10kHz',3;'Inverter_DeadTime',2;'PMLSM_Plant_Model',9;'Inverter_DeadTime/PWM_Update_HalfTs',3};
vars={};
for g=1:size(groups,1)
    src=[m '/' groups{g,1}]; parent=get_param(src,'Parent'); ph=get_param(src,'PortHandles');
    for k=1:groups{g,2}
        v=sprintf('legacy_%d_%d',g,k); vars{end+1}=v; %#ok<AGROW>
        b=[parent '/Step7C_Tap_' v]; add_block('simulink/Sinks/To Workspace',b,'VariableName',v,'SaveFormat','Timeseries');
        dp=get_param(b,'PortHandles'); add_line(parent,ph.Outport(k),dp.Inport,'autorouting','on');
    end
end
si=Simulink.SimulationInput(m); si=si.setModelParameter('StopTime','5e-3','ReturnWorkspaceOutputs','on');
overrides={'Host_Enable_Schedule',[0 1 0 1];'Host_Iq_Test_Mode',1;'Host_Id_A',0;'Host_Iq_A',0.2;'Host_Load_N',0};
for k=1:size(overrides,1), si=si.setVariable(overrides{k,1},overrides{k,2},'Workspace',m); end
checks='';
for k=1:size(overrides,1)
    checks=[checks sprintf('assert(isequal(slResolve(''%s'',bdroot),%s),''LEGACY_OVERRIDE_MISMATCH'');',overrides{k,1},mat2str(overrides{k,2},17))]; %#ok<AGROW>
end
si=si.setModelParameter('StartFcn',checks);
if strcmp(stage,'after'), si=si.setVariable('CONTROL_BACKEND',0); end
out=sim(si); t=(0:50e-6:5e-3)'; data=zeros(numel(t),numel(vars));
for k=1:numel(vars)
    ts=out.get(vars{k});
    % Controller outputs are 100us; sample their held value on the 50us grid.
    data(:,k)=interp1(ts.Time(:),double(ts.Data(:)),t,'previous','extrap');
end
assert(all(isfinite(data),'all'));
file=fullfile(outdir,['legacy_' stage '.txt']); fid=fopen(file,'w'); cf=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'Solver=%s FixedStep=%s effective_step=50us\n',get_param(m,'Solver'),get_param(m,'FixedStep'));
fprintf(fid,'Host_Enable_Schedule=[0 1 0 1] Host_Iq_Test_Mode=1 Host_Id_A=0 Host_Iq_A=0.2 Host_Load_N=0 StopTime=0.005\n');
fprintf(fid,'columns=t cmpA cmpB cmpC vd vq id iq ia ib ic x_mm v_mmps theta_e omega_e delayedA delayedB delayedC\n');
for k=1:numel(t), fprintf(fid,'%s\n',strtrim(sprintf('%.17g ',[t(k) data(k,:)]))); end
fprintf(fid,'min=%s\nmax=%s\nfinal=%s\n',mat2str(min(data),17),mat2str(max(data),17),mat2str(data(end,:),17));
fprintf(fid,'MODEL_SAVED=0\nXSI_SETUP_CALLED=0\nSTEP7C_LEGACY_BASELINE_CAPTURE_PASS\n');
result=struct('time',t,'data',data);
if strcmp(stage,'after')
    lines=splitlines(string(fileread(fullfile(outdir,'legacy_before.txt'))));
    previous=sscanf(strjoin(lines(4:3+numel(t)),newline),'%f',[18 numel(t)])';
    assert(isequal(size(previous),[numel(t) 18])); delta=max(abs(data-previous(:,2:end)),[],1);
    f=fopen(fullfile(outdir,'legacy_compare.txt'),'w'); c=onCleanup(@() fclose(f)); %#ok<NASGU>
    fprintf(f,'max_abs_differences=%s\n',mat2str(delta,17)); assert(all(delta<=1e-10),'Legacy numeric behavior changed');
    fprintf(f,'STEP7C_LEGACY_EQUIVALENCE_PASS\nLEGACY_REQUIRES_XSI=0\n');
end
fprintf('STEP7C_LEGACY_BASELINE_CAPTURE_PASS stage=%s samples=%d\n',stage,numel(t));
end
function restoreSession(p,mp)
cd(p); path(mp);
end
