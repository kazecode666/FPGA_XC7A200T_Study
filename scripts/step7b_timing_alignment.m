function step7b_timing_alignment
% Fresh simulation state per run; temporary stimuli are never saved to SLX.
root=fileparts(fileparts(mfilename('fullpath')));
assert(strcmp(version('-release'),'2026b'));
oldpwd=pwd; oldpath=getenv('PATH'); oldvivado=getenv('XILINX_VIVADO'); mp=path;
cleanup=onCleanup(@() restore(oldpwd,oldpath,oldvivado,mp)); %#ok<NASGU>
hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat');
addpath(fullfile(root,'simulink模型')); cd(fullfile(root,'.Xil','step7b_foc_cosim'));
raw=splitlines(string(fileread(fullfile(root,'motor_control_ip','integration','tb','vectors','step6d_pwm_vectors.txt'))));
rows=raw(strlength(strtrim(raw))>0 & ~startsWith(raw,'#'));
% Consecutive accepted golden rows: d-current then PI reset, both kind/profile 0.
indices=[5 6]; vals=zeros(2,22);
fid=fopen(fullfile(root,'docs','reports','step7b','timing_alignment.txt'),'w'); cl=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'Communication=50us HDL_clock=20ns reset_release=200ns PreRunTime=0 timescale=1s:1s\n');
for j=1:2
    tokens=split(strtrim(rows(indices(j)+1)));
    for k=1:22
        % All fields fit signed 32 bits after sign extension; avoid hex2dec(64bit) precision loss.
        lo=hex2dec(extractAfter(tokens(k),8));
        if startsWith(tokens(k),'ffffffff'), lo=lo-2^32; end
        vals(j,k)=lo;
    end
    assert(all(vals(j,1:2)==0) && vals(j,3)==indices(j));
    fprintf(fid,'Vector %c data_row_1based=%d index=%d raw=%s\n','A'+j-1,indices(j)+1,indices(j),rows(indices(j)+1));
end
names={'ia','ib','ic','theta_e','we','id_ref','iq_ref','vdc','pi_reset','uq_zero_en'};
physical=vals(:,4:13)./[2^15 2^15 2^15 65536/(2*pi) 2^16 2^15 2^15 2^15 1 1];
expected=vals(:,17:19); assert(~isequal(expected(1,:),expected(2,:)));
fprintf(fid,'Physical columns=ia ib ic theta_rad we id_ref iq_ref vdc pi_reset uq_zero_en\n');
for j=1:2
    fprintf(fid,'Vector %c physical=%s expected_CMP=%s\n','A'+j-1,mat2str(physical(j,:),17),mat2str(expected(j,:)));
end
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m),'Close Simple model before timing test');
for rep=1:3
    load_system(m); cm=onCleanup(@() close_system(m,0));
    a=[m '/FPGA_HDL_Cosim/FPGA_Input_Adapter'];
    for k=1:numel(names), replaceSource([a '/Smoke_' names{k}],physical(1,k),physical(2,k)); end
    si=Simulink.SimulationInput(m);
    si=si.setVariable('FPGA_Cosim_Enable',1); si=si.setVariable('FPGA_Cosim_Input_Mode',0);
    si=si.setModelParameter('FixedStep','50e-6','StopTime','300e-6','ReturnWorkspaceOutputs','on','FastRestart','off');
    out=sim(si); ts=pmlsm_get_monitor(out,'fpga'); d=double(ts.Data);
    assert(all(d(:,7:8)==0,'all') && all(d(:,12:end)==0,'all'));
    assert(all(d(1,1:8)==0),'XSI reset did not create a fresh state');
    i1=find(d(:,5)==1 & d(:,6)==1,1); i2=find(d(:,5)==2 & d(:,6)==1,1);
    assert(~isempty(i1) && ~isempty(i2),'Did not observe two active commands');
    fprintf(fid,'Run=%d first_active_time=%.12g second_active_time=%.12g first_CMP=%s second_CMP=%s\n',rep,ts.Time(i1),ts.Time(i2),mat2str(d(i1,1:3)),mat2str(d(i2,1:3)));
    for k=1:numel(ts.Time)
        fprintf(fid,'run=%d t=%.12g accepted=%d active=%d valid=%d CMP=%s\n',rep,ts.Time(k),d(k,4),d(k,5),d(k,6),mat2str(d(k,1:3)));
    end
    % Frozen observed rule: input B at 50us is used by accepted ID 1 and active ID 1.
    assert(isequal(d(i1,1:3),expected(2,:)) && isequal(d(i2,1:3),expected(2,:)),...
        'Scheduler mapping changed from NEW value');
    assert(abs(ts.Time(find(d(:,4)==1,1))-100e-6)<1e-12);
    assert(abs(ts.Time(i1)-150e-6)<1e-12 && abs(ts.Time(i2)-250e-6)<1e-12);
    clear cm;
end
fprintf(fid,['Rule: B updated at Simulink t=50us is captured by accepted_sample_id=1; active_command_id=1 and 2 both match B.\n' ...
    'The reset lasts 200ns with no prerun, so the first HDL peak occurs just AFTER the 50us data hit, not exactly coincident with it.\n' ...
    'Observed communication grid: accepted ID 1 at 100us, active ID 1 at 150us; accepted ID 2 at 200us, active ID 2 at 250us.\n' ...
    'No full-period delay inserted. Contract applies to frozen reset/clock/prerun; changing these requires revalidation.\n' ...
    'Three fresh simulations: identical NEW mapping, faults=0, range_flags=0.\nSTEP7B_TIMING_ALIGNMENT_PASS\n']);
fprintf('STEP7B_TIMING_ALIGNMENT_PASS runs=3 A_index=5 B_index=6 mapping=NEW\n');
end
function replaceSource(p,initial,final)
parent=get_param(p,'Parent'); name=get_param(p,'Name'); pos=get_param(p,'Position');
ph=get_param(p,'PortHandles'); l=get_param(ph.Outport,'Line'); dst=get_param(l,'DstPortHandle');
targets=cell(numel(dst),1);
for k=1:numel(dst), targets{k}=sprintf('%s/%d',get_param(get_param(dst(k),'Parent'),'Name'),get_param(dst(k),'PortNumber')); end
delete_line(l); delete_block(p); % in-memory objects only; no filesystem deletion or SLX save
add_block('simulink/Sources/Step',p,'Position',pos,'Time','50e-6','Before',sprintf('%.17g',initial),...
    'After',sprintf('%.17g',final),'SampleTime','50e-6');
for k=1:numel(targets), add_line(parent,[name '/1'],targets{k}); end
end
function restore(p,e,v,mp)
cd(p); setenv('PATH',e); setenv('XILINX_VIVADO',v); path(mp);
end
