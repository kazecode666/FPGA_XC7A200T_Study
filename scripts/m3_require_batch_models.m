function m3_require_batch_models(cfg)
% 模型开发入口仅允许独立-batch，避免覆盖用户交互工作区或同名未保存模型。
assert(batchStartupOptionUsed,'M3:INDEPENDENT_SESSION_REQUIRED', ...
    'Use a separate MATLAB -batch process for M3; preserve the interactive session.');
owned={cfg.model,'PMLSM_PI_FOC_Float_Baseline',['gm_' cfg.model],['gm_' cfg.model '_vnl']};
for k=1:numel(owned)
    assert(~bdIsLoaded(owned{k}),'M3:MODEL_ALREADY_LOADED', ...
        'Refuse to replace/close an already loaded %s.',owned{k});
end
end
