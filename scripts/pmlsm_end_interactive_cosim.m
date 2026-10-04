function pmlsm_end_interactive_cosim()
% End a prepared session without saving transient changes to the SLX.
s=pmlsm_interactive_cosim_state('get');
if isempty(s), return; end
if bdIsLoaded(s.model)
 try, set_param(s.model,'SimulationCommand','stop'); catch, end
 if isfield(s,'preparedChecksum') && ~isequal( ...
   Simulink.BlockDiagram.getChecksum(s.model),s.preparedChecksum)
  error('PMLSM:InteractiveModelEdited', ...
   ['The model changed after preparation. The session remains active so ' ...
    'your edits are not discarded. Resolve these edits before ending the session.']);
 end
 close_system(s.model,0);
 if s.wasLoaded
  load_system(s.model);
  if s.wasOpen, open_system(s.model); end
 end
end
cd(s.oldpwd); path(s.oldpath);
setenv('PATH',s.oldEnvPath); setenv('XILINX_VIVADO',s.oldVivado);
for k=1:numel(s.baseNames)
 name=s.baseNames{k};
 if s.baseExisted(k), assignin('base',name,s.baseValues{k});
 else, evalin('base',['clear(''' name ''')']); end
end
pmlsm_interactive_cosim_state('clear');
fprintf('Interactive co-sim ended; original directory, MATLAB path, process environment and base variables restored.\n');
end
