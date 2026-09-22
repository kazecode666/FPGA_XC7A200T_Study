function result=step7c_run_dynamic(name,reportDir)
if nargin<1, name='ideal'; end
root=fileparts(fileparts(mfilename('fullpath')));
if nargin<2, reportDir=fullfile(root,'docs','reports','step7c'); end
if ~isfolder(reportDir), mkdir(reportDir); end
result=step7c_run_scenario(name,1e-6); t=result.time; d=result.data;
% Save raw diagnostic data locally even when a gate fails; not a PASS artifact.
if nargin<2
 save(fullfile(root,'.Xil',['step7c_' name '_raw.mat']),'result');
else
 rawPath=fullfile(root,'.Xil',['step7c_' name '_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')) '_raw.mat']);
 save(rawPath,'result'); fprintf('RAW_DATA=%s\n',rawPath);
end
assert(all(isfinite(d),'all')); assert(all(result.rangeFlags==0)); assert(all(d(:,22)==0));
if strcmp(name,'stop')
    after=t>=.008+1e-6; before=find(t<.008,1,'last');
    assert(abs(d(before,9))>1 && abs(d(before,10))>1e-4,'Stop did not occur during motion');
    assert(all(d(after,20:21)==0,'all') && all(d(after,24:25)==0,'all'),'Stop retained actuation');
    assert(all(result.selected(after,4)==0));
    f=fopen(fullfile(reportDir,'dynamic_stop.txt'),'w'); c=onCleanup(@() fclose(f)); %#ok<NASGU>
    fprintf(f,'stop_time=0.008 maximum_visibility_delay=1e-6 deadtime=0\npre_stop_state=%s\nfinal_state=%s\n',mat2str(d(before,:),17),mat2str(d(end,:),17));
    fprintf(f,'post_stop_valid_max=%g bridge_max=%g abs_vdq_max=%g needs_reset_max=%g fault_max=%g\n',max(d(after,20)),max(d(after,21)),max(abs(d(after,24:25)),[],'all'),max(d(after,23)),max(d(:,22)));
    fprintf(f,'STEP7C_DYNAMIC_STOP_PASS\n'); fprintf('STEP7C_DYNAMIC_STOP_PASS\n'); return;
end
assert(all(d(:,23)==0));
assert(max(abs(d(:,10)-d(1,10)))>1e-4 && max(abs(d(:,11)))>1e-3 && max(d(:,5))-min(d(:,5))>1e-3);
assert(max(abs(result.live-d(:,[5 6 7 10 11])),[],'all')<1e-12,'Live feedback differs from plant');
assert(max(abs(result.selected-d(:,[15 16 17 21])),[],'all')<1e-12,'Selected duty/enable delayed');
assert(max(d(:,18))>=300 && max(d(:,19))>=300); assert(all(diff(d(:,18))>=0) && all(diff(d(:,19))>=0));
assert(all(d(:,19)<=d(:,18)) && max(d(:,18)-d(:,19))<=1);
pos=t>=.001 & t<.011; neg=t>=.016 & t<.026;
assert(max(d(pos,4))>=.25 && min(d(neg,4))<=-.25,'Q direction/reach failed');
assert(max(abs(d(:,3)))<.5 && max(abs(d(:,4)))<2,'Current bounds failed');
ap=accel(t,d(:,9),.003,.009); an=accel(t,d(:,9),.018,.024); assert(ap>0 && an<0);
ai=find(diff(d(:,18))>0)+1; assert(all(abs(diff(t(ai))-100e-6)<1e-12));
f=fopen(fullfile(reportDir,['dynamic_' name '.txt']),'w'); c=onCleanup(@() fclose(f)); %#ok<NASGU>
fprintf(f,'scenario=%s commTs=1e-6 plant_step=1e-6 Ts_ACR=1e-4 PI_PROFILE=0 Vdc=48 load=0\n',name);
fprintf(f,'deadtime_s=%.17g deadtime_ratio=%.17g\n',double(strcmp(name,'deadtime'))*1e-6,double(strcmp(name,'deadtime'))*.01);
fprintf(f,'columns=id_ref iq_ref id iq ia ib ic x_mm v_mmps theta_e omega_e cmp_u cmp_v cmp_w duty_u duty_v duty_w accepted_id active_id valid bridge fault needs_reset vd vq\n');
fprintf(f,'min=%s\nmax=%s\nfinal=%s\n',mat2str(min(d),17),mat2str(max(d),17),mat2str(d(end,:),17));
fprintf(f,'positive_acceleration_mm_s2=%.17g negative_acceleration_mm_s2=%.17g\n',ap,an);
fprintf(f,'q_positive_RMS=%.17g q_negative_RMS=%.17g\n',sqrt(mean((d(pos,4)-.5).^2)),sqrt(mean((d(neg,4)+.5).^2)));
fprintf(f,'LIVE_ADAPTER_EQUALS_PLANT=1 SELECTED_DUTY_DELAY_S=0 RANGE_FLAGS=%s\n',mat2str(result.rangeFlags));
fprintf(f,'STEP7C_DYNAMIC_%s_PASS\n',upper(name)); fprintf('STEP7C_DYNAMIC_%s_PASS\n',upper(name));
end
function a=accel(t,v,lo,hi)
i=find(t>=lo & t<=hi); a=mean(diff(v(i))./diff(t(i)));
end
