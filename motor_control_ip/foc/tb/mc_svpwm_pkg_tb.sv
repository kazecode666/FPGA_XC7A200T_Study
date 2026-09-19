`timescale 1ns/1ps

module mc_svpwm_pkg_tb;
  import mc_svpwm_pkg::*;

  task automatic fail(input string message);
    begin
      $fatal(1, "SVPWM_PKG_TB_FAIL: %s", message);
    end
  endtask

  task automatic check_round(
    input logic signed [95:0] value,
    input int unsigned shift,
    input logic signed [95:0] expected,
    input string label
  );
    logic signed [95:0] actual;
    begin
      actual = svpwm_round_shift_s96(value, shift);
      if ($isunknown(actual) || actual !== expected)
        fail($sformatf("%s value=%0d shift=%0d got=%0d expected=%0d",
                       label, value, shift, actual, expected));
    end
  endtask

  initial begin
    if (SVPWM_INPUT_WIDTH != 25 || SVPWM_INPUT_FRAC_BITS != 15 ||
        SVPWM_XYZ_WIDTH != 40 || SVPWM_DWELL_WIDTH != 34 ||
        SVPWM_DWELL_FRAC_BITS != 32 || SVPWM_DUTY_WIDTH != 26 ||
        SVPWM_DUTY_FRAC_BITS != 24)
      fail("fixed-point format constants");
    if (SVPWM_CMP_A !== 36'sd433 || SVPWM_CMP_B !== 36'sd250 ||
        SVPWM_X_COEFF !== 41'sd17321 ||
        SVPWM_YB_COEFF !== 41'sd8660 ||
        SVPWM_YA_COEFF !== 41'sd15000)
      fail("sector/XYZ coefficient constants");
    if (SVPWM_ONE_F32 !== 34'sd4294967296)
      fail("F32 unity constant");

    check_round(96'sd0, 8, 96'sd0, "zero");
    check_round(96'sd123456789, 0, 96'sd123456789, "shift-zero-positive");
    check_round(-96'sd123456789, 0, -96'sd123456789, "shift-zero-negative");
    check_round(96'sd1, 1, 96'sd1, "positive-half-tie");
    check_round(-96'sd1, 1, -96'sd1, "negative-half-tie");
    check_round(96'sd3, 1, 96'sd2, "positive-odd-tie");
    check_round(-96'sd3, 1, -96'sd2, "negative-odd-tie");
    check_round(96'sd5, 2, 96'sd1, "positive-below-half");
    check_round(-96'sd5, 2, -96'sd1, "negative-below-half");
    check_round(96'sd6, 2, 96'sd2, "positive-tie-away");
    check_round(-96'sd6, 2, -96'sd2, "negative-tie-away");
    check_round(96'sd7, 2, 96'sd2, "positive-above-half");
    check_round(-96'sd7, 2, -96'sd2, "negative-above-half");
    check_round(96'sh7fffffffffffffffffffffff, 95, 96'sd1,
                "positive-s96-rail");
    check_round(96'sh800000000000000000000000, 95, -96'sd1,
                "negative-s96-rail");

    if (!svpwm_fits_s40(96'sd549755813887) ||
        !svpwm_fits_s40(-96'sd549755813888) ||
         svpwm_fits_s40(96'sd549755813888) ||
         svpwm_fits_s40(-96'sd549755813889))
      fail("S40 rails and +/-1 neighbors");
    if (!svpwm_fits_s34(96'sd8589934591) ||
        !svpwm_fits_s34(-96'sd8589934592) ||
         svpwm_fits_s34(96'sd8589934592) ||
         svpwm_fits_s34(-96'sd8589934593))
      fail("S34 rails and +/-1 neighbors");
    if (!svpwm_fits_s26(96'sd33554431) ||
        !svpwm_fits_s26(-96'sd33554432) ||
         svpwm_fits_s26(96'sd33554432) ||
         svpwm_fits_s26(-96'sd33554433))
      fail("S26 rails and +/-1 neighbors");

    $display("ALL STEP 6C3 SVPWM PKG TESTS PASSED");
    $finish;
  end
endmodule
