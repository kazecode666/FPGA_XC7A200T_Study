# Step 6C1 Task 4: Park and inverse Park

Implemented mc_park and mc_inv_park with four signed 25x18 products each,
signed 43-bit F31 product registers, explicit sign extension into signed 44-bit
F31 accumulation, and package fxp_round_sat_f31_to_s25 conversion. There is
no product truncation, primitive instantiation, or combinational output bypass.
All data stages are valid-gated. Active-low asynchronous reset clears all valid
stages and data. Acceptance edge N produces standalone output on edge N+2.

Ports: mc_park(clk,reset_n,input_valid,i_alpha,i_beta,sin_theta,cos_theta,
output_valid,id,iq); mc_inv_park uses vd,vq inputs and v_alpha,v_beta outputs.
Data ports signed 25 F15, coefficients signed 18 F16.

TDD RED: the complete testbench was analyzed before either module existed;
xelab failed specifically because mc_park and mc_inv_park were missing.
Actual elaborator output is tdd_park_red.txt. GREEN output is tdd_park_green.txt.

Vivado Simulator 2026.1 GREEN results:
- 1141 Park fixtures and 1143 inverse fixtures, integer-exact to Python.
- 1000 independent safe-range seeded fixtures (seed 0xC1A0, +/-8 physical units).
- Actual Park RTL -> inverse-Park RTL cascade with three valid-gated coefficient
  alignment registers; fixed cascade latency N+5, integer-exact inverse outputs.
- 3299 checked outputs total, including explicit theta=0 identity/pi/2 signs,
  back-to-back traffic, periodic valid gaps, reset flushing and post-reset recovery.
- Rounding tie-1/tie/tie+1 of both signs and deliberate positive/negative saturation.
- Unsaturated RTL roundtrip maximum 5 raw F15 LSB = 0.000152587891 physical units.
  This maximum only includes safe cascade tests; full-width saturated inverse
  fixture errors are not represented as quantization errors.
- ALL STEP 6C1 PARK TESTS PASSED.

Generator changes use an independent RNG so original integration fixtures and
other generated artifacts are unchanged. The new park_roundtrip_vectors.txt
schema is alpha beta sine cosine d q back_alpha back_beta (decimal integers).
Both existing Park/inverse fixture files also include all 1000 safe cases.
Inverse fixtures additionally gain standalone rounding stimuli.

Commands (simulation working directory .Xil/step6c1_park):
E:/AMDDesignTools/2026.1/Vivado/bin/xvlog.bat -sv ../../motor_control_ip/foc/rtl/mc_fxp_pkg.sv ../../motor_control_ip/foc/rtl/mc_park.sv ../../motor_control_ip/foc/rtl/mc_inv_park.sv ../../motor_control_ip/foc/tb/mc_park_tb.sv
E:/AMDDesignTools/2026.1/Vivado/bin/xelab.bat mc_park_tb -s park_green
E:/AMDDesignTools/2026.1/Vivado/bin/xsim.bat park_green -runall

Fixture files were copied under the simulation cwd at motor_control_ip/foc/tb/vectors.
Alternatively supply VECTOR_DIR plusarg. Generator --generate then --check passed;
git diff --check passed. No synthesis or resource-inference claim is made here;
DSP use_dsp attributes request inference, and later synthesis must verify mapping.
Protected legacy files were not edited; existing user dirty files were preserved.
