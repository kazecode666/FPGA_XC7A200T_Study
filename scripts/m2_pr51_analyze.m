function result=m2_pr51_analyze(stage)
% Named small review evidence. No time shifts or interpolated comparisons.
root=fileparts(fileparts(mfilename('fullpath')));
runtime=fullfile(root,'.runtime/pr51_review_20261024');
folder=fullfile(root,'docs/reports/m2_foc_fixed_point/pr51_revision');
if ~isfolder(folder),mkdir(folder);end
a=load(fullfile(runtime,'discovery_float.mat'),'out','metadata');
b=load(fullfile(runtime,'discovery_fixed.mat'),'out','metadata');
if strcmp(stage,'discovery')
    % This also ensures the latest local layout/log changes did not alter the case.
    previous=load(fullfile(root,'.runtime/m2_20261024/paired_moves.mat'),'a','b');
    migration=0;
    for n={'id','iq','x_mm','v_mmps','duty_u','duty_v','duty_w','vd','vq','x_d','x_q','du_d_z','du_q_z'}
        migration=max([migration difference(a.out,previous.a,n{1}) difference(b.out,previous.b,n{1})]);
    end
    assert(migration==0,'M2:LOCAL_MODEL_DRIFT','Local case differs from original failure; preserve both.');
    clear previous
    rows=cell(0,5);first=Inf;
    for name={'review_sign_a','review_sign_b','review_sign_c','review_sector','review_sat_delayed','in_PI_Reset_EN'}
        x=a.out.logsout.get(name{1}).Values;y=b.out.logsout.get(name{1}).Values;
        assert(isequal(x.Time,y.Time));indices=find(double(x.Data(:))~=double(y.Data(:)));
        t=NaN;if ~isempty(indices),t=x.Time(indices(1));first=min(first,t);end
        dt=median(diff(x.Time));rows(end+1,:)={name{1},t,numel(indices),dt,numel(x.Time)}; %#ok<AGROW>
    end
    writetable(cell2table(rows,'VariableNames',{'actual_branch_signal','first_different_s','different_samples','native_sample_s','samples'}),fullfile(folder,'branch_divergence.csv'));
    assert(isfinite(first));centers=first;labels={'first_branch'};peaks=cell(0,5);
    for name={'iq','v_mmps'}
        x=a.out.logsout.get(name{1}).Values;y=b.out.logsout.get(name{1}).Values;
        assert(isequal(x.Time,y.Time));delta=double(y.Data(:))-double(x.Data(:));
        [maximum,k]=max(abs(delta));rmse=sqrt(mean(delta.^2));
        centers(end+1)=x.Time(k);labels{end+1}=['peak_' name{1}]; %#ok<AGROW>
        peaks(end+1,:)={name{1},x.Time(k),maximum,rmse,delta(k)}; %#ok<AGROW>
    end
    writetable(cell2table(peaks,'VariableNames',{'signal','peak_s','max_abs','rmse','signed_difference'}),fullfile(folder,'failure_peaks.csv'));
    arithmetic=cell(0,4);
    for name={'duty_u','duty_v','duty_w','vd','vq','review_park_d','review_park_q', ...
            'x_d','x_q','in_id_ref','in_iq_ref','id','iq','v_mmps'}
        x=a.out.logsout.get(name{1}).Values;y=b.out.logsout.get(name{1}).Values;
        assert(isequal(x.Time,y.Time));delta=double(y.Data(:))-double(x.Data(:));
        at=find(delta~=0,1);t=NaN;initial=0;
        if ~isempty(at),t=x.Time(at);initial=delta(at);end
        arithmetic(end+1,:)={name{1},t,initial,max(abs(delta))}; %#ok<AGROW>
    end
    writetable(cell2table(arithmetic,'VariableNames',{'signal','first_nonzero_difference_s','first_signed_difference','full_max_abs_difference'}),fullfile(folder,'arithmetic_divergence.csv'));
    for name={'target_accepted_mm','segment_start_s','accepted_count','rejected_count','command_status','move_ready'}
        assert(difference(a.out,b.out,name{1})==0,'M2:COMMAND_TRAJECTORY_CHANGED','%s',name{1});
    end
    intervals=[max(0,centers(:)-.001) min(4,centers(:)+.001)];
    result=struct('first_branch_s',first,'centers_s',centers,'window_labels',{labels}, ...
        'intervals_s',intervals,'window_halfwidth_s',.001,'original_failure_reproduced_max',migration, ...
        'same_command_and_ready_samples',true,'candidate_count_this_checkpoint',0, ...
        'acceptance_pass',false,'curves_shifted',false,'budget_relaxed',false);
    writejson(fullfile(folder,'localization.json'),result);
    tracking_metrics(a.out,b.out,[[0 4];intervals], ...
        [{'whole_case'} labels],folder);
    disp(result);
