function result=m3_model_stage(cfg)
% 原定点 -> gm 独立逐位验证；只加载本次拥有的副本，不保存正式模型。
arguments
    cfg (1,1) struct
end
descriptor=fullfile(cfg.run_dir,'final_build.json');
m3_require_batch_models(cfg);
assert(isfile(descriptor),'M3:FINAL_BUILD_REQUIRED','Missing final post-testbench build descriptor.');
build=jsondecode(fileread(descriptor));
candidateContract=[];
if isfield(cfg,'candidate')
    manifest=jsondecode(fileread(fullfile(cfg.run_dir,'manifest.json')));
    contractFile=manifest.candidate_contract.path;
    if isempty(regexp(contractFile,'^(?:[A-Za-z]:|[/\\])','once')),contractFile=fullfile(cfg.root,contractFile);end
    assert(strcmp(m3_sha256(contractFile),manifest.candidate_contract.sha256),'M3:CANDIDATE_CONTRACT');
    candidateContract=jsondecode(fileread(contractFile));
end
work=[tempname(cfg.run_dir) '_model'];mkdir(work);
modelFolder=fullfile(work,'models');mkdir(modelFolder);
sourceFiles=dir(cfg.source_dir);
for k=1:numel(sourceFiles)
    if ~sourceFiles(k).isdir,copyfile(fullfile(cfg.source_dir,sourceFiles(k).name),fullfile(modelFolder,sourceFiles(k).name));end
end
gm=['gm_' cfg.model];vnl=[gm '_vnl'];
for n={gm,vnl}
    file=fullfile(build.rtl_dir,cfg.model,[n{1} '.slx']);
    assert(isfile(file),'M3:DERIVED_MODEL_MISSING','Missing final generated model %s.',file);
    copyfile(file,fullfile(modelFolder,[n{1} '.slx']));
end
owned={cfg.model,gm,vnl};
for n=owned,assert(~bdIsLoaded(n{1}),'M3:MODEL_ALREADY_LOADED','Refuse to replace an already loaded %s.',n{1});end
oldpwd=pwd;oldpath=path;oldgen=Simulink.fileGenControl('getConfig');
cleanup=onCleanup(@()restore(owned,oldpwd,oldpath,oldgen)); %#ok<NASGU>
cd(modelFolder);addpath(modelFolder,'-begin');
Simulink.fileGenControl('set','CacheFolder',fullfile(work,'cache'),'CodeGenFolder',fullfile(work,'code'),'createDir',true);
evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');
fixedCfg=evalin('base','FOC_Fixed_Config');
diagnostics=struct;
for n=owned
    file=fullfile(modelFolder,[n{1} '.slx']);load_system(file);
    assert(strcmpi(get_param(n{1},'FileName'),file),'M3:MODEL_PATH','Unexpected loaded model path.');
    set_param(n{1},'DataTypeOverride','Off','SimulationMode','normal');
    before=get_param(n{1},'IntegerOverflowMsg');
    assert(strcmpi(before,'error'),'M3:DIAGNOSTIC_CONTRACT','%s must retain IntegerOverflowMsg=error.',n{1});
    diagnostics.(n{1})=struct('IntegerOverflowMsg_before',before, ...
        'IntegerOverflowMsg_observer',get_param(n{1},'IntegerOverflowMsg'));
end
% 固定相位来自最终生成报告。禁止搜索“最佳平移”消除数值/反馈错误。
latency=274;
if isfield(cfg,'candidate')
    contract=candidateContract;m=manifest;
    assert(strcmp(contract.candidate_id,cfg.candidate.candidate_id),'M3:CANDIDATE_ID');
    assert(contract.output_phase_cycles==m.candidate_contract.output_phase_cycles,'M3:CANDIDATE_PHASE');
    latency=contract.output_phase_cycles;
end
writejson(fullfile(work,'comparison_contract.json'),struct('build',build,'output_phase_cycles',latency, ...
    'temporary_model_diagnostics',diagnostics, ...
    'denominator_policy','Every logged denominator must be nonzero, including startup and the held terminal frame. No startup or per-frame exception.', ...
    'clock_period_s',cfg.clock_period_s,'frame_cycles',cfg.cycles_per_frame, ...
    'source_state_event','n*100us, block output before update', ...
    'gm_state_event','n*100us, mapped Delay/RateTransition output', ...
    'hardware_reset_and_ce','NOT_TESTED_HERE: generated model has only the original nine ports; RTL protocol stage required'));
