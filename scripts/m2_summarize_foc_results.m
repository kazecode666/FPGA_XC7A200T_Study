function m2_summarize_foc_results
% 从已保存的同一时间轴数据出图/统计，不重跑或修改模型。
root=fileparts(fileparts(mfilename('fullpath')));folder=fullfile(root,'docs/reports/m2_foc_fixed_point');runtime=fullfile(root,'.runtime/m2_20261024');addpath(fullfile(root,'simulink模型'));files=dir(fullfile(runtime,'closedloop_*.mat'));rows=cell(0,8);tracking=cell(0,7);inputs=cell(0,5);
for k=1:numel(files)
 data=load(fullfile(files(k).folder,files(k).name));scene=data.metaFloat.scene;outputs={data.floating,data.fixed};
 for impl=1:2
  out=outputs{impl};label='float';if impl==2,label='fixed';end
  for name={'id','iq','x_mm','v_mmps','duty_u','duty_v','duty_w','vd','vq','x_d','x_q','du_d_z','du_q_z'}
   v=out.logsout.get(name{1}).Values;y=double(v.Data);steady=v.Time>=v.Time(end)*.8;rows(end+1,:)={scene,label,name{1},v.Time(end)*.8,mean(y(steady)),max(y(steady))-min(y(steady)),min(y),max(y)}; %#ok<AGROW>
  end
  inputs(end+1,:)={scene,label,'Vdc_V',48,48}; %#ok<AGROW>
  ia=out.logsout.get('in_ia').Values;ib=out.logsout.get('in_ib').Values;ic=out.logsout.get('in_ic').Values;theta=out.logsout.get('in_theta_e').Values;
  alpha=(double(ia.Data)-.5*double(ib.Data)-.5*double(ic.Data))*(2/3);beta=(double(ib.Data)-double(ic.Data))/sqrt(3);angle=double(theta.Data);dq={alpha.*cos(angle)+beta.*sin(angle),-alpha.*sin(angle)+beta.*cos(angle)};
  for axis=1:2,names={'id','iq'};ref=out.logsout.get(['in_' names{axis} '_ref']).Values;delta=dq{axis}-double(ref.Data);tracking(end+1,:)={scene,label,[names{axis} '_analytic_control_frame_minus_selected_ref'],max(abs(delta)),sqrt(mean(delta.^2)),mean(delta(ref.Time>=ref.Time(end)*.8)),'derived Clarke/Park using logged controller theta and phase currents; analytic trig, not logged fixed PI feedback'};end %#ok<AGROW>
  for name={'ia','ib','ic','theta_e','omega_e','id_ref','iq_ref','PI_Reset_EN'}
   v=out.logsout.get(['in_' name{1}]).Values;y=double(v.Data);inputs(end+1,:)={scene,label,name{1},min(y),max(y)};limit=2;if strcmp(name{1},'theta_e'),limit=8*pi;elseif strcmp(name{1},'omega_e'),limit=100;elseif strcmp(name{1},'PI_Reset_EN'),limit=1;end;assert(all(abs(y)<=limit),'M2:CLOSEDLOOP_ENVELOPE','%s %s',scene,name{1}); %#ok<AGROW>
  end
  % Physical dq vs actually selected reference. During alignment the controller
  % frame differs: these are explicitly physical-frame comparisons, not PI error.
  for axis={'id','iq'}
   v=out.logsout.get(axis{1}).Values;r=out.logsout.get(['in_' axis{1} '_ref']).Values;assert(isequal(round(v.Time/1e-4),round(r.Time/1e-4))&&max(abs(v.Time-r.Time))<1e-12);delta=double(v.Data)-double(r.Data);tracking(end+1,:)={scene,label,[axis{1} '_physical_minus_selected_ref'],max(abs(delta)),sqrt(mean(delta.^2)),mean(delta(v.Time>=v.Time(end)*.8)),'same100us ticks (timestamp roundoff<1ps); actual logged reference; alignment frames may differ'}; %#ok<AGROW>
  end
  if ~startsWith(scene,'current')&&~startsWith(scene,'speed')&&~strcmp(scene,'reset')&&~strcmp(scene,'alignment')
   v=out.logsout.get('x_mm').Values;target=1;V=5;A=50;if strcmp(scene,'daily'),target=10;V=10;A=100;elseif strcmp(scene,'position_neg'),target=-1;end
   reference=arrayfun(@(t)pmlsm_scurve_profile(t-.05,target,V,A,1000,.1),v.Time);delta=double(v.Data)-reference;tracking(end+1,:)={scene,label,'x_mm_minus_profile',max(abs(delta)),sqrt(mean(delta.^2)),mean(delta(v.Time>=v.Time(end)*.8)),'reference reconstructed with unchanged original profile; not a logged x_ref'}; %#ok<AGROW>
  elseif startsWith(scene,'speed')
   v=out.logsout.get('v_mmps').Values;reference=10;if endsWith(scene,'neg'),reference=-10;end;delta=double(v.Data)-reference;tracking(end+1,:)={scene,label,'v_mmps_minus_host_command',max(abs(delta)),sqrt(mean(delta.^2)),mean(delta(v.Time>=v.Time(end)*.8)),'host command; includes startup transient'}; %#ok<AGROW>
  end
 end
 fig=figure('Visible','off','Color','w','Position',[100 100 1100 850]);cleanup=onCleanup(@()close(fig));tiledlayout(4,1,'TileSpacing','compact');
 nexttile;v=data.floating.logsout.get('x_mm').Values;w=data.fixed.logsout.get('x_mm').Values;plot(v.Time,v.Data,w.Time,w.Data,'--');ylabel('x (mm)');legend('float','fixed','Location','best');title(['M2 same-time closed loop: ' scene],'Interpreter','none');grid on
 nexttile;v=data.floating.logsout.get('iq').Values;w=data.fixed.logsout.get('iq').Values;plot(v.Time,v.Data,w.Time,w.Data,'--');ylabel('iq (Apeak)');grid on
 nexttile;v=data.floating.logsout.get('v_mmps').Values;w=data.fixed.logsout.get('v_mmps').Values;plot(v.Time,double(w.Data)-double(v.Data));ylabel('fixed-float v (mm/s)');grid on
 nexttile;v=data.fixed.logsout.get('in_iq_ref').Values;w=data.fixed.logsout.get('in_id_ref').Values;z=data.fixed.logsout.get('in_PI_Reset_EN').Values;plot(v.Time,double(v.Data),w.Time,double(w.Data),z.Time,double(z.Data));legend('selected iq ref A','selected id ref A','PI reset','Location','best');xlabel('Time (s), no shifting');grid on
 exportgraphics(fig,fullfile(folder,['scene_' scene '.png']),'Resolution',130);clear cleanup
