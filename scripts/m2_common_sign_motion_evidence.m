function m2_common_sign_motion_evidence(floating,fixed,folder)
% Supplemental ORIGINAL-production metrics; no thresholds are redefined here.
root=fileparts(fileparts(mfilename('fullpath')));
source=fullfile(root,'docs/reports/m2_foc_fixed_point/pr51_revision');
tracking=readtable(fullfile(source,'tracking_metrics.csv'),'TextType','string');
holding=readtable(fullfile(source,'holding_metrics.csv'),'TextType','string');
rows=cell(0,6);
for quantity=unique(tracking.tracking_quantity)'
    a=tracking(tracking.implementation=="float"&tracking.window=="whole_case"&tracking.tracking_quantity==quantity,:);
    b=tracking(tracking.implementation=="fixed"&tracking.window=="whole_case"&tracking.tracking_quantity==quantity,:);
    for field={'max_tracking_error','tracking_rmse','mean_tracking_error','actual_peak_to_peak'}
        x=a.(field{1});y=b.(field{1});
        rows(end+1,:)={'whole_case',char(quantity),field{1},x,y,abs(y-x)}; %#ok<AGROW>
    end
end
for target=unique(holding.accepted_target_mm)'
    a=holding(holding.implementation=="float"&holding.accepted_target_mm==target,:);
    b=holding(holding.implementation=="fixed"&holding.accepted_target_mm==target,:);
    assert(a.profile_done_start_s==b.profile_done_start_s&&a.before_next_target_s==b.before_next_target_s);
    for field={'max_target_error_mm','target_rmse_mm','mean_target_error_mm','position_peak_to_peak_mm','ready_fraction'}
        x=a.(field{1});y=b.(field{1});
        rows(end+1,:)={'profile_done_to_next_target',num2str(target,17),field{1},x,y,abs(y-x)}; %#ok<AGROW>
    end
end
writetable(cell2table(rows,'VariableNames',{'original_production_window','quantity_or_target','metric','Float','Fixed','absolute_metric_difference'}),fullfile(folder,'original_motion_metric_comparison.csv'));
rows=cell(0,8);
for k=1:2
    if k==1,out=floating;impl='Float';else,out=fixed;impl='Fixed';end
    count=out.logsout.get('accepted_count').Values;
    target=out.logsout.get('target_accepted_mm').Values;
    ready=out.logsout.get('move_ready').Values;
    done=out.logsout.get('trajectory_done').Values;
    pos=out.logsout.get('x_mm').Values;
    assert(isequal(round(count.Time/1e-4),round(pos.Time/1e-4))&&max(abs(count.Time-pos.Time))<1e-12);
    for number=1:4
        first=find(count.Data==number,1);last=find(count.Data==number,1,'last');
        at=find((1:numel(count.Time))'>=first&(1:numel(count.Time))'<=last&ready.Data==1&done.Data==1,1);
        assert(~isempty(at));error=abs(double(pos.Data(at))-double(target.Data(at)));
        rows(end+1,:)={impl,number,double(target.Data(first)),count.Time(first), ...
            count.Time(at),error,.02+1e-9,error<=.02+1e-9}; %#ok<AGROW>
    end
end
writetable(cell2table(rows,'VariableNames',{'original_implementation','accepted_move','target_mm','accepted_s','first_ready_after_profile_done_s','position_error_at_ready_mm','unchanged_ready_tolerance_mm','within_original_ready_window'}),fullfile(folder,'original_arrival_evidence.csv'));
end