cases=m3_foc_vectors;
% 首个短序列直接重放确定性边界中的非零/限幅/复位点，并从零初态启动。
probeIndices=[1 202 211 221 231 241 251 300 310 320 901 902 920 921 941 942 944];
probe=struct('name','directed_probe','u',cases(1).u(probeIndices,:));
probe.u(1,8)=1;
probeOnly=isfield(cfg,'model_probe_only')&&cfg.model_probe_only;
caseCount=numel(cases);if probeOnly,caseCount=0;end
caseResults=cell(1,caseCount+1);
caseResults{1}=run_case(probe,true);
for k=1:caseCount,caseResults{k+1}=run_case(cases(k),false);end
result=struct('stage','model','status','PASS','run_dir',cfg.run_dir,'evidence',{{work}}, ...
    'failures',{{}},'cases',{caseResults},'fixed_output_phase_cycles',latency, ...
    'global_reset_ce_numeric_oracle','RTL_STAGE_REQUIRED','complete_suites',~probeOnly);
for k=1:numel(caseResults)
    if ~strcmp(caseResults{k}.status,'PASS')
        result.status='FAIL';result.failures{end+1}=caseResults{k};
    end
end
if probeOnly&&strcmp(result.status,'PASS'),result.status='NOT_RUN';end
writejson(fullfile(work,'model_result.json'),result);
writejson(fullfile(cfg.run_dir,['model_result_' getleaf(work) '.json']),result);
fprintf('M3_MODEL_COMPLETE %s %s\n',result.status,work);

    function item=run_case(test,isProbe)
        label=matlab.lang.makeValidName(test.name);folder=fullfile(work,label);mkdir(folder);
        item=struct('name',test.name,'status','NOT_RUN','samples',size(test.u,1), ...
            'folder',folder,'source_gm',struct,'validation',struct('status','NOT_RUN'),'failures',{{}});
        try
            [ds,inputTable]=stimulus(test.u,fixedCfg,cfg.data_period_s);
            writetable(inputTable,fullfile(folder,'input_hex.csv'));
            sourceLog=configure_source(cfg.model,isProbe);
            sourceOut=simulate(cfg.model,ds,(size(test.u,1)-1)*cfg.data_period_s,cfg.data_period_s);
            save(fullfile(folder,'source.mat'),'sourceOut','-v7.3');
            sourceHex=frame_table(sourceOut,sourceLog,0,size(test.u,1),cfg);
            sourceTable=[inputTable sourceHex];writetable(sourceTable,fullfile(folder,'source_hex.csv'));
            gmLog=configure_gm(gm,isProbe);
            stop=(size(test.u,1)-1)*cfg.data_period_s+(latency+1)*cfg.clock_period_s;
            if isProbe,stop=size(test.u,1)*cfg.data_period_s;end
            gmOut=simulate(gm,ds,stop,cfg.clock_period_s);
            save(fullfile(folder,'gm.mat'),'gmOut','-v7.3');
            item.denominators=check_denominators(gmOut,cfg,latency,folder,'gm');
            gmHex=frame_table(gmOut,gmLog,latency,size(test.u,1),cfg);
            gmTable=[inputTable gmHex];writetable(gmTable,fullfile(folder,'gm_hex.csv'));
            comparison=compare_tables(sourceHex,gmHex,cfg,latency);
            comparison.values_compared=height(sourceHex)*width(sourceHex);
            comparison.output_phase_cycles=latency;
            comparison.state_event_cycles=(0:height(sourceHex)-1)*cfg.cycles_per_frame;
            item.source_gm=comparison;
            writejson(fullfile(folder,'source_gm_result.json'),comparison);
            if isProbe
                events=probe_events(sourceOut,gmOut,size(test.u,1),cfg,latency);
                writetable(events,fullfile(folder,'state_phase_events.csv'));
                % 实测原生100us旧态相同；源下一态必须在gm下一帧旧态可见。
                % 不把原生100us producer伪称为硬件phase4999日志。
                item.next_state_mapping=check_next_state(sourceOut,gmOut,size(test.u,1),cfg,folder);
                assert(strcmp(item.next_state_mapping.status,'PASS'),'M3:NEXT_STATE_BITS', ...
                    'Source next state differs from gm next-frame old state; see next_state_mapping.json.');
            end
            if ~strcmp(comparison.status,'PASS'),item.status='FAIL';end
            if ~strcmp(item.denominators.status,'PASS'),item.status='FAIL';end
        catch exception
            item.status='FAIL';item.failures{end+1}=failure(exception);
        end
        % 原生validation用含非零/限幅/复位的17帧；长序列由独立位比较覆盖。
        if isProbe
            try
                [ds,~]=stimulus(test.u,fixedCfg,cfg.data_period_s);
                stop=size(test.u,1)*cfg.data_period_s;
                clear_logging(vnl);log_denominators(vnl);
                validationOut=simulate(vnl,ds,stop,cfg.clock_period_s);
                save(fullfile(folder,'validation.mat'),'validationOut','-v7.3');
                divisionCheck=check_denominators(validationOut,cfg,latency,folder,'validation');
                item.validation=struct('status','PASS','finite_stop_s',stop, ...
                    'denominators',divisionCheck, ...
                    'scope','unmodified generated validation assertions and error diagnostics; independent bit oracle reported separately');
                if ~strcmp(divisionCheck.status,'PASS'),item.validation.status='FAIL';item.status='FAIL';end
            catch exception
                item.validation=struct('status','FAIL','failure',failure(exception));
                item.failures{end+1}=failure(exception);item.status='FAIL';
            end
        else
            item.validation=struct('status','NOT_RUN','reason','covered_by_directed_probe', ...
                'independent_source_gm_full_sequence',true);
        end
        validationRequiredPassed=~isProbe||strcmp(item.validation.status,'PASS');
        if strcmp(item.status,'NOT_RUN')&&strcmp(item.source_gm.status,'PASS')&&validationRequiredPassed,item.status='PASS';end
        writejson(fullfile(folder,'case_result.json'),item);
        fprintf('M3_MODEL_CASE %s %s %d\n',test.name,item.status,size(test.u,1));
    end
