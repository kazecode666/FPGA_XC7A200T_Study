function pmlsm_formalize_signal_names
% One-time, SID-based presentation migration of the current R2026b model.
% No controller, routing, port geometry, or monitor column order changes.
m='PMLSM_ThreeLoop_Simple';
assert(strcmp(version('-release'),'2026b'));
g=library.settingsLookup(); assert(g.gatePass);
if ~bdIsLoaded(m), load_system(m); end
assert(strcmp(get_param(m,'Dirty'),'off'),'Save existing edits before migration.');
blocks=find_system(m,'MatchFilter',@Simulink.match.allVariants,'Type','Block');
bh=cellfun(@(b)get_param(b,'Handle'),blocks);
pos=cellfun(@(b)get_param(b,'Position'),blocks,'UniformOutput',false);
lh=find_system(m,'FindAll','on','MatchFilter',@Simulink.match.allVariants,'Type','line');
lp=arrayfun(@(h)get_param(h,'Points'),lh,'UniformOutput',false);
% Restore the user's layout even if the toolkit reports an error.
c=onCleanup(@()restoreGeometry(bh,pos,lh,lp));
map={'S7D_Outer_Id','outer_id_ref_A';'S7D_Outer_Iq','outer_iq_ref_A'; ...
 'id_ref','fpga_id_ref_A';'iq_ref','fpga_iq_ref_A'; ...
 'id','id_A';'iq','iq_A';'ia','ia_A';'ib','ib_A';'ic','ic_A'; ...
 'v','v_mmps';'theta','theta_e_rad';'we','omega_e_radps'; ...
 'x_ref','x_ref_mm';'vdc','vdc_V';'v_cmd','host_v_ref_mmps'; ...
 'id_cmd','host_id_ref_A';'iq_cmd','host_iq_test_ref_A';'iq_mode','host_iq_test_mode'; ...
 'Close_EN','speed_loop_enable';'Pos_EN','position_loop_enable'; ...
 'vd','vd_V';'vq','vq_V'};
model_read(m,'root'); ops={};
routes=find_system(m,'SearchDepth',1,'Regexp','on','BlockType','^(From|Goto)$');
for k=1:numel(routes)
 b=routes{k}; sid=Simulink.ID.getSID(b); sid=extractAfter(sid,':');
 tag=get_param(b,'GotoTag'); i=find(strcmp(map(:,1),tag));
 if ~isempty(i), tag=map{i,2}; end
 type=get_param(b,'BlockType');
 % Duplicate readers are distinguished by their existing SID, not by a fake signal name.
 if strcmp(type,'Goto'), name=['Publish_' tag]; else, name=['Read_' tag '_' char(sid)]; end
 p=struct('Name',name,'GotoTag',tag,'ShowName','off');
 if strcmp(type,'Goto'), assert(strcmp(get_param(b,'TagVisibility'),'local')); end
 ops{end+1}=struct('op','configure','target',['blk_' char(sid)],'params',p); %#ok<AGROW>
end
ops{end+1}=struct('op','configure','target','blk_1748','params',struct('Name','Motor_Control_Monitor'));
apply(m,'root',ops);
% Formal names for the 25-column user-facing monitor; ordering is frozen.
names={'fpga_id_ref_A','fpga_iq_ref_A','id_A','iq_A','ia_A','ib_A','ic_A', ...
 'x_mm','v_mmps','theta_e_rad','omega_e_radps','cmp_u_active','cmp_v_active','cmp_w_active', ...
 'fpga_duty_u','fpga_duty_v','fpga_duty_w','accepted_sample_id','active_command_id', ...
 'active_valid','fpga_bridge_enable','fault_code','needs_reset','vd_V','vq_V'};
model_read(m,'blk_1748'); ops={};
for k=1:numel(names)
 ops{end+1}=struct('op','configure','target',sprintf('blk_%d',1755+2*(k-1)), ...
  'params',struct('Name',names{k})); %#ok<AGROW>
 ops{end+1}=struct('op','configure','target',sprintf('blk_%d',1756+2*(k-1)), ...
  'params',struct('Name',[names{k} '_double'])); %#ok<AGROW>
end
ops{end+1}=struct('op','configure','target','blk_1750', ...
 'params',struct('Name','Motor_Control_Log','VariableName','motor_control_monitor'));
