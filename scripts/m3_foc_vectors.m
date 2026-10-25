function cases=m3_foc_vectors
% 固定seed的紧凑边界/连续序列；非物理不平衡组合明确标注。
all=m2_foc_vectors;u=all(1:1024,:);
% Keep six sector boundaries, then deliberate limiter/reset/bus cases.
u(901:940,1:3)=0;u(901:920,6:7)=2;u(921:940,6:7)=0;
u(941:944,8)=[1;0;1;1];u(945:960,8)=0;
u(961:976,9)=12;u(977:992,9)=24;u(993:1024,9)=60;
u(1,8)=1;
cases=struct('name','boundary_random','u',u,'seed',20261024, ...
    'samples',1024,'sample_s',1e-4,'nonphysical_unbalanced_vectors',true);
root=fileparts(fileparts(mfilename('fullpath')));
replay=fullfile(root,'verification','m3_foc','vectors','actual_prefix_inputs.csv');
if isfile(replay)
    names={'ia','ib','ic','theta_e','omega_e','iq_ref','id_ref','PI_Reset_EN','Vdc_V'};
    opts=detectImportOptions(replay,'VariableNamingRule','preserve');
    opts=setvartype(opts,names,'string');t=readtable(replay,opts);
    assert(isequal(t.sample_id,(0:height(t)-1)'),'M3:REPLAY_PREFIX');
    widths=[32 32 32 40 40 32 32 1 32];frac=[24 24 24 32 24 24 24 0 24];
    signed=[true true true true true true true false false];
    v=zeros(height(t),9);
    for k=1:9
        % Only <=40bit INPUT words use exact binary64 decoding; never 64/72bit states.
        raw=hex2dec(string(t.(names{k})));
        if signed(k),negative=raw>=2^(widths(k)-1);raw(negative)=raw(negative)-2^widths(k);end
        v(:,k)=raw*2^-frac(k);
    end
    cases(2)=struct('name','actual_prefix','u',v,'seed',20261024, ...
        'samples',height(t),'sample_s',1e-4,'nonphysical_unbalanced_vectors',false);
end
end
