function result=m2_verify_foc_fixed_point(stage)
% M2分层独立进程验收；all不覆盖任何source参考。
arguments
 stage (1,:) char {mustBeMember(stage,{'source','interface','types','unit','closedloop','hdlcheck','fresh','all'})}
end
root=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(root,'simulink模型'));folder=fullfile(root,'docs/reports/m2_foc_fixed_point');runtime=fullfile(root,'.runtime/m2_20261024');
if strcmp(stage,'source')
 assert(~isfile(fullfile(folder,'source_acceptance.json')),'M2:REFERENCE_EXISTS','修改前参考不得重建覆盖。');scenes={'standard','daily','current_pos','current_neg','speed_pos','speed_neg','position_neg','ideal','load','reset','alignment'};rows=struct([]);
 for k=1:numel(scenes)
  file=fullfile(runtime,['source_' scenes{k} '.mat']);assert(~isfile(file),'M2:REFERENCE_EXISTS','场景参考已存在，先检查现场。');[out,metadata]=m2_run_shared_case(scenes{k},0);save(file,'out','metadata','-v7.3');
  names=getElementNames(out.logsout);finite=true;nanCount=0;for j=1:numel(names),v=out.logsout.get(names{j}).Values;candidate=startsWith(names{j},'candidate_');if candidate,nanCount=nanCount+sum(~isfinite(v.Data(:)));else,finite=finite&&all(isfinite(v.Data(:)));end;end
  assert(finite);row=struct('scene',scenes{k},'stop_s',metadata.stop_s,'output_and_state_finite',finite,'known_unselected_candidate_nonfinite',nanCount,'x_final_mm',out.logsout.get('x_mm').Values.Data(end),'raw_file',file);if k==1,rows=row;else,rows(k)=row;end;fprintf('M2_SOURCE_SCENE %s nonfinite_candidates=%d\n',scenes{k},nanCount);
 end
 result=struct('version',version,'process',matlabProcessID,'pass',true,'scenes',rows,'source_immutable',true);
elseif strcmp(stage,'all')
 result=struct;for name={'interface','types','unit','closedloop','hdlcheck','fresh'},result.(name{1})=m2_verify_foc_fixed_point(name{1});end;return
elseif strcmp(stage,'types')
 result=m2_test_foc_types;return
elseif strcmp(stage,'interface')
 result=m2_test_foc_interface;return
else
 assert(isfile(fullfile(root,'simulink模型/PMLSM_FOC_FixedPoint.slx')),'M2:FIXED_MODEL_MISSING','尚无独立FOC实现源。');error('M2:STAGE_PENDING','阶段%s尚待实现。',stage);
end
fid=fopen(fullfile(folder,[stage '_acceptance.json']),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);fprintf('M2_%s_PASS\n',upper(stage));
end
