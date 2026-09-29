function value=pmlsm_interactive_cosim_state(action,value)
% Process-local state for a prepared, unsaved interactive co-sim session.
persistent session
if nargin<2, value=[]; end
switch action
 case 'get', value=session;
 case 'set', session=value;
 case 'clear', session=[]; value=[];
 otherwise, error('PMLSM:InteractiveState','Unknown state action.');
end
end
