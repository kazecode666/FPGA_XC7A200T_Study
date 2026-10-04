function summary = study_l1_run_checkpoint_a(reportDir,models)
% Fresh component regression. No plant, HDL Coder, Vivado or hardware calls.
study=fileparts(fileparts(mfilename('fullpath')));
fileGenCfg=Simulink.fileGenControl('getConfig');
restoreGen=onCleanup(@()Simulink.fileGenControl('setConfig','config',fileGenCfg)); %#ok<NASGU>
Simulink.fileGenControl('set','CacheFolder',fullfile(study,'.runtime/cache'), ...
    'CodeGenFolder',fullfile(study,'.runtime/codegen'),'createDir',true);
if nargin<2, models=fullfile(study,'models'); end
if nargin<1
    reportDir=fullfile(study,'reports/checkpoint_a',['fresh_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
end
assert(~isfolder(reportDir),'StudyL1:ExistingReport','Use a fresh report directory.');
mkdir(reportDir); p=study_l1_init; v=study_l1_generate_vectors(p);
tb='speed_pi_compare_tb'; assert(~bdIsLoaded(tb));
load_system(fullfile(models,[tb '.slx']));
cleanup=onCleanup(@()close_system(tb,0)); %#ok<NASGU>
si=Simulink.SimulationInput(tb);
fields={'v_ref','v_meas','enable','reset','tick','angle_init','test_mode'};
for name=string(fields)
    si=si.setVariable(['study_' char(name)],timeseries(v.(name),v.time));
end
si=si.setModelParameter('StopTime',num2str(v.time(end),17));
out=sim(si);
fprintf('ACTUAL_TICK_SAMPLES=%d EXPECTED=%d\n',numel(out.actual_tick.Data),numel(v.tick));
disp(out.actual_tick.Time(find(out.actual_tick.Data(:),5))');
assert(isequal(double(out.actual_tick.Data(:)),v.tick),'StudyL1:SchedulerPhase','Original scheduler ticks differ.');
ticks=v.time(v.tick~=0); assert(abs(ticks(1)-.0009)<1e-15);
assert(max(abs(diff(ticks)-.001))<1e-14);
labels={'iq_ref','iq_unlimited','integrator','saturation','integrator_next', ...
    'previous_excess','excess_next','hard_reset','int_reset','iq_limited','error','P','KiTs','AW'};
prefixes={'original','float'};
if getSimulinkBlockHandle([tb '/B1'])>0, prefixes{end+1}='b1'; end
if getSimulinkBlockHandle([tb '/B2'])>0, prefixes{end+1}='b2'; end
d=struct; raw=struct;
for prefix=string(prefixes)
    for k=1:numel(labels)
        ts=out.get(sprintf('%s_%02d',prefix,k)); data=ts.Data(:);
        assert(numel(data)==numel(v.time) && max(abs(ts.Time(:)-v.time))<1e-12);
        d.(prefix).(labels{k})=double(data);
        assert(all(isfinite(double(data))));
        if isfi(data), raw.(prefix).(labels{k})=double(storedInteger(data)); end
    end
end
delta=zeros(1,numel(labels));
for k=1:numel(labels)
    delta(k)=max(abs(d.original.(labels{k})-d.float.(labels{k})));
end
assert(max(delta)<1e-12,'StudyL1:FloatMismatch','Independent float differs from extracted real PI.');
% Also simulate each saved standalone SLX, so testbench copies cannot mask a
% stale or accidentally different deliverable model.
savedNames={'speed_pi_float','speed_pi_fixed','speed_pi_fixed_b2'};
for k=2:numel(prefixes)
    name=savedNames{k-1}; assert(~bdIsLoaded(name));
    load_system(fullfile(models,[name '.slx']));
    one=Simulink.SimulationInput(name);
    inputNames={'v_ref_mmps','v_meas_mmps','enable','reset','sample_tick','angle_init','test_mode'};
    inputs=Simulink.SimulationData.Dataset;
    for j=1:numel(fields)
        values=v.(fields{j});
        if j>=3 && j~=5, values=logical(values); end
        if j<=2 && k>=3
            format=study_l1_types(upper(string(prefixes{k})));
            type=sscanf(format.input,'fixdt(%d,%d,%d)');
            values=fi(values,type(1),type(2),type(3), ...
                fimath('RoundingMethod','Convergent','OverflowAction','Saturate'));
        end
        inputs=inputs.addElement(timeseries(values,v.time),inputNames{j});
    end
    one=one.setExternalInput(inputs);
    one=one.setModelParameter('StopTime',num2str(v.time(end),17), ...
        'SaveOutput','on','OutputSaveName','yout','SaveFormat','Dataset', ...
        'ReturnWorkspaceOutputs','on','LimitDataPoints','off');
    standalone=sim(one);
    for j=1:numel(labels)
        ts=standalone.yout.getElement(j).Values;
        assert(numel(ts.Data)==numel(v.time) && max(abs(ts.Time(:)-v.time))<1e-12);
        assert(isequal(double(ts.Data(:)),d.(prefixes{k}).(labels{j})), ...
            'StudyL1:StandaloneMismatch','Saved standalone model differs: %s/%s',name,labels{j});
    end
    close_system(name,0);
end
% Hold between ticks, reset is sampled only at tick. Old integral drives output.
idle=find(v.tick==0); idle=idle(idle>1);
for prefix=string(prefixes)
    a=d.(prefix);
    for field=string(labels), assert(all(a.(field)(idle)==a.(field)(idle-1))); end
    assert(all(a.iq_ref(a.hard_reset~=0)==0));
    assert(all(a.integrator_next(a.int_reset~=0)==0));
    assert(any(a.iq_limited==1) && any(a.iq_limited==-1));
    assert(any(a.int_reset~=0 & a.hard_reset==0));
    assert(a.hard_reset(450)==1 && a.excess_next(450)>0 && a.integrator_next(450)==0);
    assert(a.previous_excess(460)==a.excess_next(450));
    assert(a.hard_reset(2101)==a.hard_reset(2100) && a.hard_reset(2110)==0);
    assert(all(a.int_reset(2410:10:2440)==0));
    assert(all(a.int_reset(2450:10:2480)==0));
    assert(all(a.int_reset(2490:10:2510)==1));
end
summary=struct('MATLAB',version,'samples',numel(v.time),'ticks',numel(ticks), ...
    'first_tick_s',ticks(1),'period_s',.001,'float_max_errors',delta, ...
    'float_vs_original_pass',true,'standalone_models_match_testbench',true,'HDL_CODER_RUN',false);
lsb=2^-15;
fixedPrefixes=string(prefixes(3:end));
for prefix=fixedPrefixes
    [ref,refraw]=study_l1_fixed_reference(v,upper(prefix),p);
    for field=string(labels)
        assert(isequal(d.(prefix).(field),ref.(field)),'StudyL1:FixedReference','Scalar fi differs for %s/%s',prefix,field);
        if isfield(raw.(prefix),field)
            assert(isequal(raw.(prefix).(field),refraw.(field)),'StudyL1:RawMismatch');
        end
    end
    a=d.float; b=d.(prefix); valid=v.tick~=0;
    assert(isequal(a.hard_reset,b.hard_reset) && isequal(a.int_reset,b.int_reset));
    metric=struct;
    metric.saturation_mismatches=nnz(a.saturation~=b.saturation);
    linear=valid & a.saturation==0 & a.hard_reset==0;
    metric.max_linear_iq_error_A=max(abs(a.iq_ref(linear)-b.iq_ref(linear)));
    metric.max_linear_iq_error_LSB=metric.max_linear_iq_error_A/lsb;
    metric.max_integrator_error_A=max(abs(a.integrator-b.integrator));
    metric.max_iq_unlimited_error_A=max(abs(a.iq_unlimited-b.iq_unlimited));
    metric.max_all_iq_error_A=max(abs(a.iq_ref-b.iq_ref));
    summary.(prefix)=metric;
    summary.(prefix).scalar_fi_all_signals_bit_exact=true;
    if prefix=="b1"
        assert(metric.saturation_mismatches==0,'StudyL1:B1Saturation');
        assert(metric.max_linear_iq_error_LSB<=2,'StudyL1:B1Precision');
    end
end
% Observed ranges and actual logged numeric types, with storage headroom.
rangeRows=cell(0,7);
for prefix=string(prefixes)
    for k=1:numel(labels)
        ts=out.get(sprintf('%s_%02d',prefix,k)); data=ts.Data(:);
        lo=min(double(data)); hi=max(double(data)); wl=NaN; fl=NaN; headroom=NaN;
        if isfi(data)
            nt=numerictype(data); wl=nt.WordLength; fl=nt.FractionLength;
            signbit=double(nt.Signedness=="Signed");
            storageLo=-signbit*2^(wl-fl-signbit);
            storageHi=2^(wl-fl-signbit)-2^-fl;
            headroom=min(lo-storageLo,storageHi-hi);
            assert(headroom>0,'StudyL1:StorageSaturation','Unexpected numeric storage saturation.');
        end
        rangeRows(end+1,:)={char(prefix),labels{k},lo,hi,wl,fl,headroom}; %#ok<AGROW>
    end
end
R=cell2table(rangeRows,'VariableNames',{'model','signal','minimum','maximum','word_length','fraction_length','minimum_storage_headroom'});
writetable(R,fullfile(reportDir,'observed_ranges.csv'));
T=table(v.time,v.tick,v.v_ref,v.v_meas,v.enable,v.reset,v.angle_init,v.test_mode, ...
    'VariableNames',{'time_s','tick','v_ref_mmps','v_meas_mmps','enable','reset','angle_init','test_mode'});
for prefix=string(prefixes)
    for field=string(labels)
        T.([char(prefix) '_' char(field) '_physical'])=d.(prefix).(field);
        if isfield(raw,prefix) && isfield(raw.(prefix),field)
            T.([char(prefix) '_' char(field) '_raw'])=raw.(prefix).(field);
        end
    end
end
writetable(T(v.tick~=0,:),fullfile(reportDir,'tick_comparison.csv'));
writetable(T,fullfile(reportDir,'all_samples.csv'));
f=fopen(fullfile(reportDir,'summary.json'),'w'); cf=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'%s\n',jsonencode(summary,PrettyPrint=true));
disp(jsonencode(summary,PrettyPrint=true)); disp('STUDY_L1_CHECKPOINT_A_REGRESSION_PASS');
end
