# Step 6C2 — Fixed-point dq PI, feedforward and circular voltage limiter

Date: 2026-09-18.
Baseline: PR #12 merged at `1207f3870ca7fd5497b2f7374bb7287654ed8c73`.
Status: **Design contract prepared for approval. Merging the documentation PR accepts this contract; it does not certify an implementation.** Codex implementation starts only after this contract is accepted and the user starts that task.

## 1. Authority, scope and decisions

Read `coordination/HANDOFF.md`, `coordination/specs/step6_motor_control_pwm_pi_foc_architecture.md`, the accepted C1 specification, and sections 5–6 of `coordination/reports/step6a_pi_foc_reference_audit.md`. This document freezes C2 integer arithmetic, transaction timing and explicitly identified FPGA-specific guards. Step 6A remains the source of PI/feedforward signs, old-state ordering, command-reset behavior and delayed anti-windup.

Implement only the standalone path `id/iq + references + we + vdc -> PI/feedforward -> circular limiter -> ud_lim/uq_lim`. The C1 transforms are read-only dependencies/regressions, not part of the C2 synthesis top. No SVPWM, inverse-Park integration, PWM integration, ADC, encoder, AXI, motor commissioning or bitstream.

Selected baseline: ordinary signed, pipelined multiplication; an iterative exact integer square root; an iterative exact unsigned divider; and fixed transaction-level completion slots. No vendor primitives, floating-point arithmetic or proprietary arithmetic IP in reusable RTL. Wider multipliers may infer several DSPs: **C1's six-DSP count is not a C2 resource target**. Report actual mapping rather than forcing a count.

Alternatives not selected: reciprocal-square-root LUT/Newton methods add approximation and normalization contracts; CORDIC/vendor IP adds another backend/portability boundary. They can be evaluated later, not substituted silently in this implementation.

## 2. Mathematical and temporal reference

One accepted control sample is one discrete update, with baseline `Ts = 100 us`. The 50 MHz fabric clock advances calculation, not integration.

With command resets inactive:

```text
ed = id_ref - id_meas
eq = iq_ref - iq_meas
ud_raw = Kp*ed + xd_old - we*Lq*iq_meas
uq_raw = Kp*eq + xq_old + we*(Ld*id_meas + psi_f)
xd_next = xd_old + KiTs*ed - Kaw_d*du_d_old
xq_next = xq_old + KiTs*eq - Kaw_q*du_q_old
Umax = 0.9*vdc/sqrt(3)
s = min(1, Umax/(sqrt(ud_raw^2 + uq_raw^2) + 1e-6))
ud_lim = s*ud_raw; uq_lim = s*uq_raw
du_d_next = ud_raw - ud_lim; du_q_next = uq_raw - uq_lim
sat_flag_next = (s < 0.999)
```

`KiTs` already includes Ts. `Kaw` is 0.2 per update; do not multiply it by Ts. Current raw voltage uses OLD x, not x_next. x_next uses OLD du, never the current limiter correction. The old correction is one **control transaction** old, not one fabric-clock old.

These reference equations are real-valued. Sections 3–6 define their complete bit-exact C2 interpretation; floating-point equality is not required.

## 3. Frozen integer formats and constants

`S<W>/F<F>` means W-bit signed two's complement with F fractional bits; `U` means unsigned. Physical value is raw divided by 2^F. Arithmetic domains are not approved motor operating limits.

| Quantity | Format | Meaning/range |
|---|---|---|
| id_meas, iq_meas, id_ref, iq_ref | S25/F15 | A; -512 to 512-2^-15 |
| ed, eq | S26/F15 | full reference-minus-measurement difference |
| we | S32/F16 | electrical rad/s; -32768 to 32768-2^-16 |
| vdc | S25/F15 | V; valid only for raw > 0, up to 512-2^-15 |
| Kp, KiTs, Kaw_d/q | S32/F24 | separate PI coefficient format, approximately +/-128 |
| Ld, Lq, psi_f | S32/F30 | H, H, Wb respectively |
| xd/xq, delayed du_d/du_q | S40/F24 | V; -32768 to 32768-2^-24 |
| ud_raw/uq_raw, limited internal voltages | S40/F24 | same internal voltage format |
| ud_lim/uq_lim external outputs | S25/F15 | V, compatible with C1 inverse Park |
| squared norm | U80/F48 | sum of two exact squared S40/F24 values |
| floor square root | U40/F24 | integer root of squared-norm raw value |
| denominator | U41/F24 | ceil root plus EPS_RAW |
| Umax | U40/F24 | conservative quantized voltage limit |
| scale | U33/F32 | 0 through exact 1; ONE_SCALE = 4294967296 |

