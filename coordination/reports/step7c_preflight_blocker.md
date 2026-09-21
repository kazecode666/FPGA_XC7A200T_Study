# Step 7C Task 2 topology gate

2026-09-22. PR #30 is merged at `b96a5ff617182eeab97a99e88a6e63068b79e39e`. Implementation branch: `step7c-dynamic-current-loop-cosim`.

Task 1 captured the unmodified legacy numerical baseline in commit `a95fe9a`. The 5 ms test has 101 samples at 50 us, with 100 us controller outputs held on that grid. It ran from the project root without HDL setup. The output-free Step 7B monitor was removed only in memory to avoid XSI initialization; the SLX was never saved. User SLX layout modifications and unrelated tracked/untracked changes are preserved.

Task 2 Step 3 explicitly requires stopping if the actual inverter does not have the stated pre-deadtime saturated count-to-duty structure. Read-only native SLX inspection and MATLAB `get_param` connectivity both show the same structure for phases A/B/C:

```text
PMLSM_ThreeLoop_Simple/Inverter_DeadTime/DeadTime_Voltage_Model/
  Phase_A_DeadTime/   (also Phase_B_DeadTime and Phase_C_DeadTime)

duty
 -> duty_norm          Gain = -1/PMLSM_pwm_period_counts
 -> duty_active_high   Bias = 1
 -> d_sum input 1      subtract delta_d at input 2
 -> d_sat              saturation [0,1]
 -> v0_eff_calc
```

Actual equation is `saturate(1-count/period-delta_d,0,1)`. There is no saturation between `duty_active_high` and `d_sum`. The taskbook asks for `saturate(1-count/period,0,1)` in the extracted adapter before the shared deadtime core. These differ for out-of-range legacy counts and cannot be treated as universally identical. Moving the existing saturation also changes deadtime semantics.

Recommended resolution: authorize extracting only the existing Gain/Bias pair into `Legacy_Counts_To_Duty`, retaining `d_sum -> d_sat` unchanged in the shared core. Keep the FPGA-only [0,1] interface guard as designed. Then run the planned <=1e-10 legacy equivalence check before any FPGA takeover. Alternatively, explicitly approve a new legacy input clamp as a behavior change; it would need separate endpoint validation.

No Step 7C structural model/RTL changes, dynamic FPGA plant takeover, Step 7D, or hardware operations were performed. The implementation is not complete. User requested shutdown after completion, so shutdown has not been issued while this explicit taskbook gate awaits resolution.
