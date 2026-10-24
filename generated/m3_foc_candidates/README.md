# PR53 bounded pipeline candidates

These are raw HDL Coder diagnostic artifacts, **not the accepted current publication**.
The original `generated/m3_foc/` remains the first-run reference until a candidate passes all numerical, RTL, timing and repeat gates.

`p1`: 29 design SV + ordinary TB +4 data files; 293-cycle output. Directed17 source/gm, next states, validation and five RTL gates pass, but 20ns OOC WNS=-71.348ns. Rejected for timing.

`p3`: Same numerical widths, locally pipelined Park/PI/limiter/InversePark/XYZ/time chain; 314-cycle output. PI observation commit is next-frame phase1 after one fast register; old-state consuming event remains pre5000. Full validation is still in progress; this directory is an auditable raw candidate copy, not a replacement of current publication.

No generated control SV is edited. Configured isolated SLX and readback, logs, path maps and machine results are under `docs/reports/m3_foc_hdl/pr53_pipeline_revision/`. Do not load an isolated model over a user model already in memory. Use scripts and a distinct batch process as described in the guide.