C1's S18/F16 coefficient format cannot represent either C2 Kp. Do not modify `mc_fxp_pkg.sv` or reuse its limited-width constants for PI coefficients.

`mc_pi_dq_core` and `mc_pi_dq_eval` have elaboration parameter `PI_PROFILE=0`. Only 0 and 1 are legal. No run-time gain writes/profile switching in C2.

| Constant | Physical value, profile 0 | Raw, profile 0 | Physical value, profile 1 | Raw, profile 1 |
|---|---:|---:|---:|---:|
| KP, F24 | 2.18125 | 36595302 | 4.3625 | 73190605 |
| KI_TS, F24 | 0.29625 | 4970250 | 0.5925 | 9940500 |
| KAW_D/KAW_Q, F24 | 0.2 | 3355443 | 0.2 | 3355443 |
| LD/LQ, F30 | 0.001745 | 1873679 | 0.001745 | 1873679 |
| PSI_F, F30 | 0.141 | 151397597 | 0.141 | 151397597 |

Profile 0 is `real_commissioning`; profile 1 is `MIL_PI_override`. These are reference configurations, not final motor tuning. Quantize the listed decimal physical constants independently using nearest/ties-away; do not derive one profile by doubling an already rounded constant.

Additional constants:

```text
C_UMAX = floor((0.9/sqrt(3))*2^30) = 557932618  // U32/F30, deliberate floor
EPS_RAW = round_away(1e-6*2^24) = 17           // U41/F24
STATE_MIN = -549755813888; STATE_MAX = 549755813887
ONE_SCALE = 4294967296                        // U33/F32
```

The generator must reproduce these values with high-precision decimal arithmetic and explicit rounding modes. A one-bit wrong constant is a failure, not a tolerance case.

## 4. Rounding, width growth and PI evaluation

Define `R(x,n)` as signed nearest rounding, ties away from zero:

```text
R(x,0) = x
R(x,n) = sign(x) * ((abs(x) + 2^(n-1)) >> n), n > 0
```

Extend a signed input by one bit before abs. Preserve negative exact multiples. `mc_pi_fxp_pkg.sv` provides a signed-96-input helper with a 97-bit magnitude; each call's shift is a compile-time constant. Also provide explicit S40 and S25 range predicates. A signed right shift alone is not R.

Calculate in this order, using captured measurements and OLD states:

```text
ed = sign_extend(id_ref) - sign_extend(id_meas)
eq = uq_zero_en ? 0 : sign_extend(iq_ref) - sign_extend(iq_meas)
P_d = R(ed*KP,15);       P_q = R(eq*KP,15)
I_d = R(ed*KI_TS,15);    I_q = R(eq*KI_TS,15)
AW_d = R(du_d_old*KAW_D,24)
AW_q = R(du_q_old*KAW_Q,24)
flux_d = LQ*iq_meas
flux_q = LD*id_meas + (sign_extend(PSI_F) << 15)
FF_d = R(-we*flux_d,37)
FF_q = R( we*flux_q,37)
ud_candidate = P_d + xd_old + FF_d
uq_candidate = P_q + xq_old + FF_q
xd_candidate = xd_old + I_d - AW_d
xq_candidate = xq_old + I_q - AW_q
```

Every P/I/AW/FF result is F24, but wide temporary terms are NOT narrowed to 40 bits before the final sums. This permits valid cancellation and avoids spurious intermediate clipping.

Minimum full product/accumulator widths: error*gain S58/F39; du*Kaw S72/F48; L*current S57/F45; q flux sum S58/F45; we*q-flux S90/F61. Sign-extend the d product before negation. Use signed-96 temporaries for rounded terms and final sums; every value under the defined input widths fits these temporaries. Widen before add, negate or left shift, not after. Do not let mixed signed/unsigned expressions or unsized literals silently change these rules.

Apply command resets BEFORE checking final candidate ranges:

- `pi_reset=1`: ud_raw, uq_raw, xd_next, xq_next are zero.
- Otherwise `uq_zero_en=1`: uq_raw and xq_next are zero, and eq is zero. d evaluation still uses the actual iq_meas in its feedforward; it is not replaced by zero.
- Other axes follow the candidate equations.

