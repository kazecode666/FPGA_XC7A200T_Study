# Local main-directory bring-up
MAIN: D:/Project/FPGA_XC7A200T. Initial main:74f6128954a4972c0ae15de4bddd716d30688d36.
Accepted main:2ffc23e (includes C3 merge4eb050b and C4 task PR18).
Created branchstep6c4-foc-current in same main directory; no new worktree/clone.
624 upstream paths had no overlap with15dirty tracked paths or12untracked hardware documents. Original status and binarydiff identical after switch; untracked files remained at same sizes. Snapshot retained .Xil/step6c4_local_preflight/before.json. Oldworktrees preserved.

TDD RED: project xelab VRFC10-2063 mc_foc_current_core missing before RTL existed.
GREEN: real project snapshot xsim2026.1 exit0, noFatal/Error, STEP6C4_ZERO_CHAIN_PASS latency=512 duty=8388608.
Zero chain WDB retained .Xil/step6c4_local_preflight/zero_chain.wdb; project simulation under FOC_Current/FOC_Current.sim.
Initial configuration issues (new-project .srcs creation, wave radix spelling, wave-close configuration) were corrected; failed setup logs retained in local plan scratch. No accepted/user source changed.
