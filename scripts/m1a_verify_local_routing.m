function result=m1a_verify_local_routing(referenceFile)
% 验证严格同层局部标签、可见轨迹绑定及默认数值保真。
root=fileparts(fileparts(mfilename('fullpath')));
if nargin==0,referenceFile=fullfile(root,'docs/reports/pr47_host_revision/default_run.mat');end
assert(isfile(referenceFile),'M1A:LOCAL_REFERENCE_REQUIRED','需提供修订前的默认仿真MAT（含out）；此本机开发对照不是模型Run依赖。');
m='PMLSM_PI_FOC_Float_Baseline';addpath(fullfile(root,'simulink模型'));
if ~bdIsLoaded(m),open_system(fullfile(root,'simulink模型',[m '.slx']));end
g=find_system(m,'LookUnderMasks','all','FollowLinks','off','BlockType','Goto');
for k=1:numel(g),assert(strcmp(get_param(g{k},'TagVisibility'),'local'),'M1A:GLOBAL_TAG','Goto必须局部作用域：%s',g{k});end
f=find_system(m,'LookUnderMasks','all','FollowLinks','off','BlockType','From');
for k=1:numel(f)
 same=find_system(get_param(f{k},'Parent'),'SearchDepth',1,'BlockType','Goto','GotoTag',get_param(f{k},'GotoTag'));
 assert(isscalar(same),'M1A:CROSS_LEVEL_TAG','From必须在同层有唯一局部Goto：%s',f{k});
end
assert(isempty(find_system(m,'LookUnderMasks','all','FollowLinks','off','BlockType','GotoTagVisibility')));
mon=[m '/Motor_Control_Monitor'];assert(numel(find_system(mon,'SearchDepth',1,'BlockType','Inport'))==11);
binding=get_param([m '/S_Curve_Reference_Actual'],'Binding');assert(numel(binding)==2);
assert(strcmp(char(binding{1}.BlockPath.getBlock(1)),[m '/Simple_Host'])&&binding{1}.OutputPortIndex==1);
assert(strcmp(char(binding{2}.BlockPath.getBlock(1)),[m '/PMLSM_Plant_Model'])&&binding{2}.OutputPortIndex==6);
evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');out=sim(m);
reference=load(referenceFile,'out');
maximum=0;
for name={'x_ref_mm','x_mm','v_mmps','id','iq','vd_cmd','vq_cmd','vd_applied','vq_applied','duty_u_cmd','duty_v_cmd','duty_w_cmd'}
 a=out.logsout.get(name{1}).Values;b=reference.out.logsout.get(name{1}).Values;
 assert(isequal(a.Time,b.Time));err=max(abs(double(a.Data(:))-double(b.Data(:))));maximum=max(maximum,err);assert(err==0,'M1A:OBSERVATION_CHANGED_MATH','相同输入的数值必须不变。');
end
result=struct('pass',true,'local_goto_count',numel(g),'same_level_from_count',numel(f),'monitor_explicit_inputs',11,'dashboard_actual_sources',{{'Simple_Host:1 x_ref_mm','PMLSM_Plant_Model:6 x_mm'}},'compared_signals',12,'max_abs_error',maximum,'stop_s',1.2);
folder=fullfile(root,'docs/reports/pr47_host_revision');fid=fopen(fullfile(folder,'local_curve_acceptance.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
fprintf('LOCAL_CURVE_PASS goto=%d from=%d max_error=%g\n',numel(g),numel(f),maximum);
end
