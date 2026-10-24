function result=m3_extract_recorded_inputs(recording,destination)
% 一次性导出已记录的完整零初态前缀；后续测试仅依赖紧凑hex文件。
assert(~isfile(destination),'M3:EVIDENCE_EXISTS','Preserve existing %s.',destination);
a=load(recording,'out','metadata');names={'ia','ib','ic','theta_e','omega_e','iq_ref','id_ref','PI_Reset_EN','Vdc_V'};
N=1536;Ts=1e-4;time=(0:N-1)'*Ts;
fixed=evalin('base','FOC_Fixed_Config');keys={'Current','Current','Current','Angle','Omega','Current','Current','Reset','Bus'};
t=table((0:N-1)','VariableNames',{'sample_id'});
for k=1:9
    v=a.out.logsout.get(['in_' names{k}]).Values;
    if numel(v.Time)==1
        assert(k==9,'M3:REPLAY_MISSING','Only bus may be recorded once.');data=repmat(v.Data,N,1);
    else
        assert(numel(v.Time)>=N&&max(abs(v.Time(1:N)-time))<1e-10,'M3:REPLAY_PREFIX','Replay must begin at time zero with all preceding samples.');data=v.Data(1:N);
    end
    if k==8,t.(names{k})=string(uint8(logical(data)));else,t.(names{k})=string(hex(fi(data(:),fixed.Types.(keys{k}),fixed.Fimath)));end
end
assert(any(t.iq_ref~="00000000")||any(t.id_ref~="00000000"),'M3:REPLAY_IDLE','Replay must include actual nonzero references.');
writetable(t,destination);
result=struct('source_recording',recording,'destination',destination,'frames',N,'first_time_s',0,'last_time_s',time(end), ...
    'prefix_preserved',true,'initial_state','original recording starts at zero; source/gm rerun also zero', ...
    'input_encoding','hex(fi) at accepted <=40bit input types; no output/state conversion', ...
    'metadata',a.metadata);
fid=fopen([destination '.json'],'w');fprintf(fid,'%s',jsonencode(result,PrettyPrint=true));fclose(fid);
end
