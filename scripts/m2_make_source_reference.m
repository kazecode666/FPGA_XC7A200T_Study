function model=m2_make_source_reference(modelFolder)
% 临时同拍参考：复制原实际FOC，不改公式、不保存源SLX。
source='PMLSM_PI_FOC_Float_Baseline';assert(nargin==1,'M2:TEST_COPY_REQUIRED','明确传入隔离的验收模型目录。');load_system(fullfile(modelFolder,[source '.slx']));model=sprintf('M2_Source_%d',matlabProcessID);new_system(model);load_system(model);set_param(model,'SolverType','Fixed-step','Solver','FixedStepDiscrete','FixedStep','Ts_ACR','SignalLogging','on','ReturnWorkspaceOutputs','on');dut=[model '/FOC_DUT'];add_block(Simulink.ID.getFullName([source ':546']),dut,'TreatAsAtomicUnit','on');
for k=1:9,b=add_block('built-in/Inport',sprintf('%s/In%d',model,k),'Port',num2str(k),'SampleTime','Ts_ACR');p=get_param(b,'PortHandles');if k<=8,q=get_param(dut,'PortHandles');if k==8,set_param(b,'OutDataTypeStr','boolean');end;add_line(model,p.Outport,q.Inport(k));else,t=add_block('built-in/Terminator',[model '/Bus48_Parameter_Reference']);q=get_param(t,'PortHandles');add_line(model,p.Outport,q.Inport);end;end
for k=1:3,b=add_block('built-in/Outport',sprintf('%s/Out%d',model,k),'Port',num2str(k));p=get_param(dut,'PortHandles');q=get_param(b,'PortHandles');add_line(model,p.Outport(k),q.Inport);end
end
