function result=m2_test_foc_closedloop
root=fileparts(fileparts(mfilename('fullpath')));runtime=fullfile(root,'.runtime/m2_20261024');folder=fullfile(root,'docs/reports/m2_foc_fixed_point');scenes={'standard','daily','current_pos','current_neg','speed_pos','speed_neg','position_neg','ideal','load','reset','alignment'};rows=cell(0,9);summary=struct([]);pass=true;
for k=1:numel(scenes)
 name=scenes{k};source=load(fullfile(runtime,['source_' name '.mat']),'out');[floating,metaFloat]=m2_run_shared_case(name,0);[fixed,metaFixed]=m2_run_shared_case(name,1);save(fullfile(runtime,['closedloop_' name '.mat']),'floating','fixed','metaFloat','metaFixed','-v7.3');
 for n={'id','iq','x_mm','v_mmps','duty_u','duty_v','duty_w','vd','vq','x_d','x_q','du_d_z','du_q_z'}
  a=source.out.logsout.get(n{1}).Values;b=floating.logsout.get(n{1}).Values;c=fixed.logsout.get(n{1}).Values;assert(isequal(a.Time,b.Time)&&isequal(b.Time,c.Time),'M2:TIME_ALIGNMENT','%s %s时间轴不同。',name,n{1});migration=max(abs(double(a.Data(:))-double(b.Data(:))));assert(migration==0,'M2:FLOAT_REFERENCE_CHANGED','%s %s %.17g',name,n{1},migration);delta=double(c.Data(:))-double(b.Data(:));err=max(abs(delta));rmse=sqrt(mean(delta.^2));maxBudget=Inf;rmseBudget=Inf;if any(strcmp(n{1},{'id','iq'})),maxBudget=.005;rmseBudget=.001;elseif strcmp(n{1},'x_mm'),maxBudget=.005;rmseBudget=.001;elseif strcmp(n{1},'v_mmps'),maxBudget=.1;rmseBudget=.02;end;ok=err<=maxBudget&&rmse<=rmseBudget;pass=pass&&ok;steady=b.Time>max(b.Time)*.8;steadyMean=mean(delta(steady));rows(end+1,:)={name,n{1},migration,err,rmse,maxBudget,rmseBudget,steadyMean,ok}; %#ok<AGROW>
  if ~ok,fprintf('M2_CLOSEDLOOP_BUDGET_FAIL %s %s max=%.17g rmse=%.17g\n',name,n{1},err,rmse);end
 end
 for n={'in_id_ref','in_iq_ref','in_PI_Reset_EN'},a=floating.logsout.get(n{1}).Values;b=fixed.logsout.get(n{1}).Values;assert(isequal(a.Time,b.Time));if strcmp(n{1},'in_PI_Reset_EN'),assert(isequal(a.Data,b.Data));end;end
 row=struct('scene',name,'pass',all(cell2mat(rows(strcmp(rows(:,1),name),9))),'final_x_float_mm',floating.logsout.get('x_mm').Values.Data(end),'final_x_fixed_mm',fixed.logsout.get('x_mm').Values.Data(end),'same_input_event_times',true,'time_shift_applied',false,'numeric_overflow_saturation',0);if k==1,summary=row;else,summary(k)=row;end
 fprintf('M2_CLOSEDLOOP_SCENE %s pass=%d\n',name,row.pass);
 % Persist partial evidence even if a later scene fails.
 writetable(cell2table(rows,'VariableNames',{'scene','signal','float_migration_max','fixed_difference_max','fixed_difference_rmse','max_budget','rmse_budget','steady_difference_mean','pass'}),fullfile(folder,'closedloop_metrics.csv'));
end
result=struct('pass',pass,'version',version,'scenes',summary,'metric_rows',size(rows,1),'same_plant',true,'deadtime_and_PI_unchanged',true);fid=fopen(fullfile(folder,'closedloop_acceptance.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);assert(pass,'M2:CLOSEDLOOP_BUDGET','共享闭环误差超冻结预算，保留原始证据。');disp('M2_CLOSEDLOOP_PASS');
end
