# Study-L1 Checkpoint D system comparison

All values use the same 100 us observation grid without time shifts. The new_result plot marks observed completion count increments; exact per-event times are in speed_events.csv.

Hand SV retains its Checkpoint C 50 MHz setup failure (WNS −1.957 ns). System co-simulation does not establish 50 MHz hardware readiness.

## speed_ideal

All three case gates and common configuration checks passed.

| Implementation | Speed results | Physical latency / ns | Worst speed-window RMSE / mm/s | iq RMSE / A |
|---|---:|---:|---:|---:|
| original | 1200 | 0 | 0.0926415902 | 0.000541208732 |
| coder_baseline | 1200 | 30 | 0.0910688383 | 0.000538910451 |
| hand_sv | 1200 | 30 | 0.0910688383 | 0.000538910451 |

| Unshifted pair | Max Δv / mm/s | Max Δspeed PI iq_ref / A | Max Δiq / A |
|---|---:|---:|---:|
| original_vs_coder_baseline | 0.0419888668 | 0.00897777147 | 0.00470987657 |
| original_vs_hand_sv | 0.0419888668 | 0.00897777147 | 0.00470987657 |
| coder_baseline_vs_hand_sv | 0 | 0 | 0 |

FOC accepted/active IDs and fault/reset status are identical on the common trace grid. Full-rate timing/coverage was checked by the unchanged Step7D evaluator. Coder baseline and Hand SV are also exactly identical in all seven compared numerical fields without time shifts.

## speed_deadtime

All three case gates and common configuration checks passed.

| Implementation | Speed results | Physical latency / ns | Worst speed-window RMSE / mm/s | iq RMSE / A |
|---|---:|---:|---:|---:|
| original | 1200 | 0 | 0.236091294 | 0.00352830927 |
| coder_baseline | 1200 | 30 | 0.247049518 | 0.00359459885 |
| hand_sv | 1200 | 30 | 0.247049518 | 0.00359459885 |

| Unshifted pair | Max Δv / mm/s | Max Δspeed PI iq_ref / A | Max Δiq / A |
|---|---:|---:|---:|
| original_vs_coder_baseline | 0.615144166 | 0.0130409785 | 0.0125778948 |
| original_vs_hand_sv | 0.615144166 | 0.0130409785 | 0.0125778948 |
| coder_baseline_vs_hand_sv | 0 | 0 | 0 |

FOC accepted/active IDs and fault/reset status are identical on the common trace grid. Full-rate timing/coverage was checked by the unchanged Step7D evaluator. Coder baseline and Hand SV are also exactly identical in all seven compared numerical fields without time shifts.

## convergence_prefix

All three case gates and common configuration checks passed.

| Implementation | Speed results | Physical latency / ns | Worst speed-window RMSE / mm/s | iq RMSE / A |
|---|---:|---:|---:|---:|
| original | 200 | 0 | prefix sanity | prefix sanity |
| coder_baseline | 200 | 30 | prefix sanity | prefix sanity |
| hand_sv | 200 | 30 | prefix sanity | prefix sanity |

| Unshifted pair | Max Δv / mm/s | Max Δspeed PI iq_ref / A | Max Δiq / A |
|---|---:|---:|---:|
| original_vs_coder_baseline | 0.00958501106 | 0.000907501772 | 0.00163234666 |
| original_vs_hand_sv | 0.00958501106 | 0.000907501772 | 0.00163234666 |
| coder_baseline_vs_hand_sv | 0 | 0 | 0 |

FOC accepted/active IDs and fault/reset status are identical on the common trace grid. Full-rate timing/coverage was checked by the unchanged Step7D evaluator. Coder baseline and Hand SV are also exactly identical in all seven compared numerical fields without time shifts.

