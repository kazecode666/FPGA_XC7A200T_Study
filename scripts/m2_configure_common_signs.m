function in=m2_configure_common_signs(in,model,file)
% Explicit opt-in, diagnostic copies only. Observe the actual consumed signal.
assert(contains(get_param(model,'FileName'),[filesep '.runtime' filesep]));
a=load(file,'tape');tape=a.tape;
assert(size(tape.values,1)==4000001&&size(tape.values,2)==3);
assert(all(ismember(tape.values(:),int8([-1 0 1]))));
assert(isequal(round(tape.time_s/1e-6),(0:4000000)'));
phase={'a','b','c'};deltaSid=[822 837 852];originalSid=[826 841 856];
for k=1:3
    product=Simulink.ID.getFullName(sprintf('%s:%d',model,deltaSid(k)));
    port=get_param(product,'PortHandles');line=get_param(port.Inport(1),'Line');
    source=get_param(line,'SrcBlockHandle');
    assert(strcmp(get_param(source,'BlockType'),'FromWorkspace'));
    assert(strcmp(get_param(source,'VariableName'),['M2_Common_Sign_' phase{k}]));
    assert(strcmp(get_param(source,'Interpolate'),'off'));
    signal=timeseries(double(tape.values(:,k)),tape.time_s);
    signal=setinterpmethod(signal,'zoh');
    in=in.setVariable(['M2_Common_Sign_' phase{k}],signal);
    observe(source,['used_recorded_sign_' phase{k}],1);
    observe(Simulink.ID.getFullName(sprintf('%s:%d',model,originalSid(k))), ...
        ['computed_unused_sign_' phase{k}],100);
end
end
function observe(block,name,decimation)
p=get_param(block,'PortHandles');
set_param(p.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom', ...
    'DataLoggingName',name,'DataLoggingDecimateData','on', ...
    'DataLoggingDecimation',num2str(decimation));
end
