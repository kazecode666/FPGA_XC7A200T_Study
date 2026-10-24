function [folder,cleanup]=m2_test_model_files
% 每个验收场景只操作本轮正式SLX的逐字节副本，防止工具保存临时观测。
root=fileparts(fileparts(mfilename('fullpath')));names={'PMLSM_PI_FOC_Float_Baseline','PMLSM_FOC_FixedPoint'};
for k=1:numel(names),assert(~bdIsLoaded(names{k}),'M2:TEST_SESSION_BUSY','请用独立验收进程，不接管已加载的%s。',names{k});end
folder=tempname(fullfile(root,'.runtime/m2_20261024'));mkdir(folder);files=cell(1,numel(names));for k=1:numel(names),source=fullfile(root,'simulink模型',[names{k} '.slx']);target=fullfile(folder,[names{k} '.slx']);copyfile(source,target);data=bytes(source);assert(isequal(data,bytes(target)),'M2:TEST_COPY_MISMATCH','验收副本与正式源不一致。');files{k}=struct('source',source,'test_file',target,'Simulink_file_checksum',Simulink.getFileChecksum(source));end
oldPath=path;oldGen=Simulink.fileGenControl('getConfig');addpath(folder,'-begin');Simulink.fileGenControl('set','CacheFolder',fullfile(folder,'cache'),'CodeGenFolder',fullfile(folder,'sim_build'),'createDir',true);
cleanup=onCleanup(@()restore(names,oldPath,oldGen));
manifest=struct('canonical_folder',fullfile(root,'simulink模型'),'test_folder',folder,'process',matlabProcessID,'models',{names},'files',{files},'copies_at_entry_byte_identical',true,'production_models_saved_by_test',false);fid=fopen(fullfile(folder,'provenance.json'),'w');fprintf(fid,'%s',jsonencode(manifest,PrettyPrint=true));fclose(fid);
end
function data=bytes(file),fid=fopen(file,'rb');finish=onCleanup(@()fclose(fid));data=fread(fid,Inf,'*uint8');end
function restore(names,oldPath,oldGen)
for k=1:numel(names),if bdIsLoaded(names{k}),close_system(names{k},0);end;end;path(oldPath);Simulink.fileGenControl('setConfig','config',oldGen);
end
