# Step 7D Task 1 blocker: live iq_cmd is a Host test command

Date: 2026-09-22. Status: **Historical Task 1 topology finding, resolved by user clarification and verified minimal wiring. Tasks 1–3 complete. Current Task 4 performance blocker is documented in `step7d_codex_report.md`.**

The user clarified that Simple_Host is the upper-computer request source: iq_test_ref is for open-outer-loop current tests; three-loop control must use position reference. This resolves the architectural decision below: preserve Host test-command semantics and later expose the existing selected outer references through minimal wiring. Baselines and their gates must precede that wiring. The original source audit remains an expected failure on the unchanged model.

Resolution evidence: baseline commit `f6e4e50` preceded wiring commit `41a1b4a`. Reference_Manager outputs 1/2 are exported through new Control_Task outports 4/5 and local tags S7D_Outer_Id/Iq. The original Host test tags retain their meaning. `docs/reports/step7d/task3_verified/` proves real live input and full-rate canary equality, 100 us accepted periods and 50 us accepted-to-active delay. `task3_legacy_after/` proves all native baseline signals and outer states remain equivalent within 1e-10. The historical sections below describe the pre-edit finding, not current model connectivity.

## Finding and stop rule

The actual R2026b SLX does not connect the selected speed/position outer-loop current reference to the existing FPGA live iq input. This triggers taskbook sections 3.3 and 11: the assumed topology differs, and the existing live reference cannot directly be reused. No controller, tag, wire, SLX, initialization, gain, RTL, timing or plant parameter was changed to bypass this gate.

The read-only MATLAB probe follows real port/line handles and local Goto producers:

```text
Simple_Host output 10 = iq_test_ref = Host_Iq_A
  -> Host_iq_cmd / local [iq_cmd]
  -> FPGA_Live_iq_cmd
  -> FPGA_HDL_Cosim/iq_cmd
  -> FPGA_Input_Adapter/iq_cmd
  -> LiveDouble_iq_ref
  -> Reference_iq_ref live branch (FPGA_Reference_Mode = 1)
```

The real selected outer reference is a different signal:

```text
Control_Task_10kHz/Speed_Loop output 1
  -> local [iq_ref_normal]
  -> Reference_Manager input 1
  -> Reference_Manager output 2 = selected iq_ref
  -> local [iq_ref] -> legacy FOC_Algorithm input 6
```

`Control_Task_10kHz` currently exports only three legacy CMP outputs. It does not export selected id/iq references. `Host_Iq_Test_Mode=0` selects the speed PI inside Reference_Manager, but does **not** change the root `iq_cmd` producer. Consequently `[backend enable inputmode refmode]=[1 1 1 1]` alone would select Host_Iq_A at the FPGA input, not close the requested outer loop. Root `id_cmd` also originates from Host output 8; selected id is Reference_Manager output 1.

This is present in both fetched origin/main and the user's as-found model. It is not caused by the local From/Goto layout work. `main_vs_local_interface.txt` records the matching source SID and controller output lists.

## Fresh evidence and reproduction

Base: `e7f707b1c2d40003f54b065a15411987cb17c9b2` (taskbook PR32), including merged PR31 `8b31b988bfe3d935898ca5960df2051c70836f5e`. Branch: `codex/step7d-outer-loops-cosim`, original working directory only.

Actual runtime: MATLAB `26.2.0.3340147 (R2026b) Prerelease Update 3`. The probe loads the actual SLX, performs no simulation or HDL setup, closes its own model without saving, and restores cwd/MATLAB path. It refuses an already-loaded model and an existing output directory. PreLoadFcn does initialize base-workspace defaults, as in the existing model; the audit was run in its own batch process.

From a fresh R2026b session with the model closed:

```matlab
cd('D:/Project/FPGA_XC7A200T');
addpath('scripts');
step7d_audit_outer_interface;
```

Expected **failure**, not a successful Step7D gate:

```text
Step7D:LiveReferenceSourceMismatch
Live iq resolves to PMLSM_ThreeLoop_Simple/Simple_Host/10,
not the selected outer reference.
STEP7D_TASK1_BLOCKED_LIVE_REFERENCE_SOURCE
```

Batch process exited 1. Fresh evidence: `docs/reports/step7d/task1_20260922_source_audit/outer_interface_gate.txt`. The broader read-only block/parameter dump remains local at `.superpowers/sdd/step7d_outer_loops_cosim/outer_read.txt`; its summary is `outer_loop_inventory.txt` in the report directory.

## Work deliberately not claimed

- Task 1 source gate failed before scenario freezing and baseline capture. No new 5 ms or full-length native/matched legacy baseline was captured or committed; prior Step7C results are not represented as Step7D evidence.
- Scheduler counters and controller equations were inspected structurally. Actual execution phases, reset behavior, Host trajectory duration and performance have not been measured in Step7D.
- No FPGA outer-loop run, new HDL runtime generation, performance retuning, final acceptance or hardware work occurred. No `STEP7D_FULL_ACCEPTANCE_PASS` is claimed.
- All pre-existing tracked diffs were compared byte-for-byte as Git diff output before/after the audit and remained identical, including tracked SLX/XPR/report changes and document deletions. No untracked files were intentionally edited or deleted during this source audit; the diff comparison does not prove unchanged contents of untracked caches.

## Clarified minimal architecture (not yet implemented)

Explicitly permit exposing **existing Reference_Manager outputs 1/2** through two additional Control_Task outports and connecting those selected id/iq references to the existing FPGA adapter inputs. Preserve the original Host `id_cmd/iq_cmd` tags and all legacy consumers; use distinct local route tags if needed. Do not rename Host test commands into outer-loop commands, duplicate controllers, alter task periods or add delays.

Following the user's clarification, Task 1 resumes first: freeze scenarios, capture and commit native/matched legacy baselines and verify their gates **before** saving this minimal wiring change. Later prove live source/quantization/timing and legacy equivalence, then resume Tasks 2–8 in order. Any subsequent baseline failure remains a separate stop condition.
