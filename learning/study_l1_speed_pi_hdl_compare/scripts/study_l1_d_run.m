function study_l1_d_run(runtimeName,runname,names,implementations)
% Run each case independently from the same private original model copy.
s=fileparts(mfilename('fullpath')); study=fileparts(s); root=fileparts(fileparts(study));
addpath(s,fullfile(root,'scripts'),fullfile(root,'simulink模型'));
assert(strcmp(version('-release'),'2026b') && license('test','EDA_Simulator_Link'));
runtime=fullfile(study,'.runtime',runtimeName); run=fullfile(study,'.runtime',runname); assert(~isfolder(run)); mkdir(run);
hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');
if nargin<3, names={'speed_ideal','speed_deadtime','convergence_prefix'}; end
if nargin<4, implementations={'original','coder_baseline','hand_sv'}; end
for n=1:numel(names), for i=1:numel(implementations)
 cfg=step7d_scenarios(names{n}); impl=implementations{i}; report=fullfile(run,names{n},impl); mkdir(report);
 fprintf('D_CASE_START %s %s\n',names{n},impl);
 [m,cfg]=study_l1_d_configure(cfg,impl,runtime,fullfile(report,'model'));
 out=sim(m); global STUDY_D_EVENTS STUDY_D_EFFECTIVE STUDY_D_LISTENERS
 cfg.effective_config=STUDY_D_EFFECTIVE; events=STUDY_D_EVENTS;
 first=out.logsout.get('D_hdl_speed_first_edge_time_ns').Values;
 assert(all(double(first.Data(first.Time>=1e-6))==double(first.Data(end))));
 cfg.speed_clock_epoch_s=(double(first.Data(end))-20)*1e-9;
 fprintf('D_ACTUAL_FIRST_EDGE_NS %.0f epoch_s=%.17g\n',double(first.Data(end)),cfg.speed_clock_epoch_s);
 save(fullfile(report,'raw.mat'),'out','cfg','events','-v7.3');
 r=study_l1_d_extract(out,cfg,events,impl,report); r.metrics=study_l1_d_validate(r,report); save(fullfile(report,'result.mat'),'r','-v7.3');
 STUDY_D_LISTENERS=[]; close_system(m,0);
 study_l1_d_golden(report);
 fprintf('D_CASE_DONE %s %s\n',names{n},impl);
end; end
fprintf('D_SYSTEM_RUN_PASS\n');
end
