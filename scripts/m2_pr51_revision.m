function result=m2_pr51_revision(stage)
% Limited PR51 review checkpoint. Never changes production models or budgets.
arguments
    stage (1,:) char {mustBeMember(stage,{'collect','windows','replay','cleanup','all'})}
end
root=fileparts(fileparts(mfilename('fullpath')));
runtime=fullfile(root,'.runtime/pr51_review_20261024');
folder=fullfile(root,'docs/reports/m2_foc_fixed_point/pr51_revision');
if ~isfolder(runtime),mkdir(runtime);end
if ~isfolder(folder),mkdir(folder);end
plan=jsondecode(fileread(fullfile(root,'docs/reports/m2_foc_fixed_point/paired_command_plan.json')));
if strcmp(stage,'all')
    result=struct;
    for item={'cleanup','collect','windows','replay'}
        result.(item{1})=m2_pr51_revision(item{1});
    end
    return
elseif strcmp(stage,'cleanup')
    result=m2_test_foc_interface_cleanup;return
elseif strcmp(stage,'collect')
    labels={'float','fixed'};
    for k=1:2
        target=fullfile(runtime,['discovery_' labels{k} '.mat']);
        if isfile(target),fprintf('PR51_KEEP_EXISTING %s\n',target);continue;end
        [out,metadata]=m2_run_shared_case('repeat',k-1,plan,[],struct('mode','discovery'));
        save(target,'out','metadata','plan','-v7.3');clear out
    end
    result=struct('collected',true,'production_changed',false);
elseif strcmp(stage,'windows')
    result=m2_pr51_analyze('discovery');
    labels={'float','fixed'};
    observation=struct('mode','detail','intervals',sortrows(result.intervals_s,1));
    for k=1:2
        target=fullfile(runtime,['detail_' labels{k} '.mat']);
        assert(~isfile(target),'M2:REVIEW_EVIDENCE_EXISTS','Preserve existing detail evidence.');
        [out,metadata]=m2_run_shared_case('repeat',k-1,plan,[],observation);
        save(target,'out','metadata','plan','observation','-v7.3');clear out
    end
    result=m2_pr51_analyze('windows');
else
    a=load(fullfile(runtime,'discovery_float.mat'),'out');
    names={'ia','ib','ic','theta_e','omega_e','iq_ref','id_ref','PI_Reset_EN','Vdc_V'};
    time=a.out.logsout.get('in_ia').Values.Time;
    u=zeros(numel(time),9);
    for k=1:9
        signal=a.out.logsout.get(['in_' names{k}]).Values;
        if numel(signal.Time)==1
            % A constant-folded bus still comes from its actual logged port.
            assert(k==9&&signal.Time==0);
            u(:,k)=double(signal.Data);
        else
            assert(same_ticks(time,signal.Time,1e-4));
            u(:,k)=double(signal.Data);
        end
    end
    assert(numel(time)==40001&&time(1)==0&&abs(time(end)-4)<1e-12);
    clear a
    tape=struct('names',{names},'time_s',time,'inputs',u, ...
        'source','actual Float FOC boundary, full prefix 0..4s', ...
        'sample_s',1e-4,'initial_PI_and_AW_states',zeros(1,4));
    tapeFile=fullfile(runtime,'float_nine_input_tape.mat');
    assert(~isfile(tapeFile),'M2:REVIEW_EVIDENCE_EXISTS','Keep the original tape.');
    save(tapeFile,'tape','-v7.3');
    [modelFolder,modelCleanup]=m2_test_model_files; %#ok<NASGU>
    evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');
    m2_bind_test_models(modelFolder);
    reference=m2_make_source_reference(modelFolder);
    sourceCleanup=onCleanup(@()close_source(reference)); %#ok<NASGU>
    ref=m2_run_foc_sequence(reference,u,false);
    cfg=evalin('base','FOC_Fixed_Config');
    decoded=u;keys={'Current','Current','Current','Angle','Omega','Current','Current','Reset','Bus'};
    for k=[1:7 9],decoded(:,k)=double(fi(u(:,k),cfg.Types.(keys{k}),cfg.Fimath));end
    refDecoded=m2_run_foc_sequence(reference,decoded,false);
    fixed=m2_run_foc_sequence('PMLSM_FOC_FixedPoint',u,true);
    target=fullfile(runtime,'same_input_replay.mat');
    assert(~isfile(target),'M2:REVIEW_EVIDENCE_EXISTS','Preserve the first replay.');
    save(target,'ref','refDecoded','fixed','tape','-v7.3');
    result=m2_pr51_analyze('replay');
end
end
function yes=same_ticks(a,b,dt)
yes=isequal(round(a/dt),round(b/dt))&&max(abs(a-b))<1e-12;
end
function close_source(model)
if bdIsLoaded(model),close_system(model,0);end
end
