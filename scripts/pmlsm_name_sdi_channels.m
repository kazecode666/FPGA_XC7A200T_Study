function pmlsm_name_sdi_channels
% Give SDI individual, readable channels while retaining the two vector logs.
% Run in an independent R2026b session with this repository as the cwd.
root=fileparts(fileparts(mfilename('fullpath')));
assert(strcmp(version('-release'),'2026b'));
assert(strcmp(pwd,root));
assert(library.settingsLookup().gatePass);
m='PMLSM_ThreeLoop_Simple';
file=fullfile(root,'simulink模型',[m '.slx']);
original=readBytes(file);
addpath(fullfile(root,'simulink模型'));
assert(~bdIsLoaded(m),'The model is already loaded in this MATLAB session.');
load_system(m);
closeModel=onCleanup(@()close_system(m,0)); %#ok<NASGU>
assert(strcmp(get_param(m,'Dirty'),'off'));
model_read(m,'blk_1748'); model_read(m,'blk_1598'); model_read(m,'blk_1453');

motor={'fpga_id_ref_A','fpga_iq_ref_A','id_A','iq_A','ia_A','ib_A','ic_A', ...
 'x_mm','v_mmps','theta_e_rad','omega_e_radps','cmp_u_active','cmp_v_active', ...
 'cmp_w_active','fpga_duty_u','fpga_duty_v','fpga_duty_w', ...
 'accepted_sample_id','active_command_id','active_valid','fpga_bridge_enable', ...
 'fault_code','needs_reset','vd_V','vq_V'};
assert(numel(motor)==25);
for k=1:numel(motor)
 sid=1756+2*(k-1); % double converter feeding the fixed monitor Mux column k
 b=Simulink.ID.getFullName(sprintf('%s:%d',m,sid));
 assert(strcmp(get_param(b,'BlockType'),'DataTypeConversion'));
 logOutput(b,['motor_' motor{k}]);
end

interface={'cmp_u_active','cmp_v_active','cmp_w_active', ...
 'accepted_sample_id','active_command_id','active_valid','needs_reset', ...
 'fault_code','raw_duty_u','raw_duty_v','raw_duty_w'};
for k=1:numel(interface)
 b=Simulink.ID.getFullName(sprintf('%s:%d',m,1599+k));
 assert(strcmp(get_param(b,'BlockType'),'Inport'));
 logOutput(b,['fpga_if_' interface{k}]);
end

% The last eleven columns of fpga_interface_monitor are range flags.
% Log at their individual source blocks so SDI shows names, not vector indices.
flagNames={'run_enable','ia','ib','ic','theta_e','we', ...
 'id_ref','iq_ref','vdc','pi_reset','uq_zero_en'};
flagSids=[1493 1500 1507 1514 1522 1529 1536 1543 1550 1557 1563];
for k=1:numel(flagNames)
 b=Simulink.ID.getFullName(sprintf('%s:%d',m,flagSids(k)));
 assert(strcmp(get_param(b,'Name'),['Range_' flagNames{k}]));
 logOutput(b,['fpga_if_range_' flagNames{k}]);
end

assert(isequal(original,readBytes(file)),'The saved SLX changed during this edit.');
for scope={'root','blk_1748','blk_1598','blk_1453'}
 result=model_check(m,scope{1},'["unconnected_ports","unconnected_lines"]');
 assert(contains(result,'status: healthy'));
end
% The saved model's default solver step remains 50 us; a separate scenario
% runner provides the 1 us override required by FPGA/XSI simulation.
save_system(m);
fprintf('SDI_NAMED_CHANNELS=%d\n',numel(motor)+numel(interface)+numel(flagNames));
end

function logOutput(b,name)
p=get_param(b,'PortHandles'); assert(numel(p.Outport)==1);
h=p.Outport(1);
assert(get_param(h,'Line')>0);
% Signal logging is a port property; the installed model_edit toolkit has
% block-level configure targets, so apply this property to the exact SID port.
set_param(h,'DataLogging','on','DataLoggingNameMode','Custom', ...
 'DataLoggingName',name,'DataLoggingLimitDataPoints','off');
assert(strcmp(get_param(h,'DataLoggingName'),name));
end

function b=readBytes(file)
f=fopen(file,'rb'); assert(f>0); c=onCleanup(@()fclose(f)); %#ok<NASGU>
b=fread(f,Inf,'*uint8');
end
