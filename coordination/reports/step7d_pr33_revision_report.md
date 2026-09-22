# PR33 revision execution — AUM3-S4 current PI

Date: 2026-09-22. Binding scope: `coordination/tasks/step7d_pr33_revision.md`.

**Tasks 1–8 complete under the revision. Fresh `STEP7D_FULL_ACCEPTANCE_PASS`.
PR33 remains open for ChatGPT Review; no merge or next stage.**

## Historical result and revised decision

The original Task4 blocker remains in `step7d_codex_report.md` and
`docs/reports/step7d/task4_speed_deadtime/`. Old profile0 with the old 0.5 mm/s
speed MAE/RMSE limits failed; those results are not reclassified using new limits.

The approved correction uses AUM3-S4 Rs=2.37 ohm, L=1.745 mH and Ts=100 us:
Kp=L/(4*xi^2*Ts), Ki=Kp*Rs/L. Profile0 xi=1/sqrt(2) gives Kp=8.725,
Ki=11850 and KiTs=1.185, independently rounded to F24 146381210/19881001.
Profile1 remains xi=1, 73190605/9940500. Kaw, speed PI, plant, deadtime law,
control periods and interface formats are unchanged. Legacy RTL symbol names
are retained for compatibility; their current physical meanings are documented
beside the constants.

New deadtime speed MAE/RMSE limits are 1.5 mm/s; ideal remains 0.5 mm/s,
and both maximum-error limits remain 2 mm/s. Structural/protocol gates remain.

## Implementation and environment

Implementation commits: `fe216a4`, `2132bd8`, `0130086`, `dc236d2`.
The fresh aggregate acceptance tests `dc236d2`. The original working tree was retained and
the remote documentation-only revision fast-forwarded. No worktree, clone,
stash, reset, cleanup, installation, global PATH change or hardware operation.
Layout work remains paused and uncommitted. No SLX was saved in this revision.

Project `.codex/config.toml` adds `matlab_r2026b`, using the already installed
MCP server 0.13.0 in new-session/nodesktop mode. The global R2026a entry is
unchanged. A direct MCP stdio initialize/tools-list/tools-call sequence verified
release 2026b, root `D:/Program Files/MATLAB/R2026b_Prerelease` and installed
model_read/model_edit/model_check functions. Existing Toolkit initialized in
that session; model access used the successful library.settingsLookup gate.
The running Codex tool inventory need not be hot-reloaded for this direct MCP
client verification; the project config exposes named tools after session reload.

Current reference constants, four direct self-check expectations, RTL literal
self-check and necessary current fixtures were synchronized. Historical Step6A
comparison explicitly retains historical coefficients; current golden fixtures
replay its input sequence with current coefficients and their own sequential
state. Historical report content remains unchanged. Fixture generation/check
is maintenance evidence, not a new Step6 HDL or hardware acceptance.

Control-event checking now compares each entire stream against its measured
grid: current starts 0, speed 0.9 ms, position 9.9 ms; periods 0.1/1/10 ms.
Deleting the last position event was observed to pass before the fix and is now
rejected. Existing accepted/active checks remain unchanged.

## Fresh evidence

Evidence directory: `docs/reports/step7d/pr33_revision_20260922/`.

- Constant mismatch and deleted-tail false acceptance reproduced before fixes.
- Corrected constant checks, contract tests including a real legacy fresh-start,
  and fresh Vivado XSI compilation/elaboration passed (`mcp_contracts_build.txt`).
- Fresh Step7C ideal and deadtime current-loop cases passed (`dynamic_*.txt`):
  positive/negative response, live feedback, duty boundary, current bounds and
  zero fault/range flags. These are representative current-loop checks, not
  full Step7C acceptance.
- First revised speed attempt was interrupted before complete output; retained
  as `speed_ideal/interrupted.txt`, never counted as a PASS.
- Fresh resumed speed_ideal passed, worst window RMSE 0.0926415902 mm/s,
  current RMSE 0.0005412087 A (`speed_ideal_resume/`).

- Fresh resumed speed_deadtime passed: worst speed RMSE 0.2360912941 mm/s,
  current RMSE 0.0035283093 A. Every speed window also meets the historical
  0.5 mm/s limit, although this new run is evaluated under the approved revision.
- All three Task5 position cases passed. Maximum arrival-window position errors:
  ideal 0.0212493021 mm, deadtime 0.0214822804 mm, negative deadtime
  0.0206091230 mm. Corresponding maximum arrival speeds are below 1 mm/s.
- The original speed-PI component harness exercised both +/-1 A output limits,
  +/-0.5 A integral limits, exact antiwindup update, explicit reset and nonzero
  integral hold (0.1154142391 A) under zero synthetic error. This is an in-memory
  injection at the original Speed_Loop inputs, not a duplicated controller or
  plant closed-loop test. A first logger-dimension failure was corrected by
  sampling on the actual speed execution events; it was not controller tuning.

- Task6 full-rate stop check passed on run `20260922_194837_331`: 150000
  post-disable samples from 0.250001 s have bridge/valid/vd/vq zero,
  needs_reset=1 and fault=0. The actual Adapter PI_Reset pulse spans
  0.350–0.351999 s and cannot re-enable the bridge. Position remains continuous;
  speed decays under the existing model. A separate `fresh_start` simulation
  passed; this is not hot restart or real hardware stopping evidence.