elseif strcmp(stage,'windows')
    location=jsondecode(fileread(fullfile(folder,'localization.json')));
    da=load(fullfile(runtime,'detail_float.mat'),'out');db=load(fullfile(runtime,'detail_fixed.mat'),'out');
    loggingResidual=max(window_parity(da.out,a.out),window_parity(db.out,b.out));
    assert(loggingResidual==0,'M2:OBSERVATION_DRIFT','Window logging altered actual values.');
    control={'in_ia','in_ib','in_ic','in_theta_e','in_omega_e','in_iq_ref','in_id_ref','in_PI_Reset_EN','in_Vdc_V', ...
        'review_park_d','review_park_q','review_vd_raw','review_vq_raw','vd','vq','x_d','x_q','du_d_z','du_q_z', ...
        'duty_u','duty_v','duty_w','review_sector','review_sat_delayed', ...
        'id','iq','x_mm','v_mmps','review_x_ref_mm','target_accepted_mm','move_ready'};
    plant={'review_phase_i_a','review_phase_i_b','review_phase_i_c', ...
        'review_deadzone_a','review_deadzone_b','review_deadzone_c', ...
        'review_sign_a','review_sign_b','review_sign_c','review_delta_d_a','review_delta_d_b','review_delta_d_c', ...
        'review_d_eff_a','review_d_eff_b','review_d_eff_c','review_pole_V_a','review_pole_V_b','review_pole_V_c', ...
        'review_vd_applied','review_vq_applied'};
    applied={'review_duty_applied_a','review_duty_applied_b','review_duty_applied_c'};
    rates=cell(0,4);
    for j=1:numel(location.window_labels)
        span=location.intervals_s(j,:);label=location.window_labels{j};
        for k=1:2
            if k==1,out=da.out;impl='float';else,out=db.out;impl='fixed';end
            c=table_window(out,control,span,1e-4);p=table_window(out,plant,span,1e-6);
            w=table_window(out,applied,span,5e-5);
            writetable(c,fullfile(folder,[label '_' impl '_control_100us.csv']));
            writetable(p,fullfile(folder,[label '_' impl '_plant_1us.csv']));
            writetable(w,fullfile(folder,[label '_' impl '_applied_50us.csv']));
            % Native timestamps, plus explicitly held constant bus only.
            for n=[control plant applied]
                v=out.logsout.get(n{1}).Values;
                d=diff(v.Time);d=d(d<1e-3);
                dt=NaN;if ~isempty(d),dt=median(d);end
                rates(end+1,:)={impl,n{1},dt,numel(v.Time)}; %#ok<AGROW>
            end
        end
        plot_windows(da.out,db.out,span,label,folder);
    end
    writetable(unique(cell2table(rates,'VariableNames',{'implementation','logged_name','native_sample_s','logged_samples'}),'rows','stable'),fullfile(folder,'native_sample_rates.csv'));
    first_branch_point(da.out,db.out,location.first_branch_s,plant,folder);
    result=struct('windows',numel(location.window_labels),'actual_logged_states',true, ...
        'time_shift_s',0,'whole_simulation_start_s',0,'full_simulation_stop_s',4, ...
        'plant_sample_s',1e-6,'FOC_sample_s',1e-4,'PWM_update_sample_s',5e-5, ...
        'window_logging_vs_full_run_max',loggingResidual);
    writejson(fullfile(folder,'window_evidence.json'),result);