end

function names=configure_source(m,extra)
clear_logging(m);d=[m '/FOC_DUT'];names=main_names;
for k=1:3,log_port(d,k,names{k});end
state={'Id/x_d_z','Iq/x_q_z','dq_voltage_limiter/Unit Delay','dq_voltage_limiter/Unit Delay1'};
next={'x_d_next','x_q_next','aw_d_next','aw_q_next'};
for k=1:4
    b=[d '/' state{k}];log_port(b,1,names{k+3});
    if extra,log_input(b,next{k});end
end
end

function names=configure_gm(m,extra)
clear_logging(m);d=[m '/FOC_DUT/FOC_DUT'];names=main_names;
assert(getSimulinkBlockHandle(d)>0,'M3:GM_STRUCTURE','Expected final inner generated DUT.');
for k=1:3,log_port(d,k,names{k});end
state={'Id/x_d_z','Iq/x_q_z','dq_voltage_limiter/Unit Delay','dq_voltage_limiter/Unit Delay1'};
next={'x_d_next','x_q_next','aw_d_next','aw_q_next'};
for k=1:4
    b=[d '/' state{k}];log_port(b,1,names{k+3});
    if extra,log_input(b,next{k});end
end
log_denominators(m);
end

function names=main_names
names={'duty_u_cmd','duty_v_cmd','duty_w_cmd','x_d_old','x_q_old','aw_d_old','aw_q_old'};
end

function clear_logging(m)
blocks=find_system(m,'LookUnderMasks','all','FollowLinks','off','Type','Block');
for k=1:numel(blocks)
    p=get_param(blocks{k},'PortHandles');
    for h=p.Outport,set_param(h,'DataLogging','off');end
end
set_param(m,'SignalLogging','on','SignalLoggingName','logsout');
end

function log_port(block,port,name)
p=get_param(block,'PortHandles');mark(p.Outport(port),name);
end

