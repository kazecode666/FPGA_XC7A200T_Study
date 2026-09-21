function step7c_plot_results(ideal,dead,rd)
f=figure('Visible','off','Position',[100 100 1200 850]); c=onCleanup(@() close(f)); %#ok<NASGU>
t=ideal.time*1000; a=ideal.data; b=dead.data;
tiledlayout(3,2);
cols=[4 3 9 8 10 11]; labels={'q current (A)','d current (A)','Velocity (mm/s)','Position (mm)','Electrical angle (rad)','Electrical speed (rad/s)'};
for k=1:6
    nexttile; plot(t,a(:,cols(k)),t,b(:,cols(k))); hold on;
    if k==1, stairs(t,a(:,2),'k--'); legend('Ideal','1 us deadtime','Reference'); else, legend('Ideal','1 us deadtime'); end
    xlabel('Time (ms)'); ylabel(labels{k}); grid on;
end
sgtitle('Step 7C: FPGA current loop, free-moving PMLSM');
exportgraphics(f,fullfile(rd,'dynamic_comparison.png'),'Resolution',150);
end
