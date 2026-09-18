# Step 6B — Three-phase motor PWM core execution report

Date: 2026-09-17; reviewed startup fix: 2026-09-18. Base `main`: `3fd4058` (includes merged Step 6A PR #10).
Branch: `step6b-motor-pwm-core`. Approved architecture and task/plan were read
before implementation. The current handoff's explicit approval takes precedence
over the architecture document's older review-status heading.

## Delivered behavior

The new portable `motor_pwm_core` is independent of legacy `pwm_controller`.
Default TBPRD=2500, counter width=12, at 50 MHz gives a 5000-clock/100 us
center-aligned cycle (10 kHz). One shared carrier drives three independently
compared raw phase outputs. CMP=0 forces LOW; CMP>=TBPRD forces HIGH; interior
HIGH duty is CMP/TBPRD. Up-count compares clear and down-count compares set;
registered outputs match the visible carrier/direction/active tuple on each edge.

Enabled accepted commands write only the complete shadow tuple. A single
pending command blocks overwrites, including its loading edge. Only a running
ZERO can load an already-pending tuple. A command accepted on the ZERO edge
waits for the following ZERO. No command changes carrier phase or period.

Disable is synchronous, effective on the next rising clock edge: outputs LOW,
counter ZERO/UP, events LOW, pending canceled, old configuration retained.
Disabled acceptance preloads complete active+shadow values without a load event.
Reset assertion is asynchronous and clears all state except UP direction.
Reset-release synchronization belongs to a future board wrapper.

Files:

- `motor_control_ip/pwm/rtl/motor_pwm_core.sv`
- `motor_control_ip/pwm/tb/motor_pwm_core_tb.sv`
- `motor_control_ip/pwm/README.md`
- `Motor_PWM/Motor_PWM.xpr` (references portable source files)
- `Motor_PWM/Motor_PWM.srcs/constrs_1/new/motor_pwm_clock.xdc`
- `scripts/step6b_motor_pwm_build.tcl`
- Text evidence under `docs/reports/step6b/`

The XDC contains only `create_clock -name sys_clk -period 20.000 [get_ports clk]`.
No input/output delay, false path, multicycle, IOSTANDARD or package-pin constraint
was added. The RTL instantiates no vendor primitives.

## Test-first sequence and functional evidence

Vivado/XSim 2026.1 executable root:
`E:/AMDDesignTools/2026.1/Vivado/bin/`.

1. Commit `9c010eb` added the reset/preload TB before the DUT. `xvlog --sv ...`
   succeeded; `xelab motor_pwm_core_tb -s step6b_red` failed specifically with
   `VRFC 10-2063 Module <motor_pwm_core> not found` and process exit 1.
   Evidence: `tdd_red.txt` (expected failure, not a final regression failure).
2. Commit `38aade2` implemented reset/preload/carrier. XSim passed the carrier
   sequence and 8-clock PEAK / 16-clock ZERO intervals (`tdd_carrier.txt`).
3. Commit `17bf645` added old-pending shadow loading. Atomicity, rejection and
   ZERO collision passed (`tdd_shadow.txt`).
4. Added phase assertions and HIGH-count tests before phase-output logic:
   the deliberately incomplete DUT produced 243 output/count errors. After
   next-state PWM implementation, duty tests passed (`tdd_pwm.txt`, commit
   `ed9a441`). XSim can exit 0 despite `$fatal`; the build therefore checks
   error/fatal text and the exact PASS marker, not process exit alone.
5. Commit `cfbfa25` completed reset/disable and systematic coverage. The new
   scoreboard initially exposed a TB startup issue (checks before any reset);
   asserting reset at time zero fixed the TB. Initial standalone simulation (before the startup review fix):
   **1277 monitored rising clocks**, `ALL STEP 6B MOTOR PWM TESTS PASSED`.

The TB uses `TBPRD_TEST=8`, a 16-clock cycle, with stimulus at falling edges
plus settling time. A separate modulo-16 time model checks every carrier state
and endpoint. A command scoreboard checks complete active/shadow tuples, pending,
ready and load eligibility after nonblocking updates. Every sampled phase level
is checked; full-cycle counts and half-cycle symmetry provide additional checks
independent of the phase-level function. A watchdog fails stalled tests.

| Requirement | Automated result / case |
|---|---|
| Shared exact carrier, ZERO/PEAK pulses | Continuous modulo-time checks; PEAK after 8, next ZERO after 16 clocks |
| Disabled preload and 0/50/100% | `{0,4,8}` yields HIGH clocks `{0,8,16}` /16 |
| Independent 25/50/75% | `{2,4,6}` yields `{4,8,12}` /16 |
| Center alignment | Up compare LOW, down compare HIGH checked each clock; equal ZERO-side HIGH counts on both halves |
| Shadow not immediately active | `{2,4,6}` → pending `{6,2,4}` leaves active unchanged until ZERO |
| Atomic ZERO load | All three active values and PWM agree on load edge; one load pulse |
| Pending overwrite rejection | Different tuple rejected while ready LOW, including loading edge |
| ZERO collision | New `{1,3,5}` accepted entering ZERO waits a full 16-clock cycle |
| Carrier unaffected by commands | Carrier monitor remains active for all update tests |
| Disable with pending | Pending discarded; old active retained, stale shadow not silently applied |
| Re-enable | Disabled preload `{8,4,0}` gives `{16,8,0}` HIGH clocks |
| Async reset under activity | Assert between clock edges with nonzero output and pending command; immediately check all required state |
| Boundary/overrange | Exhaust all representable 4-bit values 0..15, including every CMP>8 |
| Update arrival timing | Commands accepted at every carrier phase; rejected attempted replacements held through load edge |
| Pulse widths | ZERO, PEAK and load cannot stay HIGH on consecutive clocks |

Final automated build repeats this TB and runs the original legacy RTL/TBs in a
separate temporary project. It never opens or saves either legacy `.xpr`:

| Regression | Exact required marker |
|---|---|
| `pwm_controller_tb` | `ALL STEP 2.5 PWM TESTS PASSED` |
| `pwm_demo_top_tb` | `ALL STEP 5A BOARD TESTS PASSED` |
| `pwm_breathe_top_tb` | `ALL STEP 5B BREATHING TESTS PASSED` |

Each has its own captured `.txt` in the evidence directory. The existing
`python scripts/reference_audit/verify_step6a_vectors.py` also passed:
160 source rows, 2926 checks, max absolute error 5.46e-12. That regression protects
the accepted reference artifacts; it is not a test of PWM duty conversion.

## Enable-first-cycle review correction (2026-09-18)

ChatGPT Review identified a startup gap in the original revision: the first
enabled edge advanced directly to count 1, skipping the opening ZERO interval.
The previous tests waited for a returned ZERO and therefore missed this segment.
The review supersedes the original README's startup sentence.

The new `check_first_enable_cycle` task samples immediately after the first
enabled edge, requires ZERO/UP with all event pulses LOW, checks PEAK at elapsed
8 and the first returned ZERO at elapsed 16, and counts all 16 opening-cycle
PWM intervals. It covers initial enable, disable/re-enable, CMP=1 and every
representable 4-bit compare including boundaries and overrange. It does not
call `wait_for_zero` to skip startup. The continuous scoreboard now distinguishes
startup ZERO from a recurring ZERO, including load eligibility.

Before changing RTL, the updated TB failed against revision `0cccb95` with
2316 errors, including missing registered startup ZERO, early PEAK/returned
ZERO and carrier alignment (`tdd_enable_first_cycle.txt`). This was the expected
RED result; XSim still returned process exit 0, while its log ended in `$fatal`.

The RTL adds one `running` state bit, cleared asynchronously by reset and on
every sampled disable. The first enabled edge holds ZERO/UP and evaluates PWM
from ZERO and the active tuple; advancing begins on the following edge.
No recurring ZERO or shadow-load event occurs on startup. Existing old-pending
ZERO loading, backpressure and synchronous disable semantics remain intact.

Post-fix XSim passed **1567 monitored rising clocks**, including 18 explicitly
checked first-enable cycles; all three legacy regressions and the Step 6A
2926-check vector regression passed again.

## Synthesis, route and timing

Build command from repository root (PowerShell):

```powershell
& E:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat -mode batch -nojournal `
  -log .Xil/step6b_enable_build.log -source scripts/step6b_motor_pwm_build.tcl
```

Post-fix batch execution completed on 2026-09-18, process exit **0**, with
`STEP6B_BUILD_PASS`. Both runs reached 100%: `synth_design Complete!` and
`route_design Complete!`. Run suffix: `20260918_094600_33076`.
The synthesized default counter is 12 bits (TBPRD=2500); no simulation generic
override is carried into synthesis.

| Resource | Synthesis | Routed |
|---|---:|---:|
| LUT | 139 | 136 |
| FF | 93 | 93 |
| Latch | 0 | 0 |
| BRAM / DSP | 0 / 0 | 0 / 0 |

Routed design also uses 15 CARRY4, 1 BUFG and 133 IOB. All 260 routable nets
are fully routed, with **0 routing errors** (`route_status.rpt`).

| Internal timing at 20 ns | Result |
|---|---:|
| WNS | +12.514 ns |
| TNS | 0.000 ns |
| WHS | +0.153 ns |
| THS | 0.000 ns |

`check_timing.rpt` reports no missing clocks, no unconstrained internal
endpoints, no multiple clocks, no combinational/latch loops and no partial
I/O delay constraints. It reports **39 inputs without input delays and 93
outputs without output delays**. These intentionally unconstrained external
interfaces are outside internal timing acceptance; this is not board-level
timing sign-off. The script checks both timing-summary totals and unrounded
worst setup/hold path slack.

Warnings and errors are separated by their source, rather than presenting a
misleading global zero-warning result:

- Synthesis and implementation run logs each contain **0 errors, 0 critical
  warnings and 0 warnings** (`messages.txt`). No width/sign, multiple-driver,
  unresolved-reference or loop warning was found.
- Final batch driver has two warnings: `Project 1-5713` for an unset board part
  in this part-only project, and `Vivado 12-180` because the latch query finds
  no `LD*` cells. Neither changes the implementation result.
- `drc.rpt` retains **two critical warnings**: `NSTD-1` and `UCIO-1` for all
  133 logical ports lacking IOSTANDARD and pin assignments. It also retains
  **one warning**, `CFGBVS-1`, for unspecified configuration-bank voltage.
  These expected board-contract findings are not suppressed or downgraded.
- `methodology.rpt` reports **132 TIMING-18 warnings** for absent I/O delays.
  No external interface timing or bitstream readiness is claimed.
- Final motor and three legacy simulations have their required PASS markers
  and no error/fatal failures. Earlier intentional TDD failures are separately
  labeled in the TDD evidence.

Two initial project-bootstrap attempts failed before the final successful
build: the first encountered an existing project source directory; the second
project-creation attempt removed the newly seeded task XDC and its guard caught
the missing file. The clock-only XDC was restored. The final script opens the
tracked XPR and does not recreate, force-overwrite or delete source directories.
These attempts did not modify legacy or reference files.

After each successful build, the XPR root path was normalized to `$PPRDIR`;
RTL, TB, XDC and build parameters were unchanged. On 2026-09-17, a four-file relocated copy
of the project was opened read-only by Vivado, and all three source references
resolved inside the relocated tree (`portability.txt`). Its warnings concern
absent generated IP/run directories/files and the unset board part; generated
build outputs are deliberately not packaged. This checks source relocation,
not a second routed build. The startup fix preserves the same three source
references and rechecks that the XPR has no drive-qualified path. Timestamped run metadata remains in the XPR, while
the build script creates fresh runs on every execution.

There is **no unresolved functional or internal timing blocker** for the
approved Step 6B scope. Physical I/O constraints and power-stage behavior
remain explicitly deferred.

## Review and scope verification

The initial separate read-only RTL/TB review found no actionable defects in carrier,
next-state output alignment, old-pending load/collision behavior, reset/disable,
or TB race/coverage logic. A separate static build/project/documentation review
also found no blocking defect. The later ChatGPT startup finding and correction
are documented above. Reviewers did not independently rerun simulation;
the build evidence is from actual local XSim execution.

`git diff --check` and the branch diff against main are used for scope checks.
Exported text evidence has trailing whitespace and extra EOF blank lines
normalized for Git; report values and diagnostic content are preserved.
No Step 6B change is made to `PWM_Controller/`, `PWM_Breathe/`, `simulink模型/`
or the Step 6A golden artifacts. Existing local changes to
`BX72管脚分配表V2.1.xlsx`, `PWM_Controller/PWM_Controller.xpr` and
`PWM_Breathe/PWM_Breathe.xpr` are preserved outside the task commits.
Generated simulation/run/cache files are excluded; only source/project metadata
and text reports are committed. No SHA/file-hash verification was used.

**No bitstream, hardware programming or physical pin mapping.** This result is
raw three-phase digital PWM timing validation, not `duty_to_cmp`, FOC/SVPWM,
complementary switching, dead time, trip protection or safe power-stage drive.
No Step 6C1 work was started. The requested PR is left open, unmerged, for
ChatGPT Review.
