function study_l1_export_models(reportDir)
% Export task-owned diagrams only; no user-model UI or state is touched.
study=fileparts(fileparts(mfilename('fullpath')));
for name=["speed_pi_float","speed_pi_fixed","speed_pi_fixed_b2"]
    load_system(fullfile(study,'models',[char(name) '.slx']));
    print(['-s' char(name) '/PI'],'-dpng','-r120',fullfile(reportDir,[char(name) '.png']));
    close_system(char(name),0);
end
end