else
    r=load(fullfile(runtime,'same_input_replay.mat'));
    metrics=cell(0,8);originalResidual=0;pass=true;
    for name={'park_d','park_q','vd_raw','vq_raw','vd','vq','x_d','x_q','du_d_z','du_q_z','duty_u','duty_v','duty_w'}
        n=name{1};x=r.ref.logsout.get(n).Values;y=r.fixed.logsout.get(n).Values;z=r.refDecoded.logsout.get(n).Values;
        assert(isequal(x.Time,y.Time)&&isequal(y.Time,z.Time));
        delta=double(y.Data(:))-double(x.Data(:));inputDelta=double(z.Data(:))-double(x.Data(:));internal=double(y.Data(:))-double(z.Data(:));
        limit=Inf;rmsLimit=Inf;
        if startsWith(n,'duty'),limit=1e-4;rmsLimit=2e-5;elseif ismember(n,{'vd','vq'}),limit=.01;rmsLimit=.002;end
        maximum=max(abs(delta));rmse=sqrt(mean(delta.^2));ok=maximum<=limit&&rmse<=rmsLimit;pass=pass&&ok;
        metrics(end+1,:)={n,maximum,rmse,max(abs(inputDelta)),max(abs(internal)),limit,rmsLimit,ok}; %#ok<AGROW>
        shared=n;if startsWith(n,'park_')||endsWith(n,'_raw'),shared=['review_' n];end
        originalResidual=max(originalResidual,matched_difference(x,a.out.logsout.get(shared).Values,1e-4));
    end
    assert(originalResidual==0,'M2:REPLAY_SOURCE_MISMATCH','Replay did not reproduce actual original FOC.');
    writetable(cell2table(metrics,'VariableNames',{'signal','same_input_max_abs','same_input_rmse','input_quantization_max','internal_plus_coefficient_max','frozen_max_budget','frozen_rmse_budget','pass'}),fullfile(folder,'same_input_replay_metrics.csv'));
    result=struct('pass_for_frozen_DUT_output_budgets',pass,'samples',size(r.tape.inputs,1), ...
        'start_s',r.tape.time_s(1),'stop_s',r.tape.time_s(end),'zero_initial_PI_and_AW',true, ...
        'all_nine_inputs_actual_logged',true,'original_replay_vs_actual_Float_max',originalResidual, ...
        'closed_loop_acceptance_pass',false,'closed_loop_sign_causality_fully_proven',false);
    writejson(fullfile(folder,'same_input_replay.json'),result);
    fig=figure('Visible','off','Position',[40 40 1300 850]);
    finish=onCleanup(@()close(fig)); %#ok<NASGU>
    groups={{'park_d','park_q'},{'vd_raw','vq_raw'},{'vd','vq'},{'duty_u','duty_v','duty_w'}};
    for j=1:4
        subplot(2,2,j);hold on
        for item=groups{j}
            x=r.ref.logsout.get(item{1}).Values;y=r.fixed.logsout.get(item{1}).Values;
            plot(x.Time,double(y.Data(:))-double(x.Data(:)),'DisplayName',item{1});
        end
        grid on;xlabel('Time (s), same input and zero initial states');
        ylabel('Fixed minus original');legend('Interpreter','none','Location','best');
    end
    exportgraphics(fig,fullfile(folder,'same_input_full_prefix.png'),'Resolution',140);
    assert(pass,'M2:REPLAY_BUDGET','Same-input FOC exceeds frozen DUT output budgets.');
    disp(result);
end
end
function tracking_metrics(a,b,spans,labels,folder)
rows=cell(0,10);
for k=1:2
    if k==1,out=a;impl='float';else,out=b;impl='fixed';end
    pairs={'review_park_d','in_id_ref','controller_id_A'; ...
        'review_park_q','in_iq_ref','controller_iq_A'; ...
        'x_mm','review_x_ref_mm','position_reference_mm'};
    for j=1:size(spans,1)
        for p=1:size(pairs,1)
            x=out.logsout.get(pairs{p,1}).Values;r=out.logsout.get(pairs{p,2}).Values;
            assert(isequal(round(x.Time/1e-4),round(r.Time/1e-4))&&max(abs(x.Time-r.Time))<1e-12);
            use=x.Time>=spans(j,1)-1e-12&x.Time<=spans(j,2)+1e-12;
            y=double(x.Data(use));e=y-double(r.Data(use));
            rows(end+1,:)={impl,labels{j},pairs{p,3},spans(j,1),spans(j,2), ...
                max(abs(e)),sqrt(mean(e.^2)),mean(e),max(y)-min(y),numel(e)}; %#ok<AGROW>
        end
    end
