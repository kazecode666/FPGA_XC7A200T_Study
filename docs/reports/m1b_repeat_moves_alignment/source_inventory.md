# M1B sources and A checkpoint

Base `9b63e9ae1e17901b663f3cf82290363fa1bfdbaf` (PR48 merged); implementation stays in original checkout.

Latest saved local SLX and init are the source, snapshotted before edits under `.runtime/m1b_20261024/snapshots/`. User init defaults10mm/5s/V10/A100 and Host clockTs_ACR are retained. Standardized PR47 scene explicitly sets1mm/1.2s/V5/A50 for regression, without changing user motor/PI/deadtime. Model Workspace empty and InitFcn read-only contract retained.

Original tracked/untracked inventory and binary patch saved. Old Simple/MIL/ControlCore/DSP and trajectory/tuning helper bytes protected with independent snapshots. No cleanup/deletion/worktree/stash/reset performed.

A: independent MATLABR2026b26.2.0.3386108 process captured immutable pre-change default MAT and two live target changes. Both runs had already reached0.2mm within original0.02mm window. New0.4mm target yielded step;10mm target sampled old global progress. Parameter received, full repeat point motion absent. `baseline_behavior.json` records exact observed reference transition. Initial test result-struct assignment failed after first raw MAT; reference was not overwritten, retry reused it and collected only missing live case. All failed logs retained locally.

Original chart source actually loaded: `PMLSM_ControlCore_Block/PMLSM_ControlCore/Angle_Init`, SID128, inherited event rate from100us parent. Actual five-state chart includes release ramp; `alignment_source.json` exports actions, priorities, data and initial values. No source model saved. DSP script not executed; only parameter lines inspected. Angle offset reset validity will be compared exactly, not inferred to clear offset memory.

Frozen contract: `acceptance_contract.json`. Full MATs are local evidence, never normal Run dependencies or submitted model forks.
