function result=m3_rtl_stage(cfg)
% 正常/暂停/复位和两个真实负例，使用同一设计SHA和原定点位串。
command=sprintf('python "%s" --run-dir "%s"',fullfile(cfg.root,'scripts','m3_verify_rtl.py'),cfg.run_dir);
[code,console]=system(command);fprintf('%s',console);
file=fullfile(cfg.run_dir,'rtl_result.json');assert(isfile(file),'M3:RTL_RESULT_MISSING','exit%d; %s',code,console);
result=jsondecode(fileread(file));if code~=0,result.status='FAIL';end
end
