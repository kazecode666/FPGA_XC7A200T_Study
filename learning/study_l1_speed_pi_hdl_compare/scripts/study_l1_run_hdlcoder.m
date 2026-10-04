function study_l1_run_hdlcoder(runDir)
% Checkpoint B: frozen B1 -> boolean-trigger carrier -> untouched generated SV.
study=fileparts(fileparts(mfilename('fullpath')));
if nargin<1, runDir=fullfile(study,'.runtime',['b_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]); end
assert(~isfolder(runDir),'Use a fresh run directory.'); mkdir(runDir);
diary(fullfile(runDir,'matlab_run.txt')); finishDiary=onCleanup(@()diary('off')); %#ok<NASGU>
assert(strcmp(version('-release'),'2026b')); assert(license('test','Simulink_HDL_Coder'));
fprintf('MATLAB=%s\n',version); disp(ver('hdlcoder')); disp(ver('hdlverifier'));
cfg=Simulink.fileGenControl('getConfig');
restore=onCleanup(@()Simulink.fileGenControl('setConfig','config',cfg)); %#ok<NASGU>
Simulink.fileGenControl('set','CacheFolder',fullfile(runDir,'cache'), ...
    'CodeGenFolder',fullfile(runDir,'codegen'),'createDir',true);
p=study_l1_init; v=study_l1_generate_vectors(p);
gold='speed_pi_fixed'; hdl='speed_pi_hdl';
assert(~bdIsLoaded(gold) && ~bdIsLoaded(hdl));
load_system(fullfile(study,'models',[gold '.slx']));
cleanupGold=onCleanup(@()close_system(gold,0)); %#ok<NASGU>
copyfile(fullfile(study,'models',[gold '.slx']),fullfile(runDir,[hdl '.slx']));
load_system(fullfile(runDir,[hdl '.slx']));
cleanupHdl=onCleanup(@()close_system(hdl,0)); %#ok<NASGU>
set_param(hdl,'Solver','FixedStepDiscrete','FixedStep','0.0001','StopTime','0.01');
mw=get_param(hdl,'ModelWorkspace');
for n=string(fieldnames(p))', mw.assignin(char(n),p.(n)); end
set_param([hdl '/sample_tick'],'OutDataTypeStr','boolean');
set_param([hdl '/v_ref_mmps'],'OutDataTypeStr','fixdt(1,32,20)');
set_param([hdl '/v_meas_mmps'],'OutDataTypeStr','fixdt(1,32,20)');
for n=["enable","reset","angle_init","test_mode"]
    set_param([hdl '/' char(n)],'OutDataTypeStr','boolean');
end
set_param([hdl '/reset'],'Name','pi_reset');
% A virtual HDL-facing carrier encloses the unchanged triggered numeric graph.
% HDL input/output pipeline settings below establish physical register boundaries.
core=[hdl '/HDLCore']; add_block('built-in/SubSystem',core,'Position',[220 75 470 440]);
add_block([hdl '/PI'],[core '/PI'],'Position',[230 90 460 430]);
lines=find_system(hdl,'SearchDepth',1,'FindAll','on','Type','line');
for line=lines', delete_line(line); end
delete_block([hdl '/PI']); % task-owned in-memory copy only
inputNames={'v_ref_mmps','v_meas_mmps','enable','pi_reset','sample_tick','angle_init','test_mode'};
for j=1:7
    add_block('built-in/Inport',[core '/' inputNames{j}],'Port',num2str(j), ...
        'Position',[30 30+50*j 60 44+50*j]);
    if j==5, dest='PI/Trigger'; else, dest=['PI/' num2str(j-(j>5))]; end
    add_line(core,[inputNames{j} '/1'],dest,'autorouting','on');
    add_line(hdl,[inputNames{j} '/1'],['HDLCore/' num2str(j)],'autorouting','on');
end
outPorts=find_system(hdl,'SearchDepth',1,'BlockType','Outport');
for j=1:numel(outPorts)
    port=get_param(outPorts{j},'Port'); name=get_param(outPorts{j},'Name');
    add_block('built-in/Outport',[core '/' name],'Port',port, ...
        'Position',[540 20+38*str2double(port) 570 34+38*str2double(port)]);
    add_line(core,['PI/' port],[name '/1'],'autorouting','on');
    add_line(hdl,['HDLCore/' port],[name '/1'],'autorouting','on');
end
fingerprintGold=piFingerprint([gold '/PI']);
fingerprintCarrier=piFingerprint([core '/PI']);
assert(isequal(fingerprintGold,fingerprintCarrier),'Frozen PI block parameters/wiring changed.');
writeText(fullfile(runDir,'pi_semantic_fingerprint.json'),jsonencode(fingerprintGold,PrettyPrint=true));
fprintf('FROZEN_PI_PARAMETERS_AND_WIRING_IDENTICAL blocks=%d\n',numel(fieldnames(fingerprintGold.blocks)));
g=simulate(gold,false); c=simulate(hdl,true);
for k=1:14
    assert(isequal(g(:,k),c(:,k)),'StudyL1:CarrierMismatch','Carrier differs at output %d',k);
end
fprintf('CARRIER_B1_ALL_14_RAW_CODES_EXACT rows=%d ticks=%d\n',size(g,1),sum(v.tick));
% Store actual golden-model raw codes, not a reimplemented PI oracle.
f=fopen(fullfile(runDir,'vectors.txt'),'w'); doneFile=onCleanup(@()fclose(f)); %#ok<NASGU>
ref=double(storedInteger(fi(v.v_ref,1,32,20,fimath('RoundingMethod','Convergent','OverflowAction','Saturate'))));
meas=double(storedInteger(fi(v.v_meas,1,32,20,fimath('RoundingMethod','Convergent','OverflowAction','Saturate'))));
rows=[ref meas v.enable v.reset v.tick v.angle_init v.test_mode g];
fprintf(f,[repmat('%.0f ',1,size(rows,2)-1) '%.0f\n'],rows');
clear doneFile;
writematrix(rows,fullfile(runDir,'golden_raw.csv'));
options={'TargetLanguage','SystemVerilog','TargetFrequency',50, ...
    'SynthesisTool','Xilinx Vivado','SynthesisToolChipFamily','Artix7', ...
    'SynthesisToolDeviceName','xc7a200t','SynthesisToolPackageName','fbg484', ...
    'SynthesisToolSpeedValue','-2','ClockInputPort','clk', ...
    'ResetInputPort','init_reset','ResetType','Synchronous','ResetAssertedLevel','active-high', ...
    'ClockEnableInputPort','clk_enable','TriggerAsClock','off', ...
    'MinimizeClockEnables','off','MinimizeGlobalResets','off', ...
    'TreatRatesAsHardwareRates','off','Oversampling',1, ...
    'Traceability','on','HDLGenerateWebview','off','ResourceReport','on', ...
    'OptimizationReport','on','GenerateHDLTestBench','off', ...
    'GenerateValidationModel','on','EDAScriptGeneration','off'};
for k=1:2:numel(options), hdlset_param(hdl,options{k},options{k+1}); end
hdlset_param(core,'InputPipeline',1,'OutputPipeline',1);
config=struct('global_options',{options},'DUT',[hdl '/HDLCore'], ...
    'InputPipeline',1,'OutputPipeline',1,'target_part','xc7a200tfbg484-2', ...
    'physical_clock_hz',50000000,'first_source_tick_seconds',.0009, ...
    'source_update_seconds',.001,'source_model_base_rate_seconds',p.Ts);
writeText(fullfile(runDir,'generator_config.json'),jsonencode(config,PrettyPrint=true));
fprintf('CLOCK_CONTRACT clk=50MHz tick-first=0.9ms period=1ms TriggerAsClock=off\n');
fprintf('RESET_CONTRACT init_reset=power-on; pi_reset=sampled command, does not clear excess\n');
checks=checkhdl(core); disp(checks);
save(fullfile(runDir,'compatibility.mat'),'checks','options');
if ~isempty(checks), assert(~any(strcmp({checks.level},'Error')),'HDL compatibility must pass before makehdl.'); end
writeText(fullfile(runDir,'compatibility.json'),jsonencode(checks,PrettyPrint=true));
outModel=fullfile(runDir,[hdl '.slx']); save_system(hdl,outModel);
fprintf('PREFLIGHT_PASS: generation starts only after carrier equivalence and compatibility.\n');
makehdl(core,'TargetDirectory',fullfile(runDir,'generated'));
fprintf('HDL_GENERATION_COMPLETE %s\n',runDir);

    function raw=simulate(model,carrier)
        fields={'v_ref','v_meas','enable','reset','tick','angle_init','test_mode'};
        names={'v_ref_mmps','v_meas_mmps','enable','reset','sample_tick','angle_init','test_mode'};
        if carrier, names{4}='pi_reset'; end
        ds=Simulink.SimulationData.Dataset;
        for j=1:7
            values=v.(fields{j});
            if j<=2
                values=fi(values,1,32,20,fimath('RoundingMethod','Convergent','OverflowAction','Saturate'));
            elseif j~=5 || carrier, values=logical(values); end
            ds=ds.addElement(timeseries(values,v.time),names{j});
        end
        si=Simulink.SimulationInput(model).setExternalInput(ds);
        si=si.setModelParameter('StopTime',num2str(v.time(end),17), ...
            'SaveOutput','on','SaveFormat','Dataset','OutputSaveName','yout', ...
            'ReturnWorkspaceOutputs','on','LimitDataPoints','off');
        out=sim(si); raw=zeros(numel(v.time),14);
        fl=[15 30 30 0 30 30 30 0 0 30 20 30 30 30];
        for j=1:14
            data=out.yout.getElement(j).Values.Data(:);
            assert(numel(data)==numel(v.time));
            if isfi(data), raw(:,j)=double(storedInteger(data));
            else
                % Dataset may expose physical doubles; binary scaling is exact
                % for these model words (<2^53), verified as integral raw codes.
                raw(:,j)=double(data)*2^fl(j);
                assert(all(raw(:,j)==fix(raw(:,j))));
            end
        end
    end
end

function fingerprint=piFingerprint(system)
paths=sort(find_system(system,'SearchDepth',1,'Type','Block'));
paths=paths(~strcmp(paths,system)); blocks=struct;
for j=1:numel(paths)
    path=paths{j}; name=get_param(path,'Name');
    names=sort(fieldnames(get_param(path,'DialogParameters')));
    params=struct;
    for k=1:numel(names), params.(names{k})=get_param(path,names{k}); end
    blocks.(name)=struct('type',get_param(path,'BlockType'),'parameters',params);
end
lines=find_system(system,'SearchDepth',1,'FindAll','on','Type','line');
connections={};
for line=reshape(lines,1,[])
    source=get_param(line,'SrcPortHandle'); dest=get_param(line,'DstPortHandle');
    if source<0, continue; end
    for d=reshape(dest,1,[])
        connections{end+1}=sprintf('%s/%s:%d -> %s/%s:%d', ...
            get_param(get_param(source,'Parent'),'Name'),get_param(source,'PortType'),get_param(source,'PortNumber'), ...
            get_param(get_param(d,'Parent'),'Name'),get_param(d,'PortType'),get_param(d,'PortNumber')); %#ok<AGROW>
    end
end
fingerprint=struct('blocks',blocks,'connections',{sort(unique(connections))});
end

function writeText(path,txt)
f=fopen(path,'w','n','UTF-8'); c=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'%s\n',txt);
end