function log_input(block,name,portIndex)
if nargin<3,portIndex=1;end
p=get_param(block,'PortHandles');line=get_param(p.Inport(portIndex),'Line');
assert(line>0,'M3:STATE_INPUT','Unconnected mapped state input %s.',block);
mark(get_param(line,'SrcPortHandle'),name);
end

function log_denominators(m)
d=[m '/FOC_DUT/FOC_DUT'];
paths={'dq_voltage_limiter/Divide/Divide', ...
    'SVPWMG/XYZ Calculate/reciprocal/reciprocal', ...
    'SVPWMG/T1T2 Calculate/Fcn1/Defined_Quotient/Defined_Quotient', ...
    'SVPWMG/T1T2 Calculate/Fcn2/Defined_Quotient/Defined_Quotient'};
names={'den_limiter','den_bus_reciprocal','den_t1','den_t2'};ports=[2 1 2 2];
for k=1:numel(paths),log_input([d '/' paths{k}],names{k},ports(k));end
end

function result=check_denominators(out,cfg,latency,folder,label)
names={'den_limiter','den_bus_reciprocal','den_t1','den_t2'};
result=struct('status','PASS','first_disallowed_zero_cycle',0,'signals',[], ...
    'output_valid_phase_cycles',latency,'first_invalid_zero',[], ...
    'scope','All logged cycles, including startup and held terminal frame; every denominator must be nonzero.');
zeroSignal=strings(0,1);zeroCycle=zeros(0,1);zeroHex=strings(0,1);
for k=1:numel(names)
    v=out.logsout.get(names{k}).Values;data=v.Data(:);
    assert(isfi(data),'M3:LOSSY_DENOMINATOR','%s must retain fi values.',names{k});
    cycles=round(v.Time(:)/cfg.clock_period_s);
    assert(all(abs(v.Time(:)-cycles*cfg.clock_period_s)<cfg.clock_period_s*1e-5),'M3:DENOMINATOR_TIME_GRID','Denominator time grid mismatch.');
    zero=find(data==0);bad=zero;
    entry=struct('name',names{k},'observed_points',numel(data),'last_cycle',cycles(end), ...
        'zero_count',numel(zero),'first_zero_cycle',[],'last_zero_cycle',[], ...
        'first_zero_phase',[],'last_zero_phase',[], ...
        'invalid_zero_count',numel(bad));
    if ~isempty(zero)
        entry.first_zero_cycle=cycles(zero(1));entry.last_zero_cycle=cycles(zero(end));
        entry.first_zero_phase=mod(entry.first_zero_cycle,cfg.cycles_per_frame);
        entry.last_zero_phase=mod(entry.last_zero_cycle,cfg.cycles_per_frame);
        % 异常较多时只留首尾和首批失败点；完整fi仍在MAT。
        keep=unique([zero(1:min(numel(zero),32));zero(max(1,numel(zero)-31):end);bad(1:min(numel(bad),32))]);
        zeroSignal=[zeroSignal;repmat(string(names{k}),numel(keep),1)]; %#ok<AGROW>
        zeroCycle=[zeroCycle;cycles(keep)];zeroHex=[zeroHex;lower(string(hex(data(keep))))]; %#ok<AGROW>
    end
    if ~isempty(bad)
        result.status='FAIL';
        if isempty(result.first_invalid_zero)
            result.first_invalid_zero=struct('signal',names{k},'cycle',cycles(bad(1)), ...
                'sample_id',floor(cycles(bad(1))/cfg.cycles_per_frame), ...
                'phase_cycles',mod(cycles(bad(1)),cfg.cycles_per_frame), ...
                'time_s',v.Time(bad(1)),'hex',char(lower(string(hex(data(bad(1)))))));
        end
    end
    if isempty(result.signals),result.signals=entry;else,result.signals(end+1)=entry;end
end
sample=floor(zeroCycle/cfg.cycles_per_frame);phase=mod(zeroCycle,cfg.cycles_per_frame);
writetable(table(zeroSignal,zeroCycle,sample,phase,zeroHex,'VariableNames',{'signal','cycle','sample_id','phase_cycles','hex'}),fullfile(folder,[label '_denominator_zeros.csv']));
writejson(fullfile(folder,[label '_denominator_result.json']),result);
end

