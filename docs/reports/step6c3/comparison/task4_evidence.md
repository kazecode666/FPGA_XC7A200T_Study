# Step 6C3 Task 4 comparison and protocol evidence

`python scripts/step6c3_svpwm_reference.py --check` passed the actual 160-row
Step 6A replay (80 rows per profile). The normalized absolute-error maxima
were `t1=0.000015665495423478064619140625`,
`t2=0.000008176039042934234619140625`,
`duty_u=0.0000042531884765625`, and
`duty_v=duty_w=0.000011942187652587890625`, all below `0.00005`.

The four allowed and observed boundary sector rows were printed explicitly:

| Row | Profile | Case | A raw | B raw | Source | Oracle |
|---:|---|---|---:|---:|---:|---:|
| 50 | real_commissioning | edge_1_1.732 | 71475 | 123795 | 3 | 1 |
| 62 | real_commissioning | edge_1_-1.732 | 71475 | -123795 | 2 | 6 |
| 130 | MIL_PI_override | edge_1_1.732 | 142950 | 247590 | 3 | 1 |
| 142 | MIL_PI_override | edge_1_-1.732 | 142950 | -247590 | 2 | 6 |

The comparison rejects any additional mismatch and also requires exactly
these four rows before reporting success.

Vivado Simulator 2026.1 freshly compiled and elaborated the production
sources and ran all 790 fixed vectors (22 directed plus 768 seeded with
`0x6c32026`). The final log reported:

```text
PROTOCOL_BUSY_INPUT_IMMUNITY_PASS rows=790 poisoned_cycles=101120
PROTOCOL_FIXED_LATENCY_PASS responses=790 latency=128
PROTOCOL_EARLIEST_NEXT_ACCEPT_PASS completion_edges_blocked=790 following_edge_accepts=789
PROTOCOL_RESET_ABORT_PASS aborts=1 stale_responses=0
ALL STEP 6C3 SECTOR SVPWM TESTS PASSED rows=790 accepted=791 responses=790 latency=128 aborts=1 poisoned_cycles=101120
```

Compile, elaboration and XSim each exited zero. The required overall PASS and
all four protocol markers were present; no `Fatal:` or `ERROR:` marker was
present. The retained final log is
`.superpowers/sdd/step6c3_sector_svpwm_plan/task4_final4/xsim.log`.

The production RTL, accepted Step 6A source, generated fixtures and comparison
CSV were unchanged.
