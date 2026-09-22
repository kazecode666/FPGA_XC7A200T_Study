function step7d_record_start(m,cfg)
global STEP7D_RUN_LISTENERS STEP7D_RUN_EVENTS STEP7D_RUN_EFFECTIVE
STEP7D_RUN_EFFECTIVE=step7d_check_start(m,cfg);
STEP7D_RUN_EVENTS=struct('current',[],'speed',[],'position',[]);
STEP7D_RUN_LISTENERS=cell(1,3); sids=[759 1163 1118]; names={'current','speed','position'};
for k=1:3
 b=Simulink.ID.getFullName(sprintf('%s:%d',m,sids(k))); key=names{k};
 STEP7D_RUN_LISTENERS{k}=add_exec_event_listener(b,'PostOutputs',@(blk,ev)record(key,blk.CurrentTime));
end
end
function record(name,t)
global STEP7D_RUN_EVENTS
STEP7D_RUN_EVENTS.(name)(end+1,1)=t;
end