end
writetable(cell2table(rows,'VariableNames',{'implementation','window','tracking_quantity','start_s','end_s','max_tracking_error','tracking_rmse','mean_tracking_error','actual_peak_to_peak','samples'}),fullfile(folder,'tracking_metrics.csv'));
% Holding starts at actual profile completion, ends before next accepted move.
rows=cell(0,10);
for k=1:2
    if k==1,out=a;impl='float';else,out=b;impl='fixed';end
    target=out.logsout.get('target_accepted_mm').Values;
    done=out.logsout.get('trajectory_done').Values;
    ready=out.logsout.get('move_ready').Values;
    pos=out.logsout.get('x_mm').Values;
    assert(isequal(round(target.Time/1e-4),round(pos.Time/1e-4)));
    change=[1;find(diff(target.Data)~=0)+1];
    for j=1:numel(change)
        last=numel(target.Time);if j<numel(change),last=change(j+1)-1;end
        indices=(change(j):last)';indices=indices(done.Data(indices)~=0);
        if isempty(indices),continue;end
        e=double(pos.Data(indices))-double(target.Data(indices));
        rows(end+1,:)={impl,double(target.Data(change(j))),target.Time(indices(1)),target.Time(indices(end)), ...
            max(abs(e)),sqrt(mean(e.^2)),mean(e),max(e)-min(e), ...
            mean(double(ready.Data(indices))),numel(e)}; %#ok<AGROW>
    end
end
writetable(cell2table(rows,'VariableNames',{'implementation','accepted_target_mm','profile_done_start_s','before_next_target_s','max_target_error_mm','target_rmse_mm','mean_target_error_mm','position_peak_to_peak_mm','ready_fraction','samples'}),fullfile(folder,'holding_metrics.csv'));
end
function value=difference(a,b,name)
x=a.logsout.get(name).Values;y=b.logsout.get(name).Values;
value=matched_difference(x,y,1e-4);
end
function residual=window_parity(part,whole)
residual=0;names=intersect(getElementNames(part.logsout),getElementNames(whole.logsout));
for j=1:numel(names)
    if startsWith(names{j},'candidate_'),continue;end
    x=part.logsout.get(names{j}).Values;y=whole.logsout.get(names{j}).Values;
    [found,at]=ismember(round(x.Time/1e-6),round(y.Time/1e-6));
    assert(all(found)&&max(abs(x.Time-y.Time(at)))<1e-12);
    residual=max(residual,max(abs(double(x.Data(:))-double(y.Data(at)))));
end
end
function value=matched_difference(x,y,dt)
assert(isequal(round(x.Time/dt),round(y.Time/dt))&&max(abs(x.Time-y.Time))<1e-12);
value=max(abs(double(x.Data(:))-double(y.Data(:))));
end
function t=table_window(out,names,span,dt)
% Only exact native ticks enter CSVs; no interpolation of dynamic signals.
ticks=(ceil((span(1)-1e-12)/dt):floor((span(2)+1e-12)/dt))';
t=table(ticks*dt,'VariableNames',{'time_s'});
for n=names
    v=out.logsout.get(n{1}).Values;
    if numel(v.Time)==1&&strcmp(n{1},'in_Vdc_V')
        t.(n{1})=repmat(double(v.Data),numel(ticks),1);continue
    end
    [found,at]=ismember(ticks,round(v.Time/dt));
    assert(all(found),'M2:MISSING_WINDOW_TICK','%s missing native ticks at %.9g.',n{1},dt);
    assert(max(abs(v.Time(at)-t.time_s))<1e-12);
    t.(n{1})=double(v.Data(at));
end
end
function plot_windows(a,b,span,label,folder)
groups={{'review_phase_i_a','review_phase_i_b','review_phase_i_c'}, ...
    {'review_sign_a','review_sign_b','review_sign_c'}, ...
    {'review_delta_d_a','review_delta_d_b','review_delta_d_c'}, ...
    {'duty_u','review_duty_applied_a'}, ...
    {'review_vd_applied','review_vq_applied'}, ...
    {'x_d','x_q','du_d_z','du_q_z'}};
