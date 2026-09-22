# Step 7D partial implementation and blocked result

Tasks 1–3 passed. Task 4 `speed_ideal` passed, `speed_deadtime` failed. Tasks 5–8 have not run. This directory is not a full Step 7D acceptance bundle.

Use R2026b Prerelease Update 3 and the installed Vivado 2026.1. Save and close the model before running. In a fresh MATLAB session:

```matlab
cd('D:/Project/FPGA_XC7A200T');
addpath(fullfile(pwd,'scripts'));
step7c_generate_foc_cosim(1e-6,true); % local runtime only, frozen RTL
runid=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
reportDir=fullfile(pwd,'docs','reports','step7d',['reproduce_' runid]);
step7d_run_scenario('speed_deadtime',1,1e-6,reportDir);
% Expected current result: Step7D:SpeedPerformance, first window RMSE ~1.103 mm/s.
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
