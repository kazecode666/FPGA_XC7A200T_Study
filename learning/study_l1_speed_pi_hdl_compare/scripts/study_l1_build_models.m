function study_l1_build_models(models)
% Create only new Study-L1 files. Existing learning models are never replaced.
study=fileparts(fileparts(mfilename('fullpath'))); root=fileparts(fileparts(study));
p=study_l1_init;
if nargin<1, models=fullfile(study,'models'); end
if ~isfolder(models), mkdir(models); end
names={'speed_pi_float','speed_pi_fixed','speed_pi_fixed_b2','speed_pi_compare_tb'};
for k=1:numel(names)
    assert(~isfile(fullfile(models,[names{k} '.slx'])),'StudyL1:ExistingFile','Refuse overwrite: %s',names{k});
end
study_l1_build_pi(names{1},"float",p);
save_system(names{1},fullfile(models,[names{1} '.slx']));
% Load original saved model only in this dedicated process; never save it.
source=fullfile(root,'simulink模型'); oldpwd=pwd; cd(source);
cleanup=onCleanup(@()cd(oldpwd)); %#ok<NASGU>
addpath(source); addpath(fullfile(root,'scripts'));
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m));
load_system(fullfile(source,[m '.slx']));
closeOriginal=onCleanup(@()close_system(m,0)); %#ok<NASGU>
mw=get_param(m,'ModelWorkspace');
for field=string(fieldnames(p))', assert(isequal(mw.evalin(char(field)),p.(field))); end
tb='speed_pi_compare_tb'; new_system(tb);
set_param(tb,'Solver','FixedStepDiscrete','FixedStep',num2str(p.Ts,17), ...
    'ReturnWorkspaceOutputs','on','SaveOutput','off','StopTime','0.01');
tmw=get_param(tb,'ModelWorkspace');
for field=string(fieldnames(p))', tmw.assignin(char(field),p.(field)); end
src=Simulink.ID.getFullName([m ':1122']); orig=[tb '/Original_PI'];
add_block(src,orig,'Position',[350 80 610 360]);
% Diagnostic taps add observation ports only; every original block is retained.
sids=[1133 1228 0 1165 1166 1162 1189 1189 1159 1163 1130 1129 1149];
labels={'unlimited','integrator','saturation','integrator_next','previous_excess', ...
    'excess_next','hard_reset','int_reset','limited','error','P','KiTs','AW'};
add_block('built-in/RelationalOperator',[orig '/Study_Saturation'], ...
    'Operator','~=','Position',[1280 20 1330 55]);
for k=1:numel(sids)
    dst=[orig '/Study_' labels{k}];
    add_block('built-in/Outport',dst,'Port',num2str(k+1),'Position',[1420 40+35*k 1450 54+35*k]);
    if sids(k)==0, block='Study_Saturation'; port=1;
    else
        path=Simulink.ID.getFullName(sprintf('%s:%d',m,sids(k)));
        block=path(numel(src)+2:end); port=1+(k==8);
    end
    add_line(orig,[block '/' num2str(port)],['Study_' labels{k} '/1']);
end
for pair={1133,1;1159,2}'
    path=Simulink.ID.getFullName(sprintf('%s:%d',m,pair{1}));
    add_line(orig,[path(numel(src)+2:end) '/1'],['Study_Saturation/' num2str(pair{2})]);
end
% Preserve the scheduler's inherited rate with the real function-call source.
task=[tb '/Original_Scheduler'];
add_block('built-in/SubSystem',task,'Position',[40 15 240 65]);
add_block('built-in/TriggerPort',[task '/Control_Tick'],'TriggerType','function-call','Position',[15 5 35 25]);
add_block(Simulink.ID.getFullName([m ':740']),[task '/Scheduler'],'Position',[40 40 240 100]);
for k=1:2
    add_block('built-in/Outport',[task '/tick_' num2str(k)],'Port',num2str(k),'Position',[290 40+35*k 320 54+35*k]);
    add_line(task,['Scheduler/' num2str(k)],['tick_' num2str(k) '/1']);
end
add_block(Simulink.ID.getFullName([m ':785']),[tb '/Original_Control_Call'],'Position',[10 5 35 25]);
add_line(tb,'Original_Control_Call/1','Original_Scheduler/Trigger');
add_block('built-in/Terminator',[tb '/UnusedPositionTick'],'Position',[270 35 290 55]);
add_line(tb,'Original_Scheduler/2','UnusedPositionTick/1');
add_block('built-in/ToWorkspace',[tb '/CaptureTick'],'VariableName','actual_tick', ...
    'SaveFormat','Timeseries','MaxDataPoints','inf','Position',[270 5 340 25]);
