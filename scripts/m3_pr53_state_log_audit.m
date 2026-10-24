function m3_pr53_state_log_audit(folder,output)
% Inspect stored fi logs only; no models opened or saved.
s=load(fullfile(folder,'gm.mat'),'gmOut');names={'x_d_old','x_q_old','aw_d_old','aw_q_old'};rows=struct([]);
for k=1:numel(names)
 v=s.gmOut.logsout.get(names{k}).Values;t=v.Time(:);
 assert(isfi(v.Data),'M3:STATE_TYPE','Stored logs must retain original fi type.');
 rows(k).signal=names{k};rows(k).points=numel(t);rows(k).stored_type=tostring(numerictype(v.Data));
 rows(k).first_times_s=t(1:min(6,numel(t)))';
 if numel(t)>1,rows(k).observed_log_period_s=t(2)-t(1);end
end
fid=fopen(output,'w');fprintf(fid,'%s',jsonencode(rows,PrettyPrint=true));fclose(fid);
fprintf('M3_STATE_LOG_AUDIT_PASS %s\n',output);
end