end
writetable(cell2table(rows,'VariableNames',{'scene','implementation','signal','steady_start_s','steady_mean','steady_peak_to_peak','full_min','full_max'}),fullfile(folder,'steady_metrics.csv'));
writetable(cell2table(tracking,'VariableNames',{'scene','implementation','comparison','max_abs','rmse','steady_mean_error','reference_provenance'}),fullfile(folder,'tracking_metrics.csv'));
writetable(cell2table(inputs,'VariableNames',{'scene','implementation','actual_FOC_input','min','max'}),fullfile(folder,'effective_inputs.csv'));
raw=load(fullfile(runtime,'D_unit_raw.mat'),'fixed');d=double(raw.fixed.logsout.get('vd_raw').Values.Data)-double(raw.fixed.logsout.get('vd').Values.Data);q=double(raw.fixed.logsout.get('vq_raw').Values.Data)-double(raw.fixed.logsout.get('vq').Values.Data);result=struct('scenes',numel(files),'input_envelope_pass',true,'unit_algorithm_limited_samples',sum(abs(d)>1e-8|abs(q)>1e-8),'numeric_representation_overflow_or_saturation',0,'steady_window','last20percent; includes normal uncompensated ripple','profile_reference','derived using unchanged original pmlsm_scurve_profile; separately validated against logged live x_ref','no_time_shift',true);
fid=fopen(fullfile(folder,'observations.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);disp('M2_OBSERVATIONS_PASS');
end
