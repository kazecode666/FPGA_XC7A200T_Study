function study_l1_c_golden(runDir)
% All expected outputs are extracted from the actual frozen B1 SLX.
study=fileparts(fileparts(mfilename('fullpath')));
assert(~isfolder(runDir),'Fresh directory required'); mkdir(runDir);
diary(fullfile(runDir,'matlab_run.txt')); cdCleanup=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('MATLAB_MCP_OK dedicated batch version=%s release=%s pwd=%s\n',version,version('-release'),pwd);
assert(strcmp(version('-release'),'2026b'));
for feature={'Simulink','Fixed_Point_Toolbox','Simulink_HDL_Coder'}
    assert(license('test',feature{1})); fprintf('LICENSE_PASS %s\n',feature{1});
end
disp(ver('hdlcoder'));
cfg=Simulink.fileGenControl('getConfig');
restore=onCleanup(@()Simulink.fileGenControl('setConfig','config',cfg)); %#ok<NASGU>
Simulink.fileGenControl('set','CacheFolder',fullfile(runDir,'cache'), ...
    'CodeGenFolder',fullfile(runDir,'codegen'),'createDir',true);
p=study_l1_init; normal=study_l1_generate_vectors(p);
gold='speed_pi_fixed'; load_system(fullfile(study,'models',[gold '.slx']));
closeGold=onCleanup(@()close_system(gold,0)); %#ok<NASGU>
export(normal,'normal');
% Full integer input range, strict reset threshold neighbours, deterministic random.
rng(739,'twister');
b=[-2147483648 -2147483647 -8388609 -8388608 -8388607 ...
    -3670017 -3670016 -3670015 -3145729 -3145728 -3145727 ...
    -524289 -524288 -524287 -1 0 1 524287 524288 524289 ...
    3145727 3145728 3145729 3670015 3670016 3670017 8388607 ...
    8388608 8388609 2147483646 2147483647];
[r,m]=ndgrid(b,b); refs=r(:); meas=m(:);
refs=[refs; randi([-2147483648 2147483647],1600,1)];
meas=[meas; randi([-2147483648 2147483647],1600,1)];
% Product rounding halfway cases of either retained parity, both signs.
e=[16384 49152 65536 196608 -16384 -49152 -65536 -196608]';
refs=[refs; zeros(numel(e),1)]; meas=[meas; -e];
% Reachable previous-excess raw halfway cases for the AW conversion.
% Reset an event before each target so x=0; search exact representable P values.
targets=[];
for k=0:140
    target=1073741824+268435456+k*536870912;
    er=round(target*1048576/19363296);
    for q=er+(-1:1)
        if q<=4294967295 && round(q*19363296/1048576)==target
            targets(end+1,1)=q; %#ok<AGROW>
        end
    end
end
assert(~isempty(targets));
extra=[];
for e=reshape([targets;-targets],1,[])
    % e may exceed a single signed32 input; split it exactly over the two inputs.
    ref=floor(e/2); measure=ref-e;
    extra=[extra;0 0 1;ref measure 0;0 0 0]; %#ok<AGROW>
end
% Output conversion ties, reached with x=0 as well (P below +/-1 A).
for k=0:80
    target=16384+k*32768; er=round(target*1048576/19363296);
    if round(er*19363296/1048576)==target
        extra=[extra;0 0 1;0 -er 0;0 0 1;0 er 0]; %#ok<AGROW>
    end
end
refs=[refs;extra(:,1)]; meas=[meas;extra(:,2)];
events=numel(refs); n=2*events+8;
s.time=(0:n-1)'*p.Ts; s.v_ref=zeros(n,1); s.v_meas=zeros(n,1);
s.enable=ones(n,1); s.reset=zeros(n,1); s.tick=zeros(n,1);
s.angle_init=zeros(n,1); s.test_mode=zeros(n,1);
at=(2:2:2*events)';
s.v_ref(at)=refs/2^20; s.v_meas(at)=meas/2^20; s.tick(at)=1;
s.reset(at(1:31:end))=1; s.enable(at(7:23:end))=0;
s.angle_init(at(11:67:end))=1; s.test_mode(at(17:71:end))=1;
if ~isempty(extra)
    tail=at(end-size(extra,1)+1:end);
    s.reset(tail)=extra(:,3); s.enable(tail)=1; s.angle_init(tail)=0; s.test_mode(tail)=0;
end
% Sustained high only triggers once; semantic resets/data changes on idle hold.
s.tick(end-7:end)=[0 1 1 1 0 0 0 0];
s.reset(end-6:end)=1; s.enable(end-5:end)=0;
export(s,'stress');
fprintf('GOLDEN_EXPORT_PASS normal_rows=%d stress_rows=%d actual_B1_only\n',numel(normal.time),n);
% Read installed HDL option support; no code generation in the oracle run.
hdl='speed_pi_hdl'; load_system(fullfile(study,'models',[hdl '.slx']));
c=onCleanup(@()close_system(hdl,0)); %#ok<NASGU>
for gain={'AW'}
    path=[hdl '/HDLCore/PI/' gain{1}];
    try
        value=hdlget_param(path,'ConstMultiplierOptimization');
        fprintf('OPTION_DEFAULT %s ConstMultiplierOptimization=%s\n',gain{1},string(value));
        hdlset_param(path,'ConstMultiplierOptimization','csd');
        fprintf('OPTION_SUPPORTED %s ConstMultiplierOptimization=%s\n',gain{1},string(hdlget_param(path,'ConstMultiplierOptimization')));
    catch ex, fprintf('OPTION_PROBE_ERROR %s\n',ex.message); end
end
    function export(v,label)
        fields={'v_ref','v_meas','enable','reset','tick','angle_init','test_mode'};
        names={'v_ref_mmps','v_meas_mmps','enable','reset','sample_tick','angle_init','test_mode'};
        ds=Simulink.SimulationData.Dataset;
        F=fimath('RoundingMethod','Convergent','OverflowAction','Saturate');
        for j=1:7
            a=v.(fields{j});
            if j<=2, a=fi(a,1,32,20,F); elseif j~=5, a=logical(a); end
            ds=ds.addElement(timeseries(a,v.time),names{j});
        end
        si=Simulink.SimulationInput(gold).setExternalInput(ds);
        si=si.setModelParameter('StopTime',num2str(v.time(end),17),'SaveOutput','on', ...
            'SaveFormat','Dataset','OutputSaveName','yout','ReturnWorkspaceOutputs','on','LimitDataPoints','off');
        out=sim(si); raw=zeros(numel(v.time),14); fl=[15 30 30 0 30 30 30 0 0 30 20 30 30 30];
        for j=1:14
            a=out.yout.getElement(j).Values.Data(:); assert(numel(a)==numel(v.time));
            if isfi(a), raw(:,j)=double(storedInteger(a));
            else, raw(:,j)=double(a)*2^fl(j); assert(all(raw(:,j)==fix(raw(:,j)))); end
        end
        ref=double(storedInteger(fi(v.v_ref,1,32,20,F)));
        measure=double(storedInteger(fi(v.v_meas,1,32,20,F)));
        rows=[ref measure v.enable v.reset v.tick v.angle_init v.test_mode raw];
        f=fopen(fullfile(runDir,[label '_vectors.txt']),'w'); z=onCleanup(@()fclose(f)); %#ok<NASGU>
        fprintf(f,[repmat('%.0f ',1,20) '%.0f\n'],rows');
    end
end
