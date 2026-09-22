# Task 1 baseline accepted

Scenarios/windows frozen in c45420a before measurements. Actual R2026b, backend 0, no HDL setup, no model save.

- Fresh 5ms/17-signal native trace versus preserved original legacy trace: all differences 0.
- Full 1.20s native 50us speed_deadtime and position_deadtime captured for later before/after equivalence.
- Five matched 1us normal performance scenarios passed their frozen speed/position/current gates.
- Actual execution callbacks: 12001 current, 1200 speed, 120 position events over each 1.20s run. First events 0, 0.0009, 0.0099s; periods 100us/1ms/10ms.
- Host position reference reaches +/-1mm at 0.4375s, before 0.70s. Existing position velocity feedforward remains zero; no new derivative path was added.
- All common-grid signals finite; full-rate peaks computed before normalization. Audited zero speed-block initial outputs precede first execution; later samples use previous-value holding.
- Toolkit produced layout/library-link warnings in the temporary model and two expected unconnected Host outputs after request-source replacement. They are not performance passes. The SLX was not saved.

Read baseline_before.txt for exact configuration, metrics, phase/counts and raw MAT directory. baseline_verification.txt freshly checks each saved artifact. Earlier failed runs are retained and explicitly invalidated, not reused as PASS.

The local as-found Simple SLX is included in the baseline commit to preserve user-requested layout before functional wiring. Other user changes remain unstaged.
