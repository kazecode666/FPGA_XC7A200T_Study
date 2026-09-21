function step7b_inspect_simple_model(reportFile)
% Inspect the user's model without saving or changing its configuration.
root=fileparts(fileparts(mfilename('fullpath')));
if nargin==0
    reportFile=fullfile(root,'docs','reports','step7b','simple_baseline_inventory.txt');
end
assert(strcmp(version('-release'),'2026b'),'Run this probe in R2026b.');
oldPath=path;
cleanup=onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(fullfile(root,'simulink模型'));
file=fullfile(root,'simulink模型','PMLSM_ThreeLoop_Simple.slx');
assert(isfile(file),'Simple model missing');
mdl='PMLSM_ThreeLoop_Simple';
assert(~bdIsLoaded(mdl),'Use a fresh batch process to protect open user edits.');
before=dir(file);
fid=fopen(reportFile,'w','n','UTF-8');
assert(fid~=-1,'Cannot open report');
closeReport=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'MATLAB=%s\nMODEL=%s\nAS_FOUND_BYTES=%d\n',version,file,before.bytes);
load_system(file);
closeModel=onCleanup(@() close_system(mdl,0)); %#ok<NASGU>
for p={'ModelVersion','SolverType','Solver','FixedStep','InitFcn','PreLoadFcn','PostLoadFcn','StartFcn','StopFcn'}
    fprintf(fid,'%s=%s\n',p{1},get_param(mdl,p{1}));
end
blocks=find_system(mdl,'SearchDepth',1,'Type','Block');
for k=1:numel(blocks)
    fprintf(fid,'ROOT_BLOCK=%s | BlockType=%s | ReferenceBlock=%s\n', ...
        blocks{k},get_param(blocks{k},'BlockType'),get_param(blocks{k},'ReferenceBlock'));
end
for n={'Simple_Host','Control_Task_10kHz','Inverter_DeadTime','PMLSM_Plant_Model'}
    assert(getSimulinkBlockHandle([mdl '/' n{1}])~=-1,'Required block absent: %s',n{1});
end
[refs,refblocks]=find_mdlrefs(mdl,'MatchFilter',@Simulink.match.allVariants);
fprintf(fid,'REFERENCED_MODELS=%s\nREFERENCE_BLOCKS=%s\n',strjoin(refs,','),strjoin(refblocks,','));
mw=get_param(mdl,'ModelWorkspace');
fprintf(fid,'MODEL_WORKSPACE_SOURCE=%s\nMODEL_WORKSPACE_FILE=%s\n',mw.DataSource,mw.FileName);
for f={'design_PMLSM_three_loop','pmlsm_scurve_profile'}
    fprintf(fid,'DEPENDENCY %s=%s\n',f{1},which(f{1}));
end
try
    set_param(mdl,'SimulationCommand','update');
catch ME
    fprintf(fid,'MODEL_UPDATE=FAIL\n%s\n',getReport(ME,'extended','hyperlinks','off'));
    rethrow(ME);
end
after=dir(file);
assert(before.bytes==after.bytes && before.datenum==after.datenum,'Read-only probe changed file');
fprintf(fid,'MODEL_UPDATE=PASS\nAS_FOUND_FILE_UNCHANGED=PASS\n');
fprintf('MODEL_UPDATE=PASS\nAS_FOUND_FILE_UNCHANGED=PASS\n');
end
