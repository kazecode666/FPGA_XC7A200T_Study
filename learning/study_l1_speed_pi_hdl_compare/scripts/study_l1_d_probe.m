function study_l1_d_probe(runname)
% Read only audit of a private copy; never opens/saves the formal source model.
s=fileparts(mfilename('fullpath')); study=fileparts(s); root=fileparts(fileparts(study));
if nargin<1, runname='d_probe_01'; end
w=fullfile(study,'.runtime',runname); assert(~isfolder(w)); mkdir(w); cd(w);
diary(fullfile(w,'probe.txt')); cleaner=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('MATLAB_D_GATE %s %s PWD=%s\n',version,version('-release'),pwd);
for f={'Simulink','Fixed_Point_Toolbox','EDA_Simulator_Link'}
 fprintf('LICENSE %s %d\n',f{1},license('test',f{1}));
end
assert(strcmp(version('-release'),'2026b'));
addpath(s,fullfile(root,'scripts'),fullfile(root,'simulink模型'));
Simulink.fileGenControl('set','CacheFolder',fullfile(w,'cache'),'CodeGenFolder',fullfile(w,'codegen'),'createDir',true);
src=fullfile(root,'simulink模型','PMLSM_ThreeLoop_Simple.slx');
dst=fullfile(w,'study_l1_d_probe_model.slx'); copyfile(src,dst);
cd(fullfile(root,'simulink模型')); load_system(dst); m='study_l1_d_probe_model';
set_param(m,'InitFcn','','StartFcn','','StopFcn','');
mw=get_param(m,'ModelWorkspace'); disp(mw); reload(mw);
p=study_l1_init; for name=fieldnames(p)'
 val=mw.getVariable(name{1}); assert(isequal(val,p.(name{1})),'Frozen coefficient mismatch %s',name{1});
 fprintf('FROZEN %s %.17g\n',name{1},val);
end
for sid=[505 1122 1189 991 1453 740 1200 1201 1202 1264 1261 1272]
 b=Simulink.ID.getFullName(sprintf('%s:%d',m,sid)); fprintf('\nSID%d %s\n',sid,b);
 ph=get_param(b,'PortHandles');
 for j=1:numel(ph.Inport)
  ln=get_param(ph.Inport(j),'Line'); if ln~=-1, sp=get_param(ln,'SrcPortHandle'); fprintf('IN%d <- %s p%d\n',j,get_param(get_param(sp,'Parent'),'Name'),get_param(sp,'PortNumber')); end
 end
 for j=1:numel(ph.Outport)
  ln=get_param(ph.Outport(j),'Line'); if ln~=-1, dstp=get_param(ln,'DstPortHandle'); for dp=dstp(:)', fprintf('OUT%d -> %s p%d\n',j,get_param(get_param(dp,'Parent'),'Name'),get_param(dp,'PortNumber')); end; end
 end
 if strcmp(get_param(b,'BlockType'),'SubSystem'), fprintf('Children=%s\n',strjoin(find_system(b,'SearchDepth',1),' | ')); end
end
rt=sfroot; em=rt.find('-isa','Stateflow.EMChart');
for k=1:numel(em), if contains(em(k).Path,'Reference_Manager') || contains(em(k).Path,'Reset_Manager'), fprintf('CHART %s\n%s\n',em(k).Path,em(k).Script); end; end
close_system(m,0); cd(w); fprintf('D_READ_ONLY_PROBE_PASS\n');
end
