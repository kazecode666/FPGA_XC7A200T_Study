function step7d_connect_outer_refs
% One-time minimal wiring; baseline f6e4e50 must already be committed.
root=fileparts(fileparts(mfilename('fullpath'))); cd(root); addpath(fullfile(root,'simulink模型'));
assert(strcmp(version('-release'),'2026b')); gate=library.settingsLookup(); assert(gate.gatePass);
m='PMLSM_ThreeLoop_Simple'; assert(~bdIsLoaded(m)); open_system(m); c=onCleanup(@()close_system(m,0)); %#ok<NASGU>
task=Simulink.ID.getFullName([m ':505']); assert(numel(get_param(task,'PortHandles').Outport)==3,'Already integrated');
scopes={task,m}; old=cell(2,2);
for k=1:2
 b=find_system(scopes{k},'SearchDepth',1,'Type','Block'); b(strcmp(b,scopes{k}))=[];
 old{k,1}=b; old{k,2}=cellfun(@(s)get_param(s,'Position'),b,'UniformOutput',false);
end
model_read(m,'blk_505');
ops={struct('op','add_block','type','Outport','name','outer_id_ref','ref','id','params',struct('Port','4')), ...
 struct('op','connect','target','blk_991.y1 -> #id.u1'), ...
 struct('op','add_block','type','Outport','name','outer_iq_ref','ref','iq','params',struct('Port','5')), ...
 struct('op','connect','target','blk_991.y2 -> #iq.u1')};
disp(model_edit(m,'blk_505',jsonencode(ops),'incremental')); model_read(m,'blk_505'); disp(model_check(m,'blk_505','["unconnected_ports","unconnected_lines"]'));
model_read(m,'root');
ops={struct('op','add_block','type','Goto','name','Step7D_Outer_Id','ref','gid','params',struct('GotoTag','S7D_Outer_Id','TagVisibility','local')), ...
 struct('op','connect','target','blk_505.y4 -> #gid.u1'), ...
 struct('op','add_block','type','Goto','name','Step7D_Outer_Iq','ref','giq','params',struct('GotoTag','S7D_Outer_Iq','TagVisibility','local')), ...
 struct('op','connect','target','blk_505.y5 -> #giq.u1'), ...
 struct('op','configure','target','blk_1472','params',struct('GotoTag','S7D_Outer_Id')), ...
 struct('op','configure','target','blk_1475','params',struct('GotoTag','S7D_Outer_Iq'))};
disp(model_edit(m,'root',jsonencode(ops),'incremental')); model_read(m,'root'); disp(model_check(m,'root','["unconnected_ports","unconnected_lines"]'));
for k=1:2
 for j=1:numel(old{k,1}), set_param(old{k,1}{j},'Position',old{k,2}{j}); end
end
for n={'Step7D_Outer_Id','Step7D_Outer_Iq'}
 b=find_system(m,'SearchDepth',1,'Name',n{1}); ph=get_param(b{1},'PortHandles'); h=get_param(get_param(ph.Inport,'Line'),'SrcPortHandle'); xy=get_param(h,'Position');
 set_param(b{1},'Position',[xy(1)+30 xy(2)-10 xy(1)+170 xy(2)+10],'ShowName','off','AttributesFormatString','');
end
% Preserve existing port block dimensions/shapes. New outports stay library default.
save_system(m); disp('STEP7D_MINIMAL_OUTER_WIRING_SAVED');
end
