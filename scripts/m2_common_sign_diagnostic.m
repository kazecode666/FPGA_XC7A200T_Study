function result=m2_common_sign_diagnostic(stage)
% Counterfactual diagnosis only; normal models and the frozen gate are retained.
arguments
    stage (1,:) char {mustBeMember(stage,{'prepare','float','fixed','analyze'})}
end
root=fileparts(fileparts(mfilename('fullpath')));
runtime=fullfile(root,'.runtime/pr51_common_sign_20261024');
folder=fullfile(root,'docs/reports/m2_foc_fixed_point/common_sign_diagnostic');
if ~isfolder(folder),mkdir(folder);end
tapeFile=fullfile(runtime,'recorded_float_signs.mat');
if strcmp(stage,'prepare')
    assert(~isfile(tapeFile),'M2:EVIDENCE_EXISTS','Keep the original sign tape.');
    a=load(fullfile(root,'.runtime/pr51_review_20261024/discovery_float.mat'),'out');
    v=a.out.logsout.get('review_sign_a').Values;
    tape=struct('time_s',v.Time,'values',zeros(numel(v.Time),3,'int8'), ...
        'source','actual original Float sign outputs, full0..4s', ...
        'phase_order',{{'a','b','c'}},'native_sample_s',1e-6);
    assert(isequal(round(tape.time_s/1e-6),(0:4000000)'));
    for k=1:3
        phase={'a','b','c'};v=a.out.logsout.get(['review_sign_' phase{k}]).Values;
        assert(isequal(v.Time,tape.time_s)&&all(ismember(v.Data,[-1 0 1])));
        tape.values(:,k)=int8(v.Data);
    end
    save(tapeFile,'tape','-v7.3');
    result=struct('diagnostic_only',true,'recorded_source','original Float', ...
        'samples_per_phase',4000001,'start_s',0,'stop_s',4,'sample_s',1e-6, ...
        'command_plan','unchanged paired_command_plan.json', ...
        'Float_self_replay_required_exact',true,'same_accepted_trajectory_required',true, ...
        'diagnostic_large_convergence_fraction',.9, ...
        'convergence_criterion_is_not_new_production_budget',true, ...
        'original_strict_gate_retained',true,'new_acceptance_exception_automatic',false);
    writejson(fullfile(folder,'diagnostic_plan.json'),result);return
end
if strcmp(stage,'analyze'),result=analyze(root,runtime,folder);return;end
target=fullfile(runtime,['common_' stage '.mat']);
assert(~isfile(target),'M2:EVIDENCE_EXISTS','Preserve the first diagnostic result.');
if strcmp(stage,'fixed')
    proof=jsondecode(fileread(fullfile(folder,'float_self_replay.json')));
    assert(proof.pass,'M2:INVALID_COUNTERFACTUAL','Float self-replay must be exact first.');
end
template=jsondecode(fileread(fullfile(runtime,'template.json')));
plan=jsondecode(fileread(fullfile(root,'docs/reports/m2_foc_fixed_point/paired_command_plan.json')));
observation=struct('model_source_folder',template.folder,'common_sign_tape',tapeFile);
implementation=double(strcmp(stage,'fixed'));
[out,metadata]=m2_run_shared_case('repeat',implementation,plan,[],observation);
save(target,'out','metadata','plan','-v7.3');
a=load(tapeFile,'tape');mismatch=zeros(1,3);
for k=1:3
    phase={'a','b','c'};v=out.logsout.get(['used_recorded_sign_' phase{k}]).Values;
    assert(isequal(round(v.Time/1e-6),round(a.tape.time_s/1e-6))&&max(abs(v.Time-a.tape.time_s))<1e-12);
    mismatch(k)=sum(double(v.Data(:))~=double(a.tape.values(:,k)));
end
assert(all(mismatch==0),'M2:REPLAY_TIMING','Consumed signs differ from the tape.');
result=struct('pass',true,'used_sign_mismatches',mismatch,'samples_per_phase',4000001, ...
    'same_native_ticks',true,'source','same recorded Float tape for both implementations', ...
    'diagnostic_only',true,'metadata',metadata);
if strcmp(stage,'float')
    old=load(fullfile(root,'.runtime/pr51_review_20261024/discovery_float.mat'),'out');
    residual=0;
    for name={'id','iq','x_mm','v_mmps','duty_u','duty_v','duty_w','vd','vq','x_d','x_q','du_d_z','du_q_z'}
        residual=max(residual,difference(out,old.out,name{1}));
    end
    result.original_Float_reproduction_max=residual;result.pass=residual==0;
    writejson(fullfile(folder,'float_self_replay.json'),result);
    assert(result.pass,'M2:SELF_REPLAY_CHANGED','Float self-replay changed original output: %.17g',residual);
else
    writejson(fullfile(folder,'fixed_replay.json'),result);
end
disp(result);
end
function result=analyze(root,runtime,folder)
f=load_control(fullfile(runtime,'common_float.mat'));q=load_control(fullfile(runtime,'common_fixed.mat'));
a=load_control(fullfile(root,'.runtime/pr51_review_20261024/discovery_float.mat'));
b=load_control(fullfile(root,'.runtime/pr51_review_20261024/discovery_fixed.mat'));
events=cell(0,4);same=true;
for n={'target_accepted_mm','segment_start_s','accepted_count','rejected_count','command_status','move_ready'}
    original=difference(a.out,b.out,n{1});common=difference(f.out,q.out,n{1});
    againstOriginal=difference(f.out,a.out,n{1});
    events(end+1,:)={n{1},original,common,againstOriginal}; %#ok<AGROW>
    if ~strcmp(n{1},'move_ready'),same=same&&common==0&&againstOriginal==0;end
end
writetable(cell2table(events,'VariableNames',{'signal','original_pair_max','common_pair_max','Float_self_vs_original_max'}),fullfile(folder,'command_and_ready.csv'));
rows=cell(0,11);large=true;gate=true;
for n={'id','iq','x_mm','v_mmps'}
    x=a.out.logsout.get(n{1}).Values;y=b.out.logsout.get(n{1}).Values;
    u=f.out.logsout.get(n{1}).Values;v=q.out.logsout.get(n{1}).Values;
    assert(isequal(x.Time,y.Time)&&isequal(x.Time,u.Time)&&isequal(u.Time,v.Time));
    d=double(y.Data(:))-double(x.Data(:));e=double(v.Data(:))-double(u.Data(:));
    oldMax=max(abs(d));oldRms=sqrt(mean(d.^2));newMax=max(abs(e));newRms=sqrt(mean(e.^2));
    reductionMax=1-newMax/oldMax;reductionRms=1-newRms/oldRms;
    lim=.005;rmsLim=.001;if strcmp(n{1},'v_mmps'),lim=.1;rmsLim=.02;end
    ok=newMax<=lim&&newRms<=rmsLim;gate=gate&&ok;
    if any(strcmp(n{1},{'iq','v_mmps'})),large=large&&reductionMax>=.9&&reductionRms>=.9;end
    rows(end+1,:)={n{1},oldMax,oldRms,newMax,newRms,reductionMax,reductionRms,lim,rmsLim,ok,same}; %#ok<AGROW>
end
writetable(cell2table(rows,'VariableNames',{'signal','original_max_abs','original_rmse','common_sign_max_abs','common_sign_rmse','max_reduction_fraction','rmse_reduction_fraction','unchanged_max_budget','unchanged_rmse_budget','diagnostic_pair_within_budget','same_accepted_trajectory'}),fullfile(folder,'convergence_metrics.csv'));
result=struct('diagnostic_completed',true,'same_accepted_trajectory',same, ...
    'predeclared_90_percent_convergence_met',large,'diagnostic_pair_within_original_budgets',gate, ...
    'original_production_case_strict_pass',false,'production_model_changed',false, ...
    'inference','shared signs remove the endogenous sign-threshold difference; counterfactual, not production validation');
writejson(fullfile(folder,'diagnostic_conclusion.json'),result);
m2_common_sign_motion_evidence(a.out,b.out,folder);
fig=figure('Visible','off','Position',[50 50 1300 800]);finish=onCleanup(@()close(fig)); %#ok<NASGU>
for k=1:2
    names={'iq','v_mmps'};n=names{k};
    x=a.out.logsout.get(n).Values;y=b.out.logsout.get(n).Values;
    u=f.out.logsout.get(n).Values;v=q.out.logsout.get(n).Values;
    subplot(2,1,k);plot(x.Time,double(y.Data)-double(x.Data),'DisplayName','original closed loop');hold on
    plot(u.Time,double(v.Data)-double(u.Data),'DisplayName','same recorded signs, diagnostic');
    xlabel('Time (s), no shift');ylabel(['Fixed minus Float: ' n],'Interpreter','none');grid on;legend('Location','best');
end
exportgraphics(fig,fullfile(folder,'original_vs_common_sign.png'),'Resolution',150);
disp(result);
end
function result=load_control(file)
result=load(file,'out');logs=result.out.logsout;names=getElementNames(logs);
for j=numel(names):-1:1
    if startsWith(names{j},'used_recorded_sign_')||startsWith(names{j},'review_sign_')
        logs=logs.removeElement(j);
    end
end
result.out.logsout=logs;
end
function value=difference(a,b,name)
x=a.logsout.get(name).Values;y=b.logsout.get(name).Values;
assert(isequal(x.Time,y.Time));value=max(abs(double(x.Data(:))-double(y.Data(:))));
end
function writejson(file,value)
fid=fopen(file,'w');fprintf(fid,'%s\n',jsonencode(value,PrettyPrint=true));fclose(fid);
end
