function evidence=m1a_check_transforms(model)
% Threshold frozen before first execution: 1e-4 A at <=2 A input magnitude,
% covering the 1024-interval sine/cosine interpolation and two transformations.
values=get_param(Simulink.ID.getFullName([model ':617']),'MaskValues');
assert(strcmp(values{end},'1024'));
values=get_param(Simulink.ID.getFullName([model ':590']),'MaskValues');
assert(strcmp(values{end},'1024'));
limit=1e-4;h=sprintf('M1A_Transform_%d',matlabProcessID);new_system(h);
cleanup=onCleanup(@()close_system(h,0));
for item={553,'Clarke';617,'Park';590,'Inverse'}'
    add_block(Simulink.ID.getFullName(sprintf('%s:%d',model,item{1})),[h '/' item{2}]);
end
angles=[0 pi/6 pi/3 pi/2 pi 3*pi/2 2*pi-1e-6 2*pi+pi/6];
phases=[1 -.5 -.5;-.25 .75 -.5;0 1 -1;1 1 1];
vectors=[];
for k=1:numel(angles),vectors=[vectors;phases repmat(angles(k),4,1)];end %#ok<AGROW>
time=(0:size(vectors,1)-1)'*1e-4;w=get_param(h,'ModelWorkspace');
for k=1:4
    name=sprintf('vector%d',k);w.assignin(name,timeseries(vectors(:,k),time));
    add_block('simulink/Sources/From Workspace',[h '/' name], ...
        'VariableName',name,'SampleTime','1e-4','Interpolate','off','OutputAfterFinalValue','Holding final value');
end
for k=1:3,connect(h,sprintf('vector%d',k),1,'Clarke',k);end
connect(h,'Clarke',1,'Park',1);connect(h,'Clarke',2,'Park',2);connect(h,'vector4',1,'Park',3);
connect(h,'Park',1,'Inverse',1);connect(h,'Park',2,'Inverse',2);connect(h,'vector4',1,'Inverse',3);
sources={'Clarke',1;'Clarke',2;'Park',1;'Park',2;'Inverse',1;'Inverse',2};
for k=1:6
    name=sprintf('out%d',k);add_block('simulink/Sinks/Out1',[h '/' name],'Port',num2str(k));
    connect(h,sources{k,1},sources{k,2},name,1);
end
set_param(h,'Solver','FixedStepDiscrete','FixedStep','1e-4','StopTime',num2str(time(end),17), ...
    'SaveOutput','on','OutputSaveName','yout','SaveFormat','Dataset','ReturnWorkspaceOutputs','on');
data=sim(Simulink.SimulationInput(h));actual=zeros(size(vectors,1),6);
for k=1:6,actual(:,k)=data.yout.getElement(k).Values.Data;end
alpha=(2*vectors(:,1)-vectors(:,2)-vectors(:,3))/3;
beta=(vectors(:,2)-vectors(:,3))/sqrt(3);theta=vectors(:,4);
d=alpha.*cos(theta)+beta.*sin(theta);q=-alpha.*sin(theta)+beta.*cos(theta);
expected=[alpha beta d q alpha beta];errors=max(abs(actual-expected),[],1);
disp(errors);assert(all(errors<limit),'M1A:TRANSFORM','Actual Clarke/Park/inverse reconstruction failed.');
evidence=struct('pass',true,'points',size(vectors,1),'threshold_A',limit, ...
    'max_abs_A',errors,'source_SIDs',[553 617 590],'configured_lookup_points',1024);
root=fileparts(fileparts(mfilename('fullpath')));
folder=fullfile(root,'docs','reports','m1a_float_baseline');
output=array2table([vectors actual expected actual-expected], 'VariableNames', ...
    {'ia_A','ib_A','ic_A','theta_rad','alpha_A','beta_A','d_A','q_A','roundtrip_alpha_A','roundtrip_beta_A', ...
    'expected_alpha_A','expected_beta_A','expected_d_A','expected_q_A','expected_roundtrip_alpha_A','expected_roundtrip_beta_A', ...
    'error_alpha_A','error_beta_A','error_d_A','error_q_A','error_roundtrip_alpha_A','error_roundtrip_beta_A'});
writetable(output,fullfile(folder,'transform_vectors.csv'));
fid=fopen(fullfile(folder,'transform_acceptance.json'),'w');
fprintf(fid,'%s',jsonencode(evidence,PrettyPrint=true));fclose(fid);
fprintf('M1A_TRANSFORM_PASS\n');
end
function connect(h,a,ap,b,bp)
src=get_param([h '/' a],'PortHandles');dst=get_param([h '/' b],'PortHandles');
add_line(h,src.Outport(ap),dst.Inport(bp),'autorouting','on');
end