- Task7 0.20 s convergence passed: common-grid max [iq,id,v,x] differences
  are [0.00148876391 A,0.00068037844 A,0.00603721903 mm/s,
  0.00000669551 mm], with 2000 accepted/1999 active commands in both runs.
- Native legacy equivalence passed at <=1e-10 for current plus full-length
  speed/position scenarios. Structure, current timing/dynamics/convergence,
  six-value minimal HDL exchange and the current-profile wrapper passed.
  The updated wrapper expects CMP 909/1591/1591, independently calculated
  from the corrected integer reference. A stale old-profile literal failed
  first; the historical failed log is retained, alongside `wrapper_retry/`.

## Final acceptance and review

Fresh aggregate output in
`docs/reports/step7d/acceptance_20260922_205317_302/` passed all 21 required
report gates and produced `STEP7D_FULL_ACCEPTANCE_PASS`. Its own XSI runtime
was rebuilt, followed by all scenarios in order; no pilot result was reused.
The source commit tested is `dc236d2db956e36d4597c054ae96b5f5de4fe410`.
Subsequent delivery changes only add descriptive postprocessing and reports.
The five speed/position metrics exactly reproduce the individual results above.
Native legacy before/after maximum error is **0** across all recorded channels,
including full 1.2 s speed and position cases (limit <=1e-10).
Structure records `LEGACY_PRE_DEADTIME_SATURATION=0` and
`SHARED_POST_DEADTIME_SATURATION=1`; one plant and one deadtime model remain.
Full run output is `mcp_acceptance_output.txt` in the aggregate directory.
Two earlier startup attempts stopped before scenario execution: this MATLAB
installation lacks Java, and its child PowerShell cannot resolve Get-FileHash.
The final helper uses built-in .NET SHA256; the same R2026b environment returned
the exact saved-model digest before relaunch. Startup failure evidence remains
in `acceptance_20260922_202209_511/` and `acceptance_20260922_202557_222/`.
Hashing records/protects the input artifact only; it does not replace acceptance.

One independent whole-branch review found no Critical/Important issues. It
checked the original speed PI XML against the base and current source fixtures
against the committed reference. Its documentation-status finding is addressed
by this final report/README update. The reviewer did not independently rerun
MATLAB/XSI, judge the deferred local layout, or accept hardware/Step6 behavior.
Actual runtime claims below remain tied to author-executed reports.

## Preservation and limits

The tested local model SHA256 is
`1E1C7A30F9FB776EE40862C69DFD35D62E3A5DA2F38996609FC6728F2CAFE7E6`.
It includes the pre-existing uncommitted model/layout edits and was not staged
by this revision. Existing tracked dirty diffs were compared with the pre-turn
binary patch (`local_preservation.txt`); untracked caches were not deleted.
This does not claim identical contents for every pre-existing untracked file.

No full Step6C2/C4/6D/6E simulation/synthesis/route/timing rerun, no speed PI
retuning, position-difference/IIR feedback or new deadtime compensation.
The whole-stage claim is based on the fresh aggregate acceptance, not the pilot
or historical partial evidence. Full-rate descriptive metrics are separately
recorded per scenario without new PASS thresholds; they do not change dynamics.
Visual inspection of the fresh negative-position response confirms travel toward
-1 mm and bounded near-zero-speed ripple after arrival. Small low-current
deadtime oscillations remain visible; satisfying the integration gates does not
claim final low-speed performance optimization.

## Execution decisions and limits of review

| Decision | Reason | Limit / cost if incorrect |
|---|---|---|
| Use original worktree; retain scratch/layout | Explicit user boundary overrides skill isolation/cleanup | Dirty files require explicit preservation and staging audit |
| Apply PR33 revision before original taskbook freezes | Explicit approved profile/gate/MCP/coverage correction | Conclusions apply to revised parameters and gates |
| Reuse installed MCP/Toolkit with project config | No installation/global migration authorized or needed | Other machines need equivalent installed paths |
| Keep historical Step6A coefficients for historical replay; current fixtures use current state/coefficients | Historical evidence must remain historical | Fixture maintenance is not full Step6 acceptance |
| Inject synthetic error at original SpeedLoop inputs in memory | Exercise actual PI with original reset/scheduling | Component result is not plant closed-loop proof |
| Store current C4 comparison beside fixtures | Do not rewrite accepted historical reports | Future C4 checks must use the current fixture path |
| Require a fresh aggregate marker after individual passes | Reviewer did not assess unfinished final acceptance | Missing final gates prevent a full-stage claim |
| Report runtime evidence as author-executed | Reviewer checked code/fixtures, did not rerun MATLAB/XSI | No independent runtime reproduction claim |
| Preserve dirty local SLX and defer layout | User explicitly postponed layout work | Tested local artifact differs from committed binary |
| Exclude full Step6, hardware and hot restart | Revised task boundaries | No coverage claim for those uses |

No Critical/Important review finding was left unresolved. Final documentation
status is required delivery work, not a separate controller or layout change.
