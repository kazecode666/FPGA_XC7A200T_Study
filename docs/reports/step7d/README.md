# Step 7D partial implementation and blocked result

Tasks 1–3 passed. Task 4 `speed_ideal` passed, `speed_deadtime` failed. Tasks 5–8 have not run. This directory is not a full Step 7D acceptance bundle.

The paragraph above describes the original pre-revision run. The binding follow-up is
`coordination/tasks/step7d_pr33_revision.md`: AUM3-S4 profile0 now uses Kp=8.725,
Ki=11850 (KiTs=1.185), and subsequent deadtime speed MAE/RMSE limits are 1.5 mm/s.
Old reports and their saved 0.5 mm/s limits remain historical evidence.

Use R2026b Prerelease Update 3 and the installed Vivado 2026.1. This project has
an independent `matlab_r2026b` server in `.codex/config.toml`; the global `matlab`
server remains R2026a. Reload the project/session to expose the new named tools
in Codex. The project server was also verified directly over MCP stdio using
its exact configured command and arguments (see `pr33_revision_20260922/mcp_contracts_build.txt`).
An open MATLAB desktop alone is not a reason to close it: use the independent
new session and load the latest saved SLX. Do not share an unsaved in-memory model.
Before model access, initialize the already installed Toolkit in that R2026b session:

```matlab
cd('D:/Project/FPGA_XC7A200T');
assert(strcmp(version('-release'),'2026b'));
disp(matlabroot);
addpath('C:/Users/lww/.matlab/agentic-toolkits/simulink');
satk_initialize;
which model_read -all
which model_edit -all
which model_check -all
assert(~isempty(which('model_read')) && ~isempty(which('model_edit')) && ~isempty(which('model_check')));
gate=library.settingsLookup(); assert(gate.gatePass);
addpath(fullfile(pwd,'scripts'));
step7c_generate_foc_cosim(1e-6,true); % rebuild after the authorized profile correction
runid=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
reportDir=fullfile(pwd,'docs','reports','step7d',['reproduce_' runid]);
step7d_run_scenario('speed_deadtime',1,1e-6,reportDir);
% New-profile result must come from this fresh run, not the historical blocker.
```

The runner configures the original model only in memory, restores its own cwd/path/process environment, and saves full simulation output before evaluating numerical gates. Use a new report directory for each run. Saved SLX default is legacy. Do not rerun the one-time `step7d_connect_outer_refs` constructor on an integrated model.

For read-only reproduction of the saved blocker (does not run HDL):

```matlab
step7d_verify_blocker;
```

Key evidence:

- `task1_baseline_20260922_04/`: untouched-controller legacy native/matched baselines. MAT files remain at the local RAW_DIR recorded in the report.
- `task3_live_source/`, `task3_verified/`, `task3_legacy_after/`: actual selected reference source, full-rate canary comparison, real scheduling and <=1e-10 native legacy equivalence.
- `task4_speed_ideal/`: full successful speed case.
- `task4_speed_deadtime/`: original failure, actual configuration, diagnostic metrics and waveform. `DIAGNOSTIC_ONLY=1` explicitly denotes a failed case; the reporting utility does not change the gate.
- `../../../coordination/reports/step7d_codex_report.md`: scope, complete status and diagnostic limitations.

Local raw output `.Xil/step7d/<RUN_ID>/` is not committed. A fresh checkout can recreate it through the runner; archived-evidence verifiers require those local artifacts and intentionally fail if they are missing. The scenario runner accepts all taskbook names, but only the completed cases above have been executed; availability of an option is not acceptance of its stage.