All four selected raw/next-state values must fit S40. Failure produces `RANGE_ERROR`; no early clamp and no persistent-state write. Limiter feedback also stays at F24 (section 5). Do not add an arbitrary integrator clip absent from Step 6A.

## 5. Exact circular-limiter integer algorithm

For valid positive vdc and representable S40 raw voltages:

```text
norm_sq = ud_raw*ud_raw + uq_raw*uq_raw
root_floor = isqrt(norm_sq)
remainder = norm_sq - root_floor*root_floor
root_ceil = root_floor + (remainder != 0)
denom = zero_extend(root_ceil) + 17
umax = (unsigned(vdc_raw)*C_UMAX) >> 21
if umax >= denom:
    scale = ONE_SCALE
else:
    scale = floor((umax << 32)/denom)
ud_hi = R(ud_raw*scale,32)
uq_hi = R(uq_raw*scale,32)
du_d_next = ud_raw - ud_hi
du_q_next = uq_raw - uq_hi
ud_lim = R(ud_hi,9)
uq_lim = R(uq_hi,9)
limited = (scale < ONE_SCALE)
sat_flag = (1000*scale < 999*ONE_SCALE)
```

`ud_hi/uq_hi` and du_next are S40/F24. The external outputs alone are narrowed to S25/F15. Back-calculation uses the internal limited F24 voltage, NOT the already rounded external F15 output. This precision boundary is an explicit C2 decision.

The norm sum is UNSIGNED: (-2^39)^2 + (-2^39)^2 equals 2^79 and must not become a negative S80 number. Use U81 temporary addition and retain its verified U80 result. Full square products are 80 bits.

The positive bus is first validated as signed, then cast unsigned. Use a full unsigned 25x32 product for Umax; shift 21 converts F45 to F24. A U40 result suffices. Build the divider numerator as `{umax[39:0],32'b0}` (U72); do not shift inside a 40-bit expression. Denominator is U41 and cannot be zero. Divider quotient is U72; on this branch it must fit U32 before extension to U33.

For signed voltage times unsigned scale, zero-extend scale to signed 34 bits before multiplication; retain the full signed 74-bit product. Compare saturation threshold using at least unsigned 43-bit products. 0.999 is not the same condition as any scaling at all.

Round-to-F15 can produce a very small norm excess. Do not secretly replace the output rounding policy to enforce a stricter circle. The defined norm tolerance is in section 9. All limited F24 values and corrections must fit S40 and the external voltages must fit S25. An impossible range/invariant failure is reported, never wrapped or accepted as a normal clipped result.

At zero vector, denominator is 17 and both voltages/corrections are zero. Keep the additive epsilon; do not replace `r+epsilon` by `max(r,epsilon)` or discard it. Positive bus values as small as one F15 LSB are valid arithmetic inputs. Zero/negative bus is handled separately.

## 6. Persistent state, reset and failures

Only `mc_pi_dq_core` owns persistent `xd_state`, `xq_state`, `du_d_state`, `du_q_state`, `sat_state`. The evaluator and limiter are stateless transaction units. Capture OLD state with the accepted input; atomically commit all five NEXT values only when a successful response is emitted. No speculative state write at acceptance or evaluator completion.

| Condition | Response | Persistent state |
|---|---|---|
| No accepted input / idle | no new response | hold |
| Normal successful calculation | computed voltages/flags | commit all five once |
| pi_reset, valid bus | zero voltages; zero next states/corrections | zero all five at successful completion |
| uq_zero_en, valid bus | q voltage/q next state/q new correction zero; d operates | commit selected d/q results |
| vdc <= 0 | INVALID_VDC; zero voltage/flags | hold all five, even if pi_reset=1 |
| selected raw/next state out of range | RANGE_ERROR; zero voltage/flags | hold all five |
| arithmetic engine/invariant failure | INTERNAL_ERROR; zero voltage/flags | hold all five |
| reset_n asserted LOW | abort pending work, output_valid=0, visible outputs zero | clear all five immediately |

Error encoding: `2'b00 OK`, `01 INVALID_VDC`, `10 RANGE_ERROR`, `11 INTERNAL_ERROR`. Invalid bus has priority; command resets mask their selected axis calculations before range checking. A command reset is not an asynchronous reset. OLD correction/saturation snapshots must remain observable for the reset transaction; clearing the command must not retroactively change its OLD data.

No sticky fault latch and no power-stage trip are provided. `output_valid` marks a completed response, INCLUDING error responses. Only `output_valid && error_code==OK` is a usable voltage result. A future integration must not treat error-response zeros as a valid control command.

