"""Audit actual B1-exported vectors and matching XSim traces; no PI oracle."""
import csv
import json
import sys
from pathlib import Path


def audit(golden):
    result = {}
    for label in ("normal", "stress"):
        rows = [list(map(int, line.split())) for line in (golden / f"{label}_vectors.txt").read_text().splitlines()]
        assert all(len(r) == 21 for r in rows)
        previous = 0
        active = []
        held = [0] * 14
        x = d = 0
        for r in rows:
            if r[4] and not previous:
                assert r[9] == x and r[12] == d, "Old-state event continuity"
                x, d = r[11], r[13]
                held = r[7:]
                active.append(r)
            else:
                assert r[7:] == held, "B1 hold semantics"
            previous = r[4]
        a = active
        counts = dict(rows=len(rows), rising_events=len(a),
                      positive_linear=sum(0 < r[7] < 32768 for r in a),
                      negative_linear=sum(-32768 < r[7] < 0 for r in a),
                      zero_error=sum(r[17] == 0 for r in a),
                      positive_saturation=sum(r[10] and r[16] == 1073741824 for r in a),
                      negative_saturation=sum(r[10] and r[16] == -1073741824 for r in a),
                      aw_nonzero=sum(r[20] != 0 for r in a),
                      release_saturation=sum(a[i-1][10] and not a[i][10] for i in range(1, len(a))),
                      saturated_reversal=sum(a[i-1][10] and a[i-1][17]*a[i][17] < 0 for i in range(1, len(a))),
                      sampled_reset=sum(r[3] for r in a), disable=sum(not r[2] for r in a),
                      reenable=sum(not a[i-1][2] and a[i][2] for i in range(1, len(a))),
                      angle_reset=sum(r[5] for r in a), test_reset=sum(r[6] for r in a),
                      overspeed_reset=sum(r[15] and not r[14] for r in a),
                      hard_reset_nonzero_excess=sum(r[14] and r[13] != 0 for r in a),
                      full_raw_min=sum(r[0] == -2147483648 or r[1] == -2147483648 for r in a),
                      full_raw_max=sum(r[0] == 2147483647 or r[1] == 2147483647 for r in a))
        for name, product, shift in (("P", lambda r: r[17]*19363296, 20),
                                     ("KiTs", lambda r: r[17]*1549064, 20),
                                     ("AW", lambda r: r[12]*85899346, 30),
                                     ("output", lambda r: r[16], 15)):
            ties = [product(r) for r in a if product(r) % (1 << shift) == 1 << (shift-1)]
            counts[name + "_ties"] = dict(total=len(ties), positive=sum(t > 0 for t in ties),
                                           negative=sum(t < 0 for t in ties),
                                           retained_even=sum((t >> shift) % 2 == 0 for t in ties),
                                           retained_odd=sum((t >> shift) % 2 == 1 for t in ties))
        result[label] = counts
    # Explicitly require the key behaviours from the original plus new suite.
    for key in ("positive_linear", "negative_linear", "zero_error", "positive_saturation", "negative_saturation",
                "aw_nonzero", "release_saturation", "saturated_reversal", "sampled_reset", "disable", "reenable",
                "angle_reset", "test_reset", "overspeed_reset", "hard_reset_nonzero_excess"):
        assert sum(result[s][key] for s in result) > 0, key
    for name in ("P", "KiTs", "AW", "output"):
        for key in ("positive", "negative", "retained_even", "retained_odd"):
            assert sum(result[s][name + "_ties"][key] for s in result) > 0, (name, key)
    return result


if __name__ == "__main__":
    golden = Path(sys.argv[1])
    data = audit(golden)
    traces = [list(csv.reader(Path(path).open())) for path in sys.argv[2:]]
    if traces:
        assert all(trace == traces[0] for trace in traces), "RTL traces differ after known latency alignment"
        assert len(traces[0])-1 == sum(data[s]["rising_events"] for s in data)
        data["identical_rtl_traces"] = len(traces)
    print(json.dumps(data, indent=2))
