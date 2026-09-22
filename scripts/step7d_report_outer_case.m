function step7d_report_outer_case(reportDir,baselineFile,diagnosticOnly)
% Summarize real data; old legacy is a comparison, never a replacement run.
if nargin<3, diagnosticOnly=false; end
txt=fileread(fullfile(reportDir,'run_summary.txt')); p=regexp(txt,'RAW_DIR=([^\r\n]+)','tokens','once');
a=load(fullfile(p{1},'result.mat'),'r'); r=a.r; c=r.cfg;
failure='';
try, step7d_assert_result(r,c);
catch e
 if ~diagnosticOnly, rethrow(e); end
 failure=[e.identifier ': ' e.message];
end
b=load(baselineFile,'r'); legacy=b.r;
assert(strcmp(legacy.cfg.name,c.name) && legacy.cfg.backend==0 && legacy.cfg.commTs==c.commTs);
o=load(fullfile(p{1},'simulation_output.mat'),'out');
for n={'hard_reset','int_reset'}
 s=o.out.logsout.get(n{1}).Values;
 assert(all(s.Data==0),'Step7D:OuterUnexpectedReset','Normal scenario reset the speed PI.');
end
f=fopen(fullfile(reportDir,'outer_comparison.txt'),'w'); fc=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'RUN_ID=%s\nLEGACY_COMPARISON_FILE=%s\nNO_WAVEFORM_EQUIVALENCE_CLAIM=1\n',r.run_id,baselineFile);
fprintf(f,'DIAGNOSTIC_ONLY=%d\nORIGINAL_GATE_FAILURE=%s\n',diagnosticOnly,failure);
r.metrics=struct('speed',[]);
for k=1:size(c.windows.speed,1)
 w=c.windows.speed(k,:); et=legacy.events.speed; et=et(et>=w(1)-1e-12 & et<w(2)-1e-12);
 idx=round(et/1e-4)+1; e=legacy.signals.v_ref(idx)-legacy.signals.v(idx);
 te=r.control_events.speed; te=te(te>=w(1)-1e-12 & te<w(2)-1e-12); j=round(te/1e-4)+1;
 er=r.v_ref_mmps(j)-r.v_mmps(j);
 r.metrics.speed(k,:)=[numel(j),mean(abs(er)),sqrt(mean(er.^2)),max(abs(er)),mean(r.v_mmps(j)),max(r.v_ref_mmps(j))-min(r.v_ref_mmps(j))];
 fprintf(f,'SPEED_WINDOW=%s LEGACY_N_MAE_RMSE_MAX=%s FPGA_N_MAE_RMSE_MAX_MEANV_REFSPAN=%s\n',mat2str(w),mat2str([numel(e),mean(abs(e)),sqrt(mean(e.^2)),max(abs(e))],17),mat2str(r.metrics.speed(k,:),17));
end
ix=round(r.control_events.current(r.control_events.current>=.002)/1e-4)+1;
r.metrics.iq_rmse_A=sqrt(mean((r.iq_ref_A(ix)-r.iq_A(ix)).^2));
if startsWith(c.name,'speed')
 t=r.time_s; ix=t>=1 & t<1.04;
 assert(all(r.v_ref_mmps(ix)==0) && all(r.load_N(ix)==.5),'Step7D:ZeroLoadWindow','Wrong zero-speed/load window.');
 assert(abs(mean(r.iq_ref_A(ix)))>1e-6 && abs(mean(r.outer_integrator(ix)))>1e-6,'Step7D:ZeroLoadHold','No holding current/integral.');
 fprintf(f,'ZERO_SPEED_LOAD_WINDOW=[1,1.04) MEAN_IQ_REF_A=%.17g INTEGRATOR_MIN_MAX=%s HARD_RESET=0 INT_RESET=0\n',mean(r.iq_ref_A(ix)),mat2str([min(r.outer_integrator(ix)),max(r.outer_integrator(ix))],17));
end
fprintf(f,'FPGA_METRICS=%s\nFPGA_FULL_RATE_PEAKS=%s\nLEGACY_FULL_RATE_PEAKS=%s\n',jsonencode(r.metrics),jsonencode(r.peaks),jsonencode(legacy.peaks));
fig=figure('Visible','off','Position',[80 80 1250 850]); figc=onCleanup(@()close(fig)); %#ok<NASGU>
tiledlayout(4,1);
nexttile; plot(r.time_s,[r.v_request_mmps r.v_ref_mmps r.v_mmps]); ylabel('mm/s'); legend('Host request','managed reference','speed','Location','best'); grid on
nexttile; plot(r.time_s,[r.iq_ref_A r.iq_A r.id_A]); ylabel('A'); legend('iq reference','iq','id','Location','best'); grid on
nexttile; plot(r.time_s,[r.load_N r.outer_integrator r.outer_limit_flags]); legend('load (N)','integrator (A)','limited','Location','best'); grid on
nexttile; plot(r.time_s,[r.x_ref_mm r.x_mm]); ylabel('mm'); xlabel('s'); legend({'Host position','position'},'Location','best'); grid on
sgtitle(strrep([c.name ' : ' r.run_id],'_',' ')); exportgraphics(fig,fullfile(reportDir,'outer_response.png'),'Resolution',140);
if diagnosticOnly, verdict='STEP7D_DIAGNOSTIC_RECORDED_NOT_ACCEPTED'; else, verdict='STEP7D_OUTER_CASE_REPORT_PASS'; end
fprintf(f,'%s\n',verdict); disp(verdict);
end
