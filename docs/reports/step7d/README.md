# Step 7D execution evidence

**Revised Step7D full acceptance passed:** `acceptance_20260922_205317_302/acceptance.txt`
records all 21 fresh gates and `STEP7D_FULL_ACCEPTANCE_PASS`, testing source
commit `dc236d2`. PR33 remains open for ChatGPT Review. See
`../../../coordination/reports/step7d_pr33_revision_report.md` for results and limits.

Historical run: Tasks 1–3 passed; Task 4 `speed_ideal` passed and `speed_deadtime` failed. That run stopped before Tasks 5–8.

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

Local raw output `.Xil/step7d/<RUN_ID>/` is not committed. Archived-evidence verifiers require those local artifacts and intentionally fail if they are missing. New revised-profile individual runs in `pr33_revision_20260922/` cover all speed/position cases, limits/reset, stop inhibition, fresh startup, convergence and scoped regressions. Their results are distinct from the historical blocker and from the final aggregate acceptance.

## Full ordered acceptance

After the R2026b/Toolkit initialization above, run:

```matlab
baselineDir=fullfile(pwd,'.Xil','step7d','20260922_113014_967');
reportDir=step7d_acceptance(baselineDir);
step7d_report_descriptive_metrics(reportDir);
```

The baseline directory is the retained **pre-modification Task1** data. It must
contain the original native equivalence files and matched-step comparison files;
see `task1_baseline_20260922_04/baseline_before.txt`. A fresh checkout does not
include these MAT files: restore the original baseline artifacts before claiming
before/after equivalence. Do not create a new post-modification baseline and
label it as the original.

Acceptance creates its own `acceptance_<run ID>` directory, rebuilds XSI, runs
the required ordered checks and writes `STEP7D_FULL_ACCEPTANCE_PASS` only after
all 21 report gates. Its model hash only records/protects the input file; actual
numerical, structural and HDL checks determine acceptance. Failures retain
`failure.txt` and raw output; fix a diagnosed harness problem or report a taskbook
stop condition, then use a new run directory. Do not reuse partial reports.

The independent session must not already have `PMLSM_ThreeLoop_Simple` loaded;
the runner refuses that condition. Another idle desktop is allowed. Avoid saving
new edits to the SLX while a run is using it. Current revision runs use the latest
saved local SLX including pre-existing layout edits; that dirty model is preserved
and not included in this revision's commits. The reported model hash identifies
this local artifact and does not establish clean-checkout binary equivalence.

Public trajectory fields use seconds, mm, mm/s, A, rad, rad/s, and N. Adapter
inputs use ia/ib/ic/id_ref/iq_ref in A, theta_e in rad and we in rad/s;
quantized reference values are decoded A after Q15 conversion. The original
speed PI integrator is in A, bounded at +/-0.5 A; iq output is bounded at +/-1 A.
Performance trajectories are on the 100 us grid, controller execution events
retain their own timestamps, and peaks come from full-rate output. Descriptive
metrics record full-rate trajectory errors/peaks and the speed-task limit ratio.
Recovery uses a stated 0.5 mm/s band until the next request/load event, even for
deadtime; it is descriptive, not an additional acceptance gate.