fig=figure('Visible','off','Position',[40 40 1400 1050]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
for k=1:6
    subplot(3,2,k);hold on
    for n=groups{k}
        for j=1:2
            if j==1,out=a;style='-';impl='Float';else,out=b;style='--';impl='Fixed';end
            v=out.logsout.get(n{1}).Values;keep=v.Time>=span(1)-1e-12&v.Time<=span(2)+1e-12;
            plot(v.Time(keep),double(v.Data(keep)),style,'DisplayName',[impl ' ' n{1}]);
        end
    end
    xlim(span);grid on;xlabel('Time (s), native sample times');legend('Interpreter','none','FontSize',7,'Location','best');
end
sgtitle(strrep(label,'_',' '));exportgraphics(fig,fullfile(folder,[label '.png']),'Resolution',140);
end
function first_branch_point(a,b,time,names,folder)
rows=cell(0,4);
for n=names
    x=point(a,n{1},time);y=point(b,n{1},time);
    rows(end+1,:)={n{1},x,y,y-x}; %#ok<AGROW>
end
writetable(cell2table(rows,'VariableNames',{'actual_logged_signal','float','fixed','fixed_minus_float'}),fullfile(folder,'first_branch_point.csv'));
% PWM updates are explicitly held, not interpolated or shifted.
ua=a.logsout.get('review_duty_applied_b').Values;
ub=b.logsout.get('review_duty_applied_b').Values;
ka=find(ua.Time<=time,1,'last');kb=find(ub.Time<=time,1,'last');
dutyDifference=double(ub.Data(kb))-double(ua.Data(ka));
correctionDifference=point(b,'review_delta_d_b',time)-point(a,'review_delta_d_b',time);
poleDifference=point(b,'review_pole_V_b',time)-point(a,'review_pole_V_b',time);
residual=poleDifference-48*(dutyDifference-correctionDifference);
assert(abs(residual)<1e-12);
result=struct('time_s',time,'phase','B','threshold_A',1e-4,'Vdc_V',48, ...
    'i_float_A',point(a,'review_phase_i_b',time),'i_fixed_A',point(b,'review_phase_i_b',time), ...
    'actual_sign_float',point(a,'review_sign_b',time),'actual_sign_fixed',point(b,'review_sign_b',time), ...
    'delta_d_float',point(a,'review_delta_d_b',time),'delta_d_fixed',point(b,'review_delta_d_b',time), ...
    'last_PWM_update_float_s',ua.Time(ka),'last_PWM_update_fixed_s',ub.Time(kb), ...
    'applied_duty_difference',dutyDifference,'pole_voltage_difference_V',poleDifference, ...
    'pole_equation_residual_V',residual, ...
    'scope','local unsaturated branch identity only; not full closed-loop attribution');
writejson(fullfile(folder,'first_branch_local_identity.json'),result);
fig=figure('Visible','off','Position',[40 40 1300 900]);
finish=onCleanup(@()close(fig)); %#ok<NASGU>
span=time+[-20e-6 20e-6];
names={'review_phase_i_b','review_sign_b','review_delta_d_b', ...
    'review_pole_V_b','review_vd_applied','review_vq_applied'};
units={'A','sign','duty correction','V','V','V'};
for j=1:6
    subplot(3,2,j);hold on
    for k=1:2
        if k==1,out=a;style='-o';impl='Float';else,out=b;style='--x';impl='Fixed';end
        v=out.logsout.get(names{j}).Values;keep=v.Time>=span(1)-1e-12&v.Time<=span(2)+1e-12;
        stairs((v.Time(keep)-time)*1e6,double(v.Data(keep)),style,'DisplayName',impl);
    end
    xline(0,':','first different sign','HandleVisibility','off');
    if j==1,yline(1e-4,':','threshold','HandleVisibility','off');end
    xlabel('Time from first sign divergence (us)');ylabel(units{j});
    title(names{j},'Interpreter','none');grid on;legend('Location','best');xlim([-20 20]);
end
exportgraphics(fig,fullfile(folder,'first_branch_zoom_1us.png'),'Resolution',150);
end
function value=point(out,name,time)
v=out.logsout.get(name).Values;at=find(round(v.Time/1e-6)==round(time/1e-6),1);
assert(~isempty(at)&&abs(v.Time(at)-time)<1e-12);value=double(v.Data(at));
end
function writejson(file,value)
fid=fopen(file,'w');fprintf(fid,'%s\n',jsonencode(value,PrettyPrint=true));fclose(fid);
end
