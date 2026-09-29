function s=pmlsm_prepare_interactive_cosim(varargin)
% Prepare an ordinary Simulink Run for the existing Step 7D scenario.
% All changes to the model are in memory; call pmlsm_end_interactive_cosim.
p=inputParser; addParameter(p,'backend',1,@(x)isscalar(x)&&any(x==[0 1]));
addParameter(p,'scenario','position_deadtime',@(x)ischar(x)||isstring(x));
parse(p,varargin{:});
assert(isempty(pmlsm_interactive_cosim_state('get')),'PMLSM:InteractiveActive', ...
 'End the previous session with pmlsm_end_interactive_cosim first.');
assert(strcmp(version('-release'),'2026b'),'PMLSM:Release','MATLAB R2026b is required.');
root=fileparts(fileparts(mfilename('fullpath'))); model='PMLSM_ThreeLoop_Simple';
cfg=step7d_scenarios(char(p.Results.scenario)); cfg.backend=p.Results.backend; cfg.commTs=1e-6;
s=struct('model',model,'cfg',cfg,'oldpwd',pwd,'oldpath',path, ...
 'oldEnvPath',getenv('PATH'),'oldVivado',getenv('XILINX_VIVADO'), ...
 'wasLoaded',bdIsLoaded(model),'baseNames',{{'CONTROL_BACKEND','FPGA_Cosim_Enable', ...
 'FPGA_Cosim_Input_Mode','FPGA_Reference_Mode','FPGA_Cosim_Ts_s','STEP7C_Comm_Ts_s'}}, ...
 'baseExisted',false(1,6));
s.baseValues=cell(1,6);
if s.wasLoaded, s.wasOpen=strcmp(get_param(model,'Open'),'on');
else, s.wasOpen=false; end
for k=1:numel(s.baseNames)
 name=s.baseNames{k}; s.baseExisted(k)=evalin('base',['exist(''' name ''',''var'')==1']);
 if s.baseExisted(k), s.baseValues{k}=evalin('base',name); end
end
if s.wasLoaded
 assert(strcmp(get_param(model,'Dirty'),'off'),'PMLSM:UnsavedModel', ...
  'Save the open model before preparing; its current unsaved edits cannot be safely restored.');
 loaded=strrep(get_param(model,'FileName'),'\','/');
 expected=strrep(fullfile(root,'simulink模型',[model '.slx']),'\','/');
 assert(strcmpi(loaded,expected),'PMLSM:WrongModel', ...
  'The loaded PMLSM_ThreeLoop_Simple is not the model in this repository.');
end
try
 addpath(fullfile(root,'scripts')); addpath(fullfile(root,'simulink模型'));
 if ~exist('satk_initialize','file')
  addpath(fullfile(getenv('USERPROFILE'),'.matlab','agentic-toolkits','simulink'));
 end
 satk_initialize; gate=library.settingsLookup();
 assert(gate.gatePass,'PMLSM:ToolkitGate','Simulink toolkit gate failed.');
 if cfg.backend==1
  work=fullfile(root,'.Xil','step7c_foc_cosim');
  files={'xsim.reloc','xsimk.dll','xsim.svtype','xsim.mem'};
  for k=1:numel(files)
   assert(isfile(fullfile(work,'xsim.dir','design',files{k})),'PMLSM:XsiRuntime', ...
    'Missing XSI runtime file: %s. Build the local runtime first.',files{k});
  end
  vivado='E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat';
  assert(isfile(vivado),'PMLSM:VivadoPath','Vivado 2026.1 not found.');
  hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath',vivado);
  cd(work);
 end
 load_system(model); model_read(model,'root');
 ops={}; kinds={'speed','load','pwm','reset'}; dest=[1249 941 1247 1257];
 for k=1:4
  mode='off'; if k==1, mode='on'; end
  ops{end+1}=struct('op','add_block','type','FromWorkspace', ...
   'name',['Step7D_Interactive_' kinds{k}],'ref',kinds{k}, ...
   'params',struct('VariableName',['STEP7D_' kinds{k} '_ts'], ...
    'Interpolate',mode,'SampleTime',num2str(cfg.commTs,17), ...
    'OutputAfterFinalValue','Holding final value')); %#ok<AGROW>
  ops{end+1}=struct('op','connect','target',sprintf('#%s.y1 -> blk_%d.u1',kinds{k},dest(k))); %#ok<AGROW>
 end
 result=model_edit(model,'root',jsonencode(ops),'incremental');
 assert(~contains(string(result),'"success":false'),'PMLSM:ModelEdit','Scenario connection failed: %s',string(result));
 set_param(model,'FixedStep',num2str(cfg.commTs,17),'StopTime',num2str(cfg.stopTime,17), ...
  'SignalLogging','on','SignalLoggingName','logsout','ReturnWorkspaceOutputs','on');
 inverter=find_system(model,'SearchDepth',1,'Name','Inverter_DeadTime');
 assert(numel(inverter)==1,'PMLSM:Inverter','Expected one Inverter_DeadTime subsystem.');
 for k=1:3
  duty=find_system(inverter{1},'SearchDepth',1,'Name',sprintf('Backend_Duty_%d',k));
  assert(numel(duty)==1,'PMLSM:DutySelector','Expected one backend duty selector.');
  ports=get_param(duty{1},'PortHandles');
  set_param(ports.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom', ...
   'DataLoggingName',sprintf('selected_duty_%d',k));
 end
 set_param(model,'InitFcn',[get_param(model,'InitFcn') newline 'pmlsm_interactive_cosim_init(bdroot);']);
 if cfg.backend==1
  h=find_system(model,'MatchFilter',@Simulink.match.allVariants,'Name','HDL_Cosimulation');
  assert(numel(h)==1,'PMLSM:HDLBlock','Expected one HDL_Cosimulation block.');
  set_param(h{1},'PortTimes',strrep(mat2str([-ones(1,11) cfg.commTs*ones(1,8)],17),' ',','));
 end
 pmlsm_interactive_cosim_state('set',s);
 pmlsm_interactive_cosim_init(model);
 open_system(model);
 s.preparedChecksum=Simulink.BlockDiagram.getChecksum(model);
 pmlsm_interactive_cosim_state('set',s);
 fprintf('Interactive co-sim ready: backend=%d, scenario=%s, step=1 us, stop=%.6g s. Use ordinary Run; end with pmlsm_end_interactive_cosim.\n',cfg.backend,cfg.name,cfg.stopTime);
catch err
 if bdIsLoaded(model)
  close_system(model,0);
  if s.wasLoaded, load_system(model); if s.wasOpen, open_system(model); end, end
 end
 cd(s.oldpwd); path(s.oldpath); setenv('PATH',s.oldEnvPath); setenv('XILINX_VIVADO',s.oldVivado);
 for k=1:numel(s.baseNames)
  name=s.baseNames{k};
  if s.baseExisted(k), assignin('base',name,s.baseValues{k});
  else, evalin('base',['clear(''' name ''')']); end
 end
 pmlsm_interactive_cosim_state('clear');
 rethrow(err);
end
end
