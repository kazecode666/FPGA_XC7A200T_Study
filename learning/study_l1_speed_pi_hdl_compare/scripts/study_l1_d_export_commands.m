function study_l1_d_export_commands(r,reportDir)
% Export actual saved full-rate command events; preserve the pending last ID.
ev=r.command_events; ac=ev.accepted_id(:); at=ev.accepted_time_s(:);
[matched,pair]=ismember(ac,ev.active_id(:)); vt=zeros(size(at));
vt(matched)=ev.active_time_s(pair(matched));
assert(all(abs(vt(matched)-at(matched)-50e-6)<=r.cfg.commTs+1e-12));
assert(all(diff(ac)==1) && all(abs(diff(at)-100e-6)<1e-12));
rows=[ac at vt double(matched) ev.accepted_references]; assert(all(isfinite(rows),'all'));
file=fullfile(reportDir,'foc_command_events.csv');
if isfile(file)
 existing=readmatrix(file); assert(isequal(size(existing),size(rows)) && max(abs(existing-rows),[],'all')<1e-12);
 fprintf('D_COMMAND_EXPORT_ALREADY_VERIFIED %s %s\n',r.cfg.name,r.cfg.implementation); return
end
writetable(array2table(rows,'VariableNames',{'command_id','accepted_time_s','active_time_s','active_within_horizon','id_ref_A','iq_ref_A'}),file);
fprintf('D_COMMAND_EXPORT_PASS %s %s accepted=%d active=%d\n',r.cfg.name,r.cfg.implementation,numel(ac),nnz(matched));
end
