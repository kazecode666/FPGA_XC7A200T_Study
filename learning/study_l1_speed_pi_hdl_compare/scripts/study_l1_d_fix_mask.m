function study_l1_d_fix_mask(w)
top='study_l1_system_cosim_top'; mdl=['hdlverifier_wizard_' top]; load_system(fullfile(w,[mdl '.slx']));
b=find_system(mdl,'SearchDepth',1,'ReferenceBlock','vivadosimlib/HDL Cosimulation'); assert(numel(b)==1); b=b{1};
[ins,outs,iw,ow,os,of]=study_l1_d_ports; ports=[ins outs];
ud=get_param(b,'UserData'); oldPaths=strsplit(get_param(b,'PortPaths'),';'); oldPaths=oldPaths(~cellfun(@isempty,oldPaths));
oldNames=cellfun(@(p)extractAfter(p,['/' top '/']),oldPaths,'UniformOutput',false);
assert(numel(oldNames)==numel(ud.HdlSigInfo)); oldInfo=ud.HdlSigInfo; newInfo=repmat(oldInfo(1),numel(ports),1);
for k=1:numel(ports)
 j=find(strcmp(oldNames,ports{k}));
 if isempty(j)
  assert(any(strcmp(ports{k},{'pi_reset','speed_pi_reset'})),'Unexpected missing data port');
  newInfo(k)=oldInfo(1); % Identical one-bit Verilog input descriptor.
 else, assert(numel(j)==1); newInfo(k)=oldInfo(j); end
end
ud.HdlSigInfo=newInfo; set_param(b,'UserData',ud,'UserDataPersistent','on');
paths=strjoin(cellfun(@(n)['/' top '/' n],ports,'UniformOutput',false),';');
set_param(b,'PortPaths',[paths ';'],'PortModes',mat2str([ones(1,numel(ins)) 2*ones(1,numel(outs))]), ...
 'PortTimes',csv([-ones(1,numel(ins)) 1e-6*ones(1,numel(outs))]),'PortSigns',csv([-ones(1,numel(ins)) os]), ...
 'PortFracLengths',csv([zeros(1,numel(ins)) of]),'PortWordLengths',csv([-ones(1,numel(ins)) ow]), ...
 'PortHDLWordSizes',csv([iw ow]),'ClockPaths',['/' top '/clk;/' top '/reset_n;'], ...
 'ClockModes','[2 4]','ClockTimes','[2e-8 2e-7]','PreRunTime','0');
save_system(mdl); close_system(mdl,0);
study=fileparts(fileparts(mfilename('fullpath'))); root=fileparts(fileparts(study));
copyfile(fullfile(root,'motor_control_ip','foc','rom','sin_qw_4096x18.mem'),fullfile(w,'hdlverifier_wizard_project','wizprj.sim','sim_1','behav','xsim'));
fprintf('D_XSI_MASK_PASS data_inputs=%d outputs=%d\n',numel(ins),numel(outs));
end
function s=csv(v), s=strrep(mat2str(v,17),' ',','); end