`reset_n` has asynchronous assertion; system integration must supply deassertion synchronous to clk. Control/valid/persistent state and visible outputs follow the reset contract. Arithmetic pipeline registers may use synchronous/no reset with valid masking for DSP inference; reset must abort their outstanding work and prevent stale completion. Do not modify C1 reset behavior. A same-time reset assertion wins over acceptance/completion.

No C2 enable port: absence of accepted transactions holds state. Motor enable/fault policy belongs to the later wrapper. Long gaps do not change the fixed KiTs; variable sampling requires a new contract.

## 7. Interfaces, completion slots and observability

All modules use clk, reset_n, input_valid/input_ready and a one-clock output_valid response pulse. No output_ready; consumers must capture responses. An input is accepted only at an edge with reset_n=1 and input_valid && input_ready. Busy input values have no effect. Ready is LOW during reset and while a request is pending.

Frozen acceptance-to-output rising-edge differences:

| Module | Interval |
|---|---:|
| mc_pi_dq_eval | N -> N+16 |
| mc_isqrt_u80 | N -> N+40 |
| mc_udiv_u72_u41 | N -> N+72 |
| mc_dq_limiter | N -> N+160 |
| mc_pi_dq_core | N -> N+256 = 5.12 us at 50 MHz |

These are DESIGN REQUIREMENTS, not measured results. Each unit supports one request in flight; hold an early result until its assigned slot. Bypass, reset-command and error paths use the same interval. Earliest next acceptance is the edge AFTER completion (core N+257), not its completion edge. The divider still responds at +72 for divide-by-zero; the limiter/core pad rejected inputs to their fixed slots. Counters/FSM advance only for pending transactions.

The core must internally finish before its completion slot. A missed schedule is a failing verification/invariant, not permission to change latency. Suggested composition: evaluator accepts by N+1, completes by N+17; limiter accepts by N+18, completes by N+178; core captures by N+179 and pads until N+256. Adjust internal launch scheduling without changing module intervals.

Top `mc_pi_dq_core #(parameter int PI_PROFILE=0)`:

```text
Inputs: clk, reset_n, input_valid
        signed [24:0] id_meas, iq_meas, id_ref, iq_ref
        signed [31:0] we
        signed [24:0] vdc
        pi_reset, uq_zero_en
Outputs: input_ready, output_valid
         signed [24:0] ud_lim, uq_lim
         logic [1:0] error_code
         limited, sat_flag
```

Evaluator additionally receives S40 OLD xd/xq/du_d/du_q; returns S40 ud_raw/uq_raw/xd_next/xq_next and error_code. Its parameter selects the same profile as the core. Limiter receives S40 ud_raw/uq_raw and S25 vdc; returns S40 ud_hi/uq_hi/du_d_next/du_q_next, S25 ud_lim/uq_lim, U33 scale, limited/sat_flag/error_code.

Sqrt receives U80 radicand; returns U40 root_floor and U41 remainder. Divider receives U72 numerator and U41 denominator; returns U72 quotient, U41 remainder and div_by_zero. On zero denominator return quotient=0, remainder=0, div_by_zero=1; otherwise verify numerator=quotient*denominator+remainder and remainder<denominator with wide checker arithmetic.

Keep stable internal, response-aligned debug names in the core: `dbg_xd_old`, `dbg_xq_old`, `dbg_du_d_old`, `dbg_du_q_old`, `dbg_sat_old`, `dbg_ud_raw`, `dbg_uq_raw`, `dbg_xd_next`, `dbg_xq_next`, `dbg_ud_hi`, `dbg_uq_hi`, `dbg_du_d_next`, `dbg_du_q_next`, `dbg_scale`. Use S40 voltage/state and U33 scale types. On errors, OLD snapshots reflect captured state, NEXT snapshots equal OLD state and other debug calculation values are zero. On reset all debug snapshots are zero.

Expose debug through hierarchy/testbench, NOT hundreds of additional top-level pins. Do not force KEEP/DONT_TOUCH merely to preserve simulation-only snapshots. Synthesis may remove them. They and functional outputs remain stable between response updates, except reset; output_valid alone pulses.

## 8. Implementation structure

Create under `motor_control_ip/foc/rtl/`:

```text
mc_pi_fxp_pkg.sv       // C2 formats, literals, R and range predicates
mc_isqrt_u80.sv        // 40-step unsigned digit-pair integer sqrt
mc_udiv_u72_u41.sv     // 72-step unsigned restoring division
mc_pi_dq_eval.sv       // stateless old-state PI/feedforward evaluator
mc_dq_limiter.sv       // squared norm, sqrt, division, common scale
mc_pi_dq_core.sv       // input capture, state ownership, atomic commit
```

Corresponding six testbenches: `mc_pi_fxp_tb`, `mc_isqrt_u80_tb`, `mc_udiv_u72_u41_tb`, `mc_pi_dq_eval_tb`, `mc_dq_limiter_tb`, `mc_pi_dq_core_tb`, under `motor_control_ip/foc/tb/`.

Create `scripts/step6c2_pi_reference.py`, `scripts/step6c2_pi_reference_test.py`, `scripts/step6c2_pi_build.tcl`, `motor_control_ip/foc/README_step6c2.md`, and `FOC_PI/FOC_PI.xpr` with clock-only `FOC_PI/FOC_PI.srcs/constrs_1/new/foc_pi_clock.xdc`. New fixture namespace: `motor_control_ip/foc/tb/vectors/step6c2/`. No duplicated source files inside the project.

The square root processes two radicand bits per iteration. Use sufficiently wide working remainder/trial registers (44 bits is sufficient); returned remainder is U41. The divider processes one numerator bit per iteration with a 42-bit shifted remainder. No combinational unrolling of all 40/72 iterations and no synthesizable variable `/` or `$sqrt` for these operations. Constants may be folded normally. Pipeline multiplies and their consumers; never assume a multi-DSP multiplier has one native-DSP timing path.

## 9. Verification and acceptance

### Three separate numerical comparisons

1. **Bit-exact:** all RTL functional responses, errors and OLD/NEXT state snapshots match the independent C2 Python integer model exactly. No epsilon for integer equality.
2. **Step 6A algorithm comparison:** use the actual 160-row `step6a_pi_foc_golden_vectors.csv`, in original order, two independent 80-row profile runs. Quantize its id/iq, references, speed and bus directly; do not rerun C1 transforms in this comparison. Hardware-reset the model once at each profile start; preserve row-by-row pi_reset/uq_zero behavior and all subsequent state. Do not reload integrators from expected CSV values every row. Require max absolute error <=0.002 V for each of ud_raw, uq_raw, ud_lim, uq_lim, du_d_z, du_q_z. Compare CSV delayed columns to OLD, not NEXT corrections. Report column-wise maxima, row/profile and state histories. Failure is a review stop, not authority to loosen the gate.
3. **Limiter ideal comparison:** for identical quantized S40 raw voltage and valid S25 bus, compare against real `min(1,Umax/(hypot(d,q)+1e-6))`. Require each external voltage error <=2 F15 LSB (0.00006103515625 V) and output norm <=ideal Umax+1 F15 LSB (0.000030517578125 V). Check finite results and signs. These are component/norm bounds, not a general relative-angle bound near zero.

Round-to-F15 and high-resolution rounding account for a small norm excess; coefficient floor, root ceiling and scale floor make the pre-round scale conservative. Directed and seeded full-domain tests are required; random tests alone are not a proof of complete-domain correctness.

Report sat_flag differences against Step 6A rather than disguising the 0.999 threshold as the onset of limiting. Any Boolean mismatch in the 160 rows must be listed with both scale estimates; a mismatch farther than 1e-4 from 0.999 in the real reference is a failure. Bit-exact current/old flags against the integer oracle are always mandatory.

### Required cases

- R positive/negative ties, tie neighbors, exact multiples, zero shift, most-negative S96; S40/S25 rail predicates.
- Sqrt 0,1,2,3,4, maximum U80, perfect squares and +/-1 neighbors, minimum/maximal root regions; exact root and remainder invariants.
- Divider zero numerator, divisor 0/1, numerator<divisor, exact division, nonzero remainder, U72/U41 maxima and seeded random values.
- PI both profiles, zero state, first-three-update identity below, measured-current error signs, positive/negative electrical speed, d/q feedforward independently, old du versus new du, small integral increments retained in F24, S26 difference extremes, selected candidate overflow.
- Limiter zero vector, axes, all quadrants, threshold +/-LSB, equal components, full S40 rail combinations, bus 1 raw/48 V/maximum/zero/negative, dynamic bus changes, limited versus sat_flag.
- Core all 160 golden rows plus at least 1024 successful seeded stateful transactions per profile; include sustained saturation, reference reversal and recovery. Test at least 128 accepted error cases per profile separately.
- No state changes over >=5000 idle clocks; vary idle gaps with identical accepted sequence and obtain identical results. Valid held across busy must accept only when ready. Toggle all unaccepted buses/commands while busy; no cross-sample contamination.
- Async reset while evaluator/sqrt/divider/padding is active, including just before completion; no stale response. Command reset during saturation must expose OLD correction then commit zero NEXT values. q-only reset must not clear d state.
- Scoreboards detect unknown valid/data on meaningful cycles, missing/extra/duplicate/reordered responses, premature state commits and completion-edge acceptance errors.