add_line(tb,'Original_Scheduler/1','CaptureTick/1');
% Own workspace streams, with no reference to user MAT files or base residue.
inputs={'v_ref','v_meas','enable','reset','tick','angle_init','test_mode'};
for k=1:numel(inputs)
    add_block('built-in/FromWorkspace',[tb '/' inputs{k}], ...
        'VariableName',['study_' inputs{k}],'SampleTime',num2str(p.Ts,17), ...
        'Interpolate','off','OutputAfterFinalValue','Holding final value', ...
        'Position',[35 100+65*k 150 130+65*k]);
end
add_line(tb,'v_ref/1','Original_PI/1'); add_line(tb,'v_meas/1','Original_PI/2');
add_line(tb,'angle_init/1','Original_PI/3'); add_line(tb,'tick/1','Original_PI/Trigger');
% Parent data stores keep the original reset manager intact.
for pair={'enable','Close_Loop_EN_cmd';'reset','PI_Reset_EN_cmd';'test_mode','Iq_Test_Mode_cmd'}'
    a=pair{1}; tag=pair{2};
    add_block('built-in/DataStoreMemory',[tb '/' tag],'DataStoreName',tag,'InitialValue','0','Position',[180 460+50*find(strcmp(inputs,a)) 280 490+50*find(strcmp(inputs,a))]);
    add_block('built-in/DataStoreWrite',[tb '/Write_' tag],'DataStoreName',tag,'Priority','-10','Position',[185 100+65*find(strcmp(inputs,a)) 285 130+65*find(strcmp(inputs,a))]);
    add_line(tb,[a '/1'],['Write_' tag '/1']);
end
add_block([names{1} '/PI'],[tb '/Float'],'Position',[680 360 940 640]);
for j=1:7
    if j==5, port='Trigger'; else, port=num2str(j-(j>5)); end
    add_line(tb,[inputs{j} '/1'],['Float/' port]);
end
subs={'Original_PI','Float'}; prefixes={'original','float'};
for k=1:numel(subs)
    for j=1:14
        sink=sprintf('Capture_%s_%02d',prefixes{k},j);
        add_block('built-in/ToWorkspace',[tb '/' sink], ...
            'VariableName',sprintf('%s_%02d',prefixes{k},j),'SaveFormat','Timeseries','FixptAsFi','on','MaxDataPoints','inf', ...
            'Position',[1050+220*k 30+48*j 1215+220*k 55+48*j]);
        add_line(tb,[subs{k} '/' num2str(j)],[sink '/1']);
    end
end
save_system(tb,fullfile(models,[tb '.slx']));
close_system(names{1},0); close_system(tb,0);
% Gates are enforced inside the reproducible build: observe A2 ranges first,
% prove B1 before creating B2. Only task-owned files are updated below.
stageReports=fullfile(models,'stage_verification');
study_l1_run_checkpoint_a(fullfile(stageReports,'A2'),models);
for k=2:3
    modes={'float','B1','B2'};
    study_l1_build_pi(names{k},string(modes{k}),p);
    save_system(names{k},fullfile(models,[names{k} '.slx']));
    load_system(fullfile(models,[tb '.slx']));
    sub=modes{k}; prefix=lower(sub);
    add_block([names{k} '/PI'],[tb '/' sub],'Position',[680 30+330*k 940 310+330*k]);
    for j=1:7
        if j==5, port='Trigger'; else, port=num2str(j-(j>5)); end
        add_line(tb,[inputs{j} '/1'],[sub '/' port]);
    end
    for j=1:14
        sink=sprintf('Capture_%s_%02d',prefix,j);
        add_block('built-in/ToWorkspace',[tb '/' sink], ...
            'VariableName',sprintf('%s_%02d',prefix,j),'SaveFormat','Timeseries', ...
            'FixptAsFi','on','MaxDataPoints','inf', ...
            'Position',[1050+220*k 30+48*j 1215+220*k 55+48*j]);
        add_line(tb,[sub '/' num2str(j)],[sink '/1']);
    end
    save_system(tb,fullfile(models,[tb '.slx']));
    close_system(tb,0); close_system(names{k},0);
    study_l1_run_checkpoint_a(fullfile(stageReports,sub),models);
end
disp('STUDY_L1_MODELS_CREATED_ORIGINAL_NOT_SAVED');
end
