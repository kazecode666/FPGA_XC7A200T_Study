# Step 6C2 design decisions and preflight — not implementation evidence

Date: 2026-09-18. Baseline main/PR #12 merge: `1207f3870ca7fd5497b2f7374bb7287654ed8c73`.

## What was checked

The design was prepared against the repository HANDOFF, accepted Step 6 architecture, Step 6A sections 5–6, its MATLAB stimulus-generation source, and the accepted C1 interfaces. An independent, local Python design-arithmetic probe regenerated decimal constants, checked rounding rails, exercised the proposed limiter and reconstructed the source stimulus recipe. It did not execute or modify the supplied MATLAB model or golden CSV.

This documentation change contains no C2 RTL, implemented oracle, generated C2 fixtures or Vivado project. No C2 XSim, synthesis, route, board timing, bitstream or hardware execution is claimed. The 256/160/72/40/16-clock values are prescribed design slots, not measured performance.

## Why these decisions

- S18/F16 cannot represent Kp=2.18125 or 4.3625. C2 uses separate S32/F24 gain constants; L/psi use S32/F30. Reusing C1's multiplier operand widths is not a correctness requirement.
- S40/F24 state retains nine more fractional bits than the F15 voltage interface. It preserves small integration increments and keeps limiter feedback precise without inventing source-model integrator clipping.
- Wide full products and final-sum range checks avoid silent wrap and premature clipping. A finite-state overflow is a flagged rejected update, not a secretly saturated integrator. This protection is an explicit FPGA addition; it is not attributed to Step 6A.
- Exact iterative isqrt/division are easy to cross-check against independent integer arithmetic. Their launch/pipeline overhead fits a conservative fixed 256-edge core budget by design, subject to actual RTL/tool verification.
- Root ceiling, Umax floor and Q32 scale floor give a conservative pre-round scale. Final nearest rounding permits a stated one-F15-LSB norm tolerance; it is not falsely described as a strict zero-overshoot circle.
- A single-in-flight transactional core preserves old-state dependencies without claiming C1's one-sample-per-clock throughput for the recursive PI.
- The two gain profiles are elaboration-time parameters. No unreviewed live gain-update or bumpless-transfer mechanism is added.
- Internal debug access avoids turning several hundred diagnostic bits into physical top-level I/O requirements.

## Local design-preflight results

Fresh Python design probe, seed `0x6C22026`, tested 20,243 valid limiter cases: 20,000 random full S40-domain voltage pairs with valid bus, plus 243 directed rail/bus combinations.

| Check | Observed result |
|---|---:|
| Limiter maximum external component error versus mathematical ideal | 0.000022279088952359416 V |
| Maximum external norm excess above ideal Umax | 0.000021040027604612987 V |
| Prescribed component bound | 0.00006103515625 V |
| Prescribed norm-excess bound | 0.000030517578125 V |
| Reconstructed source recipe | 160 rows, two 80-row profiles |
| Recipe maximum ud_raw difference | 0.00008589466646924393 V |
| Recipe maximum uq_raw difference | 0.00011254509524147305 V |
| Recipe maximum ud_lim difference | 0.00009584864214673416 V |
| Recipe maximum uq_lim difference | 0.00011904200152199063 V |
| Recipe maximum next-integrator difference | 0.00001526803988467079 V |

The recipe probe implemented the audited 800-interval interpolated transform behavior in software and followed the read-only MATLAB stimulus source. **It is not a check of the actual committed Step 6A CSV**, and it must not be cited as the future implementation's 160-row acceptance. Codex must replay the actual CSV independently and meet the frozen gates.

The probe also reproduced the spec's first three one-amp raw/state/output values, checked positive/negative round ties and signed-96 minimum, and checked that invalid bus/overflow hold state while a valid command reset clears next state. It did not simulate handshake/reset timing.

## Remaining validation belongs to execution

Codex must produce actual source-column ranges, exact fixtures, unit/integration simulations including OLD/NEXT states, strict negative controls, portable project evidence and both gain-profile routed timing. Full-domain mathematical arguments and directed extremes supplement random arithmetic tests. No numerical gate may be relaxed because only this preliminary probe was run.

PR #12's P3 standalone fixture-count weakness remains non-blocking and outside C2 source modifications. C2 explicitly requires strict counts/parsing and manifest regeneration to prevent repeating it.
