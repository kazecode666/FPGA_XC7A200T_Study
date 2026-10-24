function paths=m2_bind_test_models(folder)
% 名称相同也不依赖path优先级；明确加载并验证本场景两份SLX。
paths=struct;for name={'PMLSM_FOC_FixedPoint','PMLSM_PI_FOC_Float_Baseline'}
 expected=fullfile(folder,[name{1} '.slx']);if ~bdIsLoaded(name{1}),load_system(expected);end
 actual=get_param(name{1},'FileName');assert(strcmpi(actual,expected),'M2:ISOLATION_PATH','%s实际路径%s不是本场景副本%s。',name{1},actual,expected);paths.(name{1})=actual;
end
fid=fopen(fullfile(folder,'loaded_paths.json'),'w');fprintf(fid,'%s',jsonencode(paths,PrettyPrint=true));fclose(fid);
end
