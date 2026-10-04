function study_l1_d_plot(reportDir)
% Portable scientific figures from published, unshifted 100 us trace CSVs.
% No models are loaded or simulated. Never replaces an existing figure.
study=fileparts(fileparts(mfilename('fullpath')));
if nargin<1, reportDir=fullfile(study,'reports','checkpoint_d','verification'); end
implementations={'original','coder_baseline','hand_sv'};
labels={'Original Simulink','HDL Coder baseline','Hand SV'};
colors=[.15 .15 .15;.08 .39 .72;.82 .35 .06];
styles={'-','-','--'};
for scenario={'speed_ideal','speed_deadtime','convergence_prefix'}
 name=scenario{1}; destination=fullfile(reportDir,[name '_comparison.png']);
 assert(~isfile(destination),'Use a new output path; existing figures are preserved.');
 data=cell(1,3);
 for k=1:3
  data{k}=readtable(fullfile(reportDir,name,implementations{k},'trace.csv'));
  assert(all(isfinite(data{k}{:,:}),'all'));
  assert(isequal(data{k}.time_s,data{1}.time_s));
 end
 assert(isequal(data{2}{:,:},data{3}{:,:}),'RTL traces must match without shifts.');
 f=figure('Visible','off','Color','w','Position',[80 80 1400 1350]);
 layout=tiledlayout(f,4,2,'TileSpacing','compact','Padding','compact');
 title(layout,[strrep(name,'_',' ') ' | same FOC / plant; unshifted 100 us grid']);
 subtitle(layout,'Hand SV 50 MHz WNS = -1.957 ns: setup FAIL; co-simulation does not establish board readiness.');
 nexttile; hold on;
 plot(data{1}.time_s,data{1}.v_ref_mmps,'Color',[.55 .55 .55],'LineWidth',1.8,'DisplayName','Shared v ref');
 series('v_mmps'); ylabel('mm/s'); title('Velocity'); legend('Location','best');
 nexttile; hold on; series('speed_pi_iq_ref_A'); ylabel('A'); title('Speed PI held iq ref'); legend('Location','best');
 nexttile; hold on; series('iq_A'); ylabel('A'); title('Plant iq'); legend('Location','best');
 nexttile; hold on;
 for k=1:3
  stairs(data{k}.time_s,data{k}.new_result,styles{k},'Color',colors(k,:),'LineWidth',1.3,'DisplayName',labels{k});
 end
 xlim([.0007 .0023]); ylim([-.1 1.1]); ylabel('count increment'); title('New result since previous sample (zoom)'); legend('Location','best');
 nexttile; hold on;
 plot(data{1}.time_s,data{1}.accepted_id,'Color',colors(1,:),'DisplayName','Accepted (all three)');
 plot(data{1}.time_s,data{1}.active_id,'--','Color',colors(2,:),'DisplayName','Active (all three)');
 ylabel('command ID'); title('FOC transaction IDs (identical)'); legend('Location','best');
 nexttile; hold on;
 plot(data{1}.time_s,data{1}.fault_code,'Color',colors(1,:),'DisplayName','fault code (all three)');
 plot(data{1}.time_s,data{1}.needs_reset,'--','Color',colors(2,:),'DisplayName','needs reset (all three)');
 ylim([-.1 1.1]); title('Fault / reset status (all zero)'); legend('Location','best');
 nexttile; hold on;
 plot(data{1}.time_s,data{1}.x_ref_mm,'Color',[.55 .55 .55],'LineWidth',1.8,'DisplayName','Shared position ref');
 series('x_mm'); ylabel('mm'); title('Position (prefix is sanity only)'); legend('Location','best');
 nexttile; hold on;
 plot(data{1}.time_s,data{1}.v_mmps-data{2}.v_mmps,'Color',colors(1,:),'DisplayName','Original - baseline');
 plot(data{1}.time_s,data{2}.v_mmps-data{3}.v_mmps,'--','Color',colors(3,:),'DisplayName','Baseline - Hand SV = 0');
 ylabel('mm/s'); title('Velocity differences at original times'); legend('Location','best');
 axesHandles=findall(f,'Type','axes');
 for ax=reshape(axesHandles,1,[]), grid(ax,'on'); xlabel(ax,'Time / s'); end
 exportgraphics(f,destination,'Resolution',160); close(f);
 fprintf('D_PORTABLE_FIGURE_PASS %s\n',name);
end
 function series(field)
  for index=1:3
   plot(data{index}.time_s,data{index}.(field),styles{index},'Color',colors(index,:),...
       'LineWidth',1.2,'DisplayName',labels{index});
  end
 end
end