function mark(port,name)
set_param(port,'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',name, ...
    'DataLoggingDecimateData','off','DataLoggingLimitDataPoints','off');
end

function out=simulate(m,ds,stop,step)
in=Simulink.SimulationInput(m).setExternalInput(ds).setModelParameter( ...
    'SolverType','Fixed-step','Solver','FixedStepDiscrete','FixedStep',num2str(step,17), ...
    'StartTime','0','StopTime',num2str(stop,17),'SaveOutput','off','SaveTime','off', ...
    'SampleTimeConstraint','Unconstrained','ReturnWorkspaceOutputs','on','SignalLogging','on');
out=sim(in);
end

function [ds,t]=stimulus(u,types,period)
assert(size(u,2)==9&&all(isfinite(u(:))),'M3:FIXTURE_SHAPE','Expected finite Nx9 input fixture.');
assert(all(ismember(u(:,8),[0 1])),'M3:RESET_INPUT','PI reset must be boolean.');
keys={'Current','Current','Current','Angle','Omega','Current','Current','Reset','Bus'};
names={'ia','ib','ic','theta_e','omega_e','iq_ref','id_ref','PI_Reset_EN','Vdc_V'};
time=(0:size(u,1)-1)'*period;ds=Simulink.SimulationData.Dataset;
t=table((0:size(u,1)-1)','VariableNames',{'sample_id'});
for k=1:9
    if k==8
        data=logical(u(:,k));bits=string(double(data));
    else
        data=fi(u(:,k),types.Types.(keys{k}),types.Fimath);bits=lower(string(hex(data(:))));
    end
    % Inport OutputAfterFinalValue=0时，有限Dataset末点后会补零；显式保持
    % 两个尾帧供流水线排空/最终提交观察，golden/input表仍只有原N帧。
    heldData=[data;data(end);data(end)];heldTime=[time;size(u,1)*period;(size(u,1)+1)*period];
    ds=ds.addElement(setinterpmethod(timeseries(heldData,heldTime),'zoh'),names{k});t.(names{k})=bits;
end
end

function t=frame_table(out,names,latency,N,cfg)
t=table;frame=(0:N-1)'*cfg.cycles_per_frame;
for k=1:numel(names)
    cycles=frame;if k<=3,cycles=cycles+latency;end
    t.(names{k})=exact_hex(out,names{k},cycles,cfg.clock_period_s);
end
end

function bits=exact_hex(out,name,cycles,clock)
sig=out.logsout.get(name);v=sig.Values;data=v.Data(:);
assert(isfi(data),'M3:LOSSY_LOG_TYPE','%s logged as %s, expected fi.',name,class(data));
actual=round(v.Time(:)/clock);
assert(all(abs(v.Time(:)-actual*clock)<clock*1e-5),'M3:LOG_TIME_GRID','%s is not on the hardware time grid.',name);
[found,at]=ismember(cycles,actual);
assert(all(found),'M3:EVENT_MISSING','%s missing required cycle %d.',name,cycles(find(~found,1)));
bits=lower(string(hex(data(at))));
end

function result=compare_tables(expected,observed,cfg,latency)
result=struct('status','PASS','bit_mismatch_count',0,'value_mismatch_count',0,'first_mismatch',[],'signals',{expected.Properties.VariableNames});
for k=1:width(expected)
    bad=find(expected{:,k}~=observed{:,k});
    result.value_mismatch_count=result.value_mismatch_count+numel(bad);
    for r=bad'
        result.bit_mismatch_count=result.bit_mismatch_count+numel(different_bits(char(expected{r,k}),char(observed{r,k})));
    end
    if ~isempty(bad)&&isempty(result.first_mismatch)
        row=bad(1);cycle=(row-1)*cfg.cycles_per_frame;if k<=3,cycle=cycle+latency;end
        a=char(expected{row,k});b=char(observed{row,k});
        result.first_mismatch=struct('sample_id',row-1,'cycle',cycle,'signal',expected.Properties.VariableNames{k}, ...
            'expected_hex',a,'observed_hex',b,'bit_positions_lsb0',different_bits(a,b));
    end
end
if result.bit_mismatch_count>0,result.status='FAIL';end
end

function result=check_next_state(source,gm,N,cfg,folder)
next={'x_d_next','x_q_next','aw_d_next','aw_q_next'};
old={'x_d_old','x_q_old','aw_d_old','aw_q_old'};
expected=table;observed=table;
for k=1:4
    expected.(next{k})=exact_hex(source,next{k},(0:N-1)'*cfg.cycles_per_frame,cfg.clock_period_s);
    observed.(next{k})=exact_hex(gm,old{k},(1:N)'*cfg.cycles_per_frame,cfg.clock_period_s);
end
result=compare_tables(expected,observed,cfg,0);
result.values_compared=4*N;result.commits_compared=N;
result.mapping='source next(n) at n*100us equals gm mapped old(n+1) at (n+1)*100us, including final commit';
if ~isempty(result.first_mismatch),result.first_mismatch.cycle=(result.first_mismatch.sample_id+1)*cfg.cycles_per_frame;end
writetable([table((0:N-1)',(1:N)'*cfg.cycles_per_frame,'VariableNames',{'sample_id','gm_observation_cycle'}) ...
    renamevars(expected,next,strcat('source_',next)) renamevars(observed,next,strcat('gm_',next))],fullfile(folder,'next_state_hex.csv'));
writejson(fullfile(folder,'next_state_mapping.json'),result);
end

function positions=different_bits(a,b)
assert(numel(a)==numel(b),'M3:BIT_WIDTH','Expected and observed hex width differ.');
positions=[];
for j=1:numel(a)
    mask=bitxor(uint8(hex2dec(a(end-j+1))),uint8(hex2dec(b(end-j+1))));
    for k=1:4,if bitget(mask,k),positions(end+1)=4*(j-1)+k-1;end;end %#ok<AGROW>
end
end

function t=probe_events(source,gm,N,cfg,latency)
t=table;names={'x_d_old','x_q_old','aw_d_old','aw_q_old','x_d_next','x_q_next','aw_d_next','aw_q_next'};
sample=[];offset=[];model=[];signal=[];values=strings(0,1);
for which=1:2
    out=source;if which==2,out=gm;end
    for j=1:numel(names)
        v=out.logsout.get(names{j}).Values;
        assert(isfi(v.Data),'M3:LOSSY_LOG_TYPE','Probe state must remain fi.');
        cyc=round(v.Time(:)/cfg.clock_period_s);
        phases=mod(cyc,cfg.cycles_per_frame);
        keep=ismember(phases,[0 1 165 166 latency cfg.cycles_per_frame-1])&cyc<=N*cfg.cycles_per_frame;
        % 原生100us状态只产生phase0；高速producer保留事件前后的真实记录。
        if any(keep)
            n=nnz(keep);sample=[sample;floor(cyc(keep)/cfg.cycles_per_frame)];offset=[offset;phases(keep)]; %#ok<AGROW>
            model=[model;repmat(string(which),n,1)];signal=[signal;repmat(string(names{j}),n,1)]; %#ok<AGROW>
            values=[values;lower(string(hex(v.Data(keep))))]; %#ok<AGROW>
        end
    end
end
t.sample_id=sample;t.phase_cycles=offset;t.model=model;t.signal=signal;t.hex=values;
t.model(t.model=="1")="source";t.model(t.model=="2")="gm";
end

function restore(owned,oldpwd,oldpath,oldgen)
for n=owned,if bdIsLoaded(n{1}),close_system(n{1},0);end;end
cd(oldpwd);path(oldpath);Simulink.fileGenControl('setConfig','config',oldgen);
end

function item=failure(exception)
item=struct('identifier',exception.identifier,'message',exception.message,'stack',{exception.stack});
end

function name=getleaf(folder)
[~,name]=fileparts(folder);
end

function writejson(file,value)
assert(~isfile(file),'M3:EVIDENCE_EXISTS','Preserve existing %s.',file);
fid=fopen(file,'w');assert(fid>=0,'M3:WRITE','Cannot write %s.',file);cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,PrettyPrint=true));
end
