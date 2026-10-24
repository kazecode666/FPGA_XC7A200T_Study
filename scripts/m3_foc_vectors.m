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
end