apply(m,'blk_1748',ops);
model_read(m,'blk_1598');
apply(m,'blk_1598',{struct('op','configure','target','blk_1612', ...
 'params',struct('Name','FPGA_Interface_Log','VariableName','fpga_interface_monitor'))});
% Internal transport tags already name real signals; remove numeric route block names.
model_read(m,'blk_1452'); scope=Simulink.ID.getFullName([m ':1452']);
routes=find_system(scope,'SearchDepth',1,'Regexp','on','BlockType','^(From|Goto)$'); ops={};
for k=1:numel(routes)
 b=routes{k}; sid=char(extractAfter(Simulink.ID.getSID(b),':')); tag=get_param(b,'GotoTag');
 type=get_param(b,'BlockType');
 if strcmp(type,'Goto'), name=['Publish_' tag]; else, name=['Read_' tag '_' sid]; end
 ops{end+1}=struct('op','configure','target',['blk_' sid], ...
  'params',struct('Name',name,'ShowName','off')); %#ok<AGROW>
end
ports={1458,'ia_A';1461,'ib_A';1464,'ic_A';1467,'theta_e_rad';1470,'omega_e_radps'; ...
 1473,'outer_id_ref_A';1476,'outer_iq_ref_A';1479,'vdc_V';1752,'fpga_id_ref_A';1754,'fpga_iq_ref_A'};
for k=1:size(ports,1)
 ops{end+1}=struct('op','configure','target',sprintf('blk_%d',ports{k,1}), ...
  'params',struct('Name',ports{k,2})); %#ok<AGROW>
end
apply(m,'blk_1452',ops);
clear c % restore before checking / saving
for k=1:numel(bh), assert(isequal(get_param(bh(k),'Position'),pos{k})); end
% Longer formal tags must not collapse to Simulink's -T- icon.
routes=find_system(m,'SearchDepth',1,'Regexp','on','BlockType','^(From|Goto)$');
fontOps={}; compact={};
for k=1:numel(routes)
 b=routes{k}; p=get_param(b,'Position'); w=max(p(3)-p(1),8*numel(get_param(b,'GotoTag'))+35);
 if strcmp(get_param(b,'BlockType'),'From')
  ph=get_param(b,'PortHandles'); dst=get_param(get_param(ph.Outport,'Line'),'DstPortHandle');
  if numel(dst)==1 && strcmp(get_param(get_param(dst,'Parent'),'SID'),'505')
   sid=char(extractAfter(Simulink.ID.getSID(b),':'));
   fontOps{end+1}=struct('op','configure','target',['blk_' sid],'params',struct('FontSize','8')); %#ok<AGROW>
   compact{end+1}=b; %#ok<AGROW>
  end
 end
 if strcmp(get_param(b,'BlockType'),'From'), p(1)=p(3)-w; else, p(3)=p(1)+w; end
 set_param(b,'Position',p);
end
apply(m,'root',fontOps);
for k=1:numel(compact)
 b=compact{k}; p=get_param(b,'Position'); w=max(90,6*numel(get_param(b,'GotoTag'))+28);
 p(3)=490; p(1)=p(3)-w; set_param(b,'Position',p);
end
disp(model_check(m,'root','["unconnected_ports","unconnected_lines"]'));
set_param(m,'SimulationCommand','update');
save_system(m);
disp('PMLSM_FORMAL_NAMES_SAVED');
end
function apply(m,scope,ops)
r=model_edit(m,scope,jsonencode(ops),'incremental'); disp(r);
model_read(m,scope); disp(model_check(m,scope,'["unconnected_ports","unconnected_lines"]'));
% A failed/partial edit must never be silently saved.
assert(~contains(jsonencode(r),'status: partial') && ~contains(jsonencode(r),'status: error'), ...
 'Inspect toolkit edit result before continuing.');
end
function restoreGeometry(bh,pos,lh,lp)
for k=1:numel(bh)
 if ~isequal(get_param(bh(k),'Position'),pos{k}), set_param(bh(k),'Position',pos{k}); end
end
for k=1:numel(lh)
 if ~isequal(get_param(lh(k),'Points'),lp{k}), set_param(lh(k),'Points',lp{k}); end
end
end
