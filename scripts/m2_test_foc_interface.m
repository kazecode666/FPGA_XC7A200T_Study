function result=m2_test_foc_interface(afterSourceCreated)
% Optional test hook injects an exception after acquiring the owned reference.
if nargin==0,afterSourceCreated=[];end
root=fileparts(fileparts(mfilename('fullpath')));runtime=fullfile(root,'.runtime/m2_20261024');folder=fullfile(root,'docs/reports/m2_foc_fixed_point');files=dir(fullfile(runtime,'source_*.mat'));assert(numel(files)==11,'M2:SOURCE_EVIDENCE_MISSING','需要本次修改前11类原始参考；不可无参考宣称迁移通过。');[modelFolder,modelCleanup]=m2_test_model_files;m='PMLSM_FOC_FixedPoint';evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');bdir=fullfile(runtime,'B_float');if ~isfolder(bdir),mkdir(bdir);end;if ~isfile(fullfile(bdir,[m '.slx'])),m2_build_foc_model(bdir,modelFolder);end;if bdIsLoaded(m),close_system(m,0);end;load_system(fullfile(bdir,[m '.slx']));rows=cell(0,5);
ref=m2_make_source_reference(modelFolder);sourceCleanup=onCleanup(@()close_source(ref)); %#ok<NASGU>
if ~isempty(afterSourceCreated),afterSourceCreated(ref);end
for k=1:numel(files)
 a=load(fullfile(files(k).folder,files(k).name),'out','metadata');u=zeros(numel(a.out.logsout.get('in_ia').Values.Time),9);names={'ia','ib','ic','theta_e','omega_e','iq_ref','id_ref','PI_Reset_EN'};for j=1:8,v=a.out.logsout.get(['in_' names{j}]).Values;u(:,j)=double(v.Data);end;u(:,9)=48;
 out=m2_run_foc_sequence(m,u,false);for name={'duty_u','duty_v','duty_w','vd','vq','x_d','x_q','du_d_z','du_q_z'},x=out.logsout.get(name{1}).Values;y=a.out.logsout.get(name{1}).Values;assert(isequal(x.Time,y.Time));delta=double(x.Data(:))-double(y.Data(:));threshold=1e-10;if startsWith(name{1},'duty'),threshold=1e-12;end;err=max(abs(delta));rows(end+1,:)={a.metadata.scene,name{1},err,threshold,err<=threshold};assert(err<=threshold,'M2:EXTRACTION','%s %s mismatch %.17g',a.metadata.scene,name{1},err);end %#ok<AGROW>
 n=getElementNames(out.logsout);for j=1:numel(n),v=out.logsout.get(n{j}).Values;assert(all(isfinite(v.Data(:))),'M2:UNDEFINED_BRANCH','%s',n{j});end;fprintf('M2_INTERFACE_SCENE_PASS %s\n',a.metadata.scene);
end
u=m2_foc_vectors;reference=m2_run_foc_sequence(ref,u,false);adapted=m2_run_foc_sequence(m,u,false);
for name={'duty_u','duty_v','duty_w','vd','vq','x_d','x_q','du_d_z','du_q_z'},x=reference.logsout.get(name{1}).Values;y=adapted.logsout.get(name{1}).Values;assert(isequal(x.Time,y.Time));err=max(abs(double(x.Data(:))-double(y.Data(:))));limit=1e-10;if startsWith(name{1},'duty'),limit=1e-12;end;assert(err<=limit);rows(end+1,:)={'algorithm_boundary_sequence',name{1},err,limit,true};end
n=getElementNames(adapted.logsout);for j=1:numel(n),v=adapted.logsout.get(n{j}).Values;assert(all(isfinite(v.Data(:))));end
save(fullfile(runtime,'B_boundary_sequence.mat'),'u','reference','adapted','-v7.3');
writetable(cell2table(rows,'VariableNames',{'scene','signal','max_abs','threshold','pass'}),fullfile(folder,'interface_metrics.csv'));
checks=checkhdl([m '/FOC_DUT']);assert(~any(contains(string({checks.MessageID}),'DutInsideTrigger')));result=struct('pass',true,'rows',size(rows,1),'trigger_parent_error_removed',true,'double_checks',checks,'version',version);fid=fopen(fullfile(folder,'interface_acceptance.json'),'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);close_system(m,0);disp('M2_INTERFACE_PASS');
end
function close_source(ref)
if bdIsLoaded(ref),close_system(ref,0);end
end
