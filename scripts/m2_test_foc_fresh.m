function result=m2_test_foc_fresh
root=fileparts(fileparts(mfilename('fullpath')));assert(~evalin('base','exist(''PMLSM_M1A_InitVersion'',''var'')==1'),'M2:FRESH_REQUIRED','请在新的独立MATLAB进程运行。');folder=fullfile(root,'.runtime/m2_20261024',sprintf('fresh_%d',matlabProcessID));mkdir(folder);
assert(isempty(find_system('SearchDepth',0,'Type','block_diagram','BlockDiagramType','model')),'M2:FRESH_REQUIRED','独立验收不接管已打开的用户模型。');
files={'PMLSM_PI_FOC_Float_Baseline.slx','PMLSM_FOC_FixedPoint.slx','init_PMLSM_PI_FOC_Float_Baseline.m','m1a_require_float_init.m','pmlsm_foc_fixed_config.m','design_PMLSM_three_loop.m','pmlsm_scurve_profile.m','pmlsm_point_move_step.m'};
for k=1:numel(files),copyfile(fullfile(root,'simulink模型',files{k}),fullfile(folder,files{k}));end
oldPath=path;oldpwd=pwd;cleanup=onCleanup(@()restore(oldPath,oldpwd));parts=strsplit(path,pathsep);project=lower(strrep(root,'\','/'));for k=1:numel(parts),candidate=lower(strrep(parts{k},'\','/'));if strcmp(candidate,project)||startsWith(candidate,[project '/']),rmpath(parts{k});end;end
cd(folder);addpath(folder,'-begin');Simulink.fileGenControl('set','CacheFolder',fullfile(folder,'cache'),'CodeGenFolder',fullfile(folder,'codegen'),'createDir',true);assert(isempty(dir('*.mat')));m='PMLSM_PI_FOC_Float_Baseline';evalin('base','init_PMLSM_PI_FOC_Float_Baseline;Host_Target_mm=1;Host_Traj_Vmax=5;Host_Traj_Amax=50;M1A_StopTime_s=1.2;');load_system(m);rows=struct([]);
for i=0:1
 in=Simulink.SimulationInput(m).setVariable('FOC_Impl_Select',i);out=sim(in);names=getElementNames(out.logsout);assert(numel(names)==numel(unique(names)));required={'id','iq','x_mm','v_mmps','vd_cmd','vq_cmd','x_d','x_q','du_d_z','du_q_z','target_accepted_mm','move_ready','Init_Done'};assert(all(ismember(required,names)));p=out.logsout.get('x_mm').Values;assert(abs(p.Data(end)-1)<.02);row=struct('implementation',i,'named_logs',numel(names),'final_x_mm',p.Data(end),'stop_s',p.Time(end),'no_old_mat',true);if i==0,rows=row;else,rows(2)=row;end;fprintf('M2_FRESH_IMPLEMENTATION_PASS %d\n',i);
end
result=struct('pass',true,'version',version,'process',matlabProcessID,'files',{files},'implementations',rows,'repository_paths_excluded',true,'legacy_mat_required',false);fid=fopen(fullfile(root,'docs/reports/m2_foc_fixed_point/fresh_acceptance.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);disp('M2_FRESH_PASS');
end
function restore(oldPath,oldpwd)
for m={'PMLSM_PI_FOC_Float_Baseline','PMLSM_FOC_FixedPoint'},if bdIsLoaded(m{1}),close_system(m{1},0);end;end;cd(oldpwd);path(oldPath);
end
