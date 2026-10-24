function result=m3_export_source_trace(cfg,modelFolder,u,label)
% 同一原定点源；hex(fi)保留32/64位全部低位，无double中转。
m=cfg.model;load_system(fullfile(modelFolder,[m '.slx']));
assert(strcmpi(get_param(m,'FileName'),fullfile(modelFolder,[m '.slx'])));
out=m2_run_foc_sequence(m,u,true);save(fullfile(cfg.run_dir,[label '_source.mat']),'out','u','-v7.3');
names={'duty_u','duty_v','duty_w','x_d','x_q','du_d_z','du_q_z'};
trace=table((0:size(u,1)-1)','VariableNames',{'sample_id'});
for k=1:numel(names)
    v=out.logsout.get(names{k}).Values;
    assert(isfi(v.Data),'M3:LOSSY_LOG_TYPE','%s must be logged as fi, got%s.',names{k},class(v.Data));
    trace.(names{k})=string(hex(v.Data(:)));
end
writetable(trace,fullfile(cfg.run_dir,[label '_source_hex.csv']));
expected=trace.duty_u(1);flipped=char(expected);digits='0123456789abcdef';
at=find(digits==lower(flipped(end)),1)-1;flipped(end)=digits(double(bitxor(uint8(at),uint8(1)))+1);
rejected=false;try,m3_compare_bits(expected,string(flipped));catch exception,rejected=strcmp(exception.identifier,'M3:BIT_MISMATCH');end
assert(rejected,'M3:NEGATIVE_FALSE_PASS','Actual expected output LSB flip was not rejected.');
result=struct('samples',size(u,1),'raw_bits','hex(fi); leading zeros retained', ...
    'actual_expected_duty',expected,'flipped_expected_duty',string(flipped), ...
    'negative_bit_flip_rejected',rejected,'csv',[label '_source_hex.csv']);
close_system(m,0);
end
