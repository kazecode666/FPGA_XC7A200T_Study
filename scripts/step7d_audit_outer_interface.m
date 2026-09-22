function step7d_audit_outer_interface(reportDir)
% Read-only Task 1 gate. No HDL setup, simulation, rewiring or model save.
root=fileparts(fileparts(mfilename('fullpath'))); oldpwd=pwd; oldpath=path;
restore=onCleanup(@()restoreSession(oldpwd,oldpath)); %#ok<NASGU>
cd(root); addpath(fullfile(root,'simulink模型'));
if nargin<1, reportDir=fullfile(root,'docs','reports','step7d',['audit_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]); end
assert(~isfolder(reportDir),'Step7D:ExistingReport','Use a new report directory.');
m='PMLSM_ThreeLoop_Simple';
assert(~bdIsLoaded(m),'Step7D:ModelAlreadyLoaded','Save and close the model before this audit.');
assert(strcmp(version('-release'),'2026b'),'Step7D:WrongRelease','Use MATLAB R2026b.');
mkdir(reportDir); load_system(m); closeModel=onCleanup(@()close_system(m,0)); %#ok<NASGU>
f=fopen(fullfile(reportDir,'outer_interface_gate.txt'),'w');
assert(f>=0); cf=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'MATLAB=%s\nMODEL=%s\nMODEL_SAVED=0\nHDL_SETUP_CALLED=0\nSIMULATION_RUN=0\n',version,get_param(m,'FileName'));
ref=Simulink.ID.getFullName([m ':1744']);
outer=Simulink.ID.getFullName([m ':991']); task=Simulink.ID.getFullName([m ':505']);
ph=get_param(ref,'PortHandles'); h=source(ph.Inport(1));
fprintf(f,'Live iq branch of %s:\n',ref);
for k=1:30
 b=get_param(h,'Parent'); typ=get_param(b,'BlockType'); pn=get_param(h,'PortNumber');
 fprintf(f,'  %s output %d (%s)\n',b,pn,typ);
 if strcmp(b,outer), break;
 elseif strcmp(b,task)
  op=find_system(b,'SearchDepth',1,'BlockType','Outport','Port',num2str(pn)); assert(numel(op)==1);
  p=get_param(op{1},'PortHandles'); h=source(p.Inport(1));
 elseif strcmp(typ,'DataTypeConversion')
  p=get_param(b,'PortHandles'); h=source(p.Inport(1));
 elseif strcmp(typ,'From')
  gs=find_system(get_param(b,'Parent'),'SearchDepth',1,'BlockType','Goto','GotoTag',get_param(b,'GotoTag'));
  assert(numel(gs)==1,'Step7D:AmbiguousTag','Expected unique same-scope Goto.');
  assert(strcmp(get_param(gs{1},'TagVisibility'),'local'));
  fprintf(f,'  via local tag [%s], producer %s\n',get_param(b,'GotoTag'),gs{1});
  p=get_param(gs{1},'PortHandles'); h=source(p.Inport(1));
 elseif strcmp(typ,'Inport')
  parent=get_param(b,'Parent'); p=get_param(parent,'PortHandles');
  h=source(p.Inport(str2double(get_param(b,'Port'))));
 else
  break
 end
end
actual=get_param(h,'Parent'); actualPort=get_param(h,'PortNumber');
p=get_param(task,'PortHandles');
fprintf(f,'ACTUAL_SOURCE=%s/%d\nEXPECTED_OUTER_REFERENCE=%s/2\nCONTROL_TASK_OUTPUT_COUNT=%d\n',actual,actualPort,outer,numel(p.Outport));
fprintf(f,'Separately audited outer producer: Speed_Loop/1 -> local [iq_ref_normal] -> Reference_Manager/1 -> selected iq_ref output 2.\n');
if ~strcmp(actual,outer) || actualPort~=2
 fprintf(f,'STEP7D_TASK1_BLOCKED_LIVE_REFERENCE_SOURCE\n');
 error('Step7D:LiveReferenceSourceMismatch', ...
  'Live iq resolves to %s/%d, not the selected outer reference. Task 1 stopped; see %s.',actual,actualPort,reportDir);
end
fprintf(f,'STEP7D_OUTER_SOURCE_GATE_PASS\n');
end
function h=source(p)
l=get_param(p,'Line'); assert(l>0,'Step7D:DisconnectedInput','Missing signal line.');
h=get_param(l,'SrcPortHandle'); assert(h>0);
end
function restoreSession(p,mp)
cd(p); path(mp);
end