Independent directed profile-0 test from zero state: id_meas=iq_meas=we=0, id_ref=32768, iq_ref=0, vdc=1572864, no command resets. Three accepted transactions must have:

```text
ud_raw(F24): 36595302, 41565552, 46535802
xd_old(F24): 0, 4970250, 9940500
xd_next(F24): 4970250, 9940500, 14910750
ud_lim(F15): 71475, 81183, 90890
uq, old/new du: 0
```

Fixtures must be deterministic, with a manifest containing exact row counts, schema and seeds. TBs reject malformed non-comment rows, out-of-range values, duplicates and count mismatches; never use a weak `count>=100` gate. Python `--check` verifies both manifest and fixture content against independent regeneration. A fixture and its expected count must not be trusted merely because they agree with each other. The normative golden count remains 160.

### Tool/build evidence

Vivado 2026.1; part `xc7a200tfbg484-2`; sys_clk=20.000 ns. Run all six C2 TBs (both PI profiles), all four unchanged C1 TBs, unchanged Step 6B PWM TB, Step 6A verifier, C1 Python --check and C2 Python checks. Strict success markers and no fatal/error are required; exit status alone is insufficient.

Synthesize AND route core profiles 0 and 1 in independent scratch runs. Record actual DSP48/BRAM/LUT/FF counts, hierarchy and warnings. No exact DSP count is imposed; no inferred latch, multiple driver, unresolved module or internal combinational loop is acceptable. Require completed route, all routable nets routed and zero routing errors. Require nonnegative setup/hold/pulse-width slack, zero negative totals/failing endpoints and no unconstrained internal endpoints/no-clock pins; inspect unrounded setup/hold path properties as well as report summaries.

Retain and enumerate external I/O-delay and board-only NSTD-1/UCIO-1/CFGBVS-1 findings. Do not invent board constraints, suppress severities or claim board timing sign-off. Audit the portable XPR after relocation, compile order, simulation fixture staging and exact clock/source inventory. Finish by rerunning the final script end-to-end after its last edit; saved-report-only gate checks do not replace that run.

Use fresh work under `.Xil`; write new evidence only under `docs/reports/step6c2/`. Never overwrite accepted C1/C1 build reports to obtain C2 regression evidence. `build_result.txt` must start IN_PROGRESS and become PASS only after every final gate; errors produce FAILED, native crashes remain non-PASS. The C2 oracle must reject Python -O/-OO or use optimization-independent explicit checks; the build must verify that safety property.

## 10. Completion boundary and references

Final report: `coordination/reports/step6c2_codex_report.md`; comparison CSV: `coordination/reports/step6c2_pi_fixed_vectors.csv`. Record versions, base/head commits, source provenance, exact numerical/latency/state tests, both profile routes, retained warnings, deviations and any unexecuted check. No SHA-256/file-hash validation; use Git diff, actual tests and tool reports.

Open implementation PR `Step 6C2: Add fixed-point dq PI and circular limiter` from `step6c2-pi-dq-limiter`; stop for ChatGPT review. Do not merge or start C3 automatically.

Primary references: the repository architecture, Step 6A audit and `scripts/reference_audit/step6a_pi_vectors.m` at the baseline above. AMD UG901, 2026.1: [DSP Block Implementation](https://docs.amd.com/r/en-US/ug901-vivado-synthesis/DSP-Block-Implementation), [Pre-Adders in the DSP Block](https://docs.amd.com/r/en-US/ug901-vivado-synthesis/Pre-Adders-in-the-DSP-Block), [USE_DSP](https://docs.amd.com/r/en-US/ug901-vivado-synthesis/USE_DSP). AMD UG901 [Coding Guidelines, 2024.2](https://docs.amd.com/r/2024.2-English/ug901-vivado-synthesis/Coding-Guidelines) documents the synchronous-reset limitations of DSP/BRAM internal registers. These references support inference/reset guidance, not measured C2 performance.
