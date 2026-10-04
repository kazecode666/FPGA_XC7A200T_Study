function study_l1_b_plot(traceCsv,outPng,modelPath,outModelPng)
% Plot recorded XSim edges, not reconstructed controller waveforms.
t=readtable(traceCsv);
f=figure('Visible','off','Color','w','Position',[100 100 1160 660]);
c=onCleanup(@()close(f)); %#ok<NASGU>
layout=tiledlayout(f,2,2,'TileSpacing','compact','Padding','compact');
cases=[49 449]; titles={'First +2 mm/s speed tick','PI reset during positive saturation'};
for col=1:2
    s=t(t.row==cases(col),:); x=s.offset_ns;
    ax=nexttile(layout,col); hold(ax,'on');
    stairs(ax,x,s.clk+6,'LineWidth',1.4);
    stairs(ax,x,s.pi_reset+4,'LineWidth',1.4);
    stairs(ax,x,s.sample_tick+2,'LineWidth',1.4);
    stairs(ax,x,s.result_valid,'LineWidth',1.7);
    yticks(ax,[.5 2.5 4.5 6.5]); yticklabels(ax,{'result_valid','sample_tick','pi_reset','clk'});
    ylim(ax,[-.3 7.4]); xlim(ax,[0 120]); grid(ax,'on');
    xline(ax,20,':','input capture'); xline(ax,40,':','PI/valid');
    title(ax,titles{col}); xlabel(ax,'ns from source launch (samples: edge + 2 ns)');
    ax=nexttile(layout,col+2); hold(ax,'on');
    stairs(ax,x,s.iq_ref_raw/2^15,'LineWidth',1.6);
    stairs(ax,x,s.integrator_register_raw/2^30,'LineWidth',1.5);
    stairs(ax,x,s.excess_register_raw/2^30,'LineWidth',1.5);
    xline(ax,40,':'); xlim(ax,[0 120]); grid(ax,'on');
    xlabel(ax,'ns from source launch'); ylabel(ax,'A');
    legend(ax,{'iq reference','integrator register','previous excess register'},'Location','best');
end
title(layout,'Recorded 50 MHz RTL edges: two pipeline stages; sampled reset preserves excess');
exportgraphics(f,outPng,'Resolution',140);
if nargin>=4
    [~,model]=fileparts(modelPath); assert(~bdIsLoaded(model)); load_system(modelPath);
    cleanup=onCleanup(@()close_system(model,0)); %#ok<NASGU>
    print(['-s' model '/HDLCore'],'-dpng','-r120',outModelPng);
end
end
