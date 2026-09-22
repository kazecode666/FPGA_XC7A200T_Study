# Step 7D status: Task 1 baseline in progress

No Step7D integration or full acceptance is available yet. The user clarified Host versus outer-loop responsibilities after the topology mismatch was reported; Task 1 has resumed without saved model changes. See `coordination/reports/step7d_preflight_blocker.md` for the original source finding and clarified architecture.

Fresh R2026b evidence is in `task1_20260922_source_audit/`. The source audit did not simulate, call HDL setup or save the model. It intentionally failed because the existing FPGA live iq input resolves to Host test current rather than the selected speed-loop output.

Reproduce from the project root in a fresh R2026b session, with the model closed:

```matlab
addpath('scripts');
step7d_audit_outer_interface;
```

This creates a new timestamped audit directory and throws `Step7D:LiveReferenceSourceMismatch` on the original topology. It is a diagnostic of that topology, not a general future connectivity evaluator or the full Step7D runner. Historical Step7C evidence remains untouched.

Scenarios and windows were committed in `c45420a` before baseline performance was observed. Run the Task 1 capture in a fresh R2026b batch/session with the model closed and a new output directory:

```matlab
step7d_test_scenarios;
step7d_capture_baseline(fullfile(pwd,'docs','reports','step7d','my_new_baseline_run'));
```

The baseline runner adds temporary high-level speed/load sources, logs native outputs and actual execution callbacks, and closes without saving. It uses backend 0 from the repository root, without HDL setup. The native 50 us cases are for legacy equivalence; matched 1 us cases are tested against the frozen performance windows. Raw data paths are recorded in each run's `baseline_before.txt`; full-rate peaks are computed before retaining common-grid data. Failure stops capture and retains diagnostics. Successful capture is not full Step7D acceptance.
