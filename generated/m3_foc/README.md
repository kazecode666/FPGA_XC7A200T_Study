# Generated FOC SystemVerilog

Raw HDL Coder R2026b output from the latest local `PMLSM_FOC_FixedPoint.slx/FOC_DUT`; do not edit algorithm RTL by hand. Regenerate through `scripts/m3_foc_hdl.m` and `scripts/m3_foc_codegen_config.m`.

`manifest.json` declares all29 design SV, one ordinary SV TB, one data file and compile order/SHA256. Provenance absolute paths are informational; compilation resolves all dependencies relative to this directory. Independent source/gm/RTL tests and repeat builds are linked in [the report](../../coordination/reports/m3_foc_systemverilog_rtl_verification.md).

**Not accepted for hardware: 20ns OOC synthesis timing FAIL, WNS−58.833ns.** Functional bit/state tests pass; capacity fits. No routed timing, board IO or hardware signoff. The generated `ce_out` is fast clock-enable, not frame-valid; consult [the timing contract](../../docs/FOC_HDL_TIMING_CONTRACT.md).
