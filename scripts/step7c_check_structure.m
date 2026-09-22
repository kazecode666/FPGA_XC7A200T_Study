function step7c_check_structure
root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'simulink模型'));
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m)); load_system(m);
c=onCleanup(@() close_system(m,0)); %#ok<NASGU>
i=[m '/Inverter_DeadTime']; p=[m '/FPGA_HDL_Cosim'];
assert(getSimulinkBlockHandle([i '/Legacy_Counts_To_Duty'])>0,'STEP7C_MISSING_BACKEND');
fid=fopen(fullfile(root,'docs','reports','step7c','structure_after.txt'),'w'); cf=onCleanup(@() fclose(fid)); %#ok<NASGU>
assert(isempty(find_system([i '/Legacy_Counts_To_Duty'],'BlockType','Saturate')));
for k=1:3
    phase=[i '/DeadTime_Voltage_Model/Phase_' char('A'+k-1) '_DeadTime'];
    assert(getSimulinkBlockHandle([phase '/duty_norm'])<0);
    assert(getSimulinkBlockHandle([phase '/duty_active_high'])<0);
    check(phase,'d_sum',1,'duty',1,fid); check(phase,'d_sat',1,'d_sum',1,fid);
    check(phase,'v0_eff_calc',1,'d_sat',1,fid);
    assert(strcmp(get_param([phase '/d_sat'],'LowerLimit'),'0') && strcmp(get_param([phase '/d_sat'],'UpperLimit'),'1'));
    check(i,'DeadTime_Voltage_Model',k,['Backend_Duty_' num2str(k)],1,fid);
    check(i,['Backend_Duty_' num2str(k)],1,'Legacy_Counts_To_Duty',k,fid);
    check(i,['Backend_Duty_' num2str(k)],2,['fpga_duty_' char('u'+k-1)],1,fid);
    check(m,'Inverter_DeadTime',9+k,'FPGA_HDL_Cosim',k,fid);
end
check(m,'Inverter_DeadTime',13,'FPGA_HDL_Cosim',4,fid);
assert(strcmp(get_param([p '/HDL_Backend_Variant'],'Variant'),'on'));
assert(strcmp(get_param([p '/HDL_Backend_Variant/FPGA_Enabled'],'VariantControl'),'V_Backend_FPGA'));
for n={'DeadTime_Voltage_Model','PMLSM_Plant_Model'}
    assert(numel(find_system(m,'MatchFilter',@Simulink.match.allVariants,'Name',n{1}))==1);
end
fprintf(fid,['FPGA_DUTY_SOURCE=FPGA_HDL_Cosim outputs\nFPGA_TO_PWM_UPDATE_HALFTS_PATH=0\n' ...
    'FPGA_TO_LEGACY_COUNT_MAPPING_PATH=0\nONE_DEADTIME_VOLTAGE_MODEL=1\nONE_PMLSM_PLANT_MODEL=1\n' ...
    'LEGACY_PRE_DEADTIME_SATURATION=0\nSHARED_POST_DEADTIME_SATURATION=1\nSTEP7C_STRUCTURE_PASS\n']);
fprintf('STEP7C_STRUCTURE_PASS\n');
end
function check(parent,dst,dp,src,sp,fid)
ph=get_param([parent '/' dst],'PortHandles'); l=get_param(ph.Inport(dp),'Line'); assert(l>0);
h=get_param(l,'SrcPortHandle'); assert(strcmp(get_param(h,'Parent'),[parent '/' src]) && get_param(h,'PortNumber')==sp);
fprintf(fid,'%s/%s:%d -> %s/%s:%d\n',parent,src,sp,parent,dst,dp);
end
