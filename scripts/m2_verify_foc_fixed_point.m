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
 assert(numel(dir(fullfile(runtime,'source_*.mat')))==11,'M2:SOURCE_EVIDENCE_MISSING','all需要本次修改前原始参考；普通Run/fresh不需要。');
 % Fresh must be first: it deliberately rejects an initialized workspace.
 result=struct;failures=cell(0,1);for name={'fresh','interface','types','unit','closedloop','hdlcheck'},try,result.(name{1})=m2_verify_foc_fixed_point(name{1});catch e,entry=struct('stage',name{1},'identifier',e.identifier,'message',e.message);failures{end+1}=entry;end;end;result.failures=failures;result.pass=isempty(failures);fid=fopen(fullfile(folder,'all_acceptance.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);assert(result.pass,'M2:VALIDATION_FAILED','存在失败阶段；独立阶段已继续，见all_acceptance.json。');return
elseif strcmp(stage,'unit')
 result=struct('unit',m2_test_foc_unit,'bus',m2_test_foc_bus,'long',m2_test_foc_long);return
elseif strcmp(stage,'closedloop')
 result=struct;failures=cell(0,1);for name={'scenes','paired','live'},try,if strcmp(name{1},'scenes'),result.scenes=m2_test_foc_closedloop;else,result.(name{1})=m2_test_foc_moves(name{1});end;catch e,entry=struct('stage',name{1},'identifier',e.identifier,'message',e.message);failures{end+1}=entry;end;end;m2_summarize_foc_results;result.failures=failures;result.pass=isempty(failures);fid=fopen(fullfile(folder,'closedloop_suite.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);assert(result.pass,'M2:CLOSEDLOOP_SUITE','闭环存在失败；独立检查已继续，见closedloop_suite.json。');return
elseif strcmp(stage,'fresh')
 result=m2_test_foc_fresh;return
elseif strcmp(stage,'types')
 result=m2_test_foc_types;return
elseif strcmp(stage,'interface')
 result=m2_test_foc_interface;return
elseif strcmp(stage,'hdlcheck')
 result=struct('isolation',m2_test_foc_isolation,'compatibility',m2_check_foc_compatibility);return
end
fid=fopen(fullfile(folder,[stage '_acceptance.json']),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);fprintf('M2_%s_PASS\n',upper(stage));
end
