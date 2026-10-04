// Hand implementation of the frozen B1 graph (not edited Coder output).
// Units: velocity mm/s; current Apeak. All truncating casts round to even.
`timescale 1ns/1ps
module speed_pi_sv (
  input logic clk, init_reset, clk_enable,
  input logic signed [31:0] v_ref_mmps, v_meas_mmps,
  input logic enable, pi_reset, sample_tick, angle_init, test_mode,
  output wire ce_out,
  output logic signed [24:0] iq_ref_A,
  output logic signed [41:0] iq_unlimited_A,
  output logic signed [31:0] integrator_A,
  output logic saturation_active,
  output logic signed [31:0] integrator_next_A,
  output logic signed [39:0] previous_excess_A, excess_next_A,
  output logic hard_reset, int_reset,
  output logic signed [41:0] iq_limited_A,
  output logic signed [32:0] error_mmps,
  output logic signed [39:0] P_A, KiTs_A, AW_A
);
  // The same input bank and event-output bank as the Coder baseline.
  logic signed [31:0] ref_q, meas_q;
  logic enable_q, reset_q, tick_q, angle_q, test_q, tick_previous;
  logic signed [31:0] x;
  logic signed [39:0] d;
  wire event_ce = clk_enable && tick_q && !tick_previous;
  assign ce_out = clk_enable;

  function automatic signed [39:0] round20(input logic signed [64:0] a);
    logic signed [45:0] r;
    begin
      // Arithmetic floor plus guard & (sticky | retained LSB) handles both signs.
      r = $signed({a[64],a[64:20]}) +
          $signed({1'b0,(a[19] && (a[20] || (|a[18:0])))});
      if (r > 46'sd549755813887) round20 = 40'sh7fffffffff;
      else if (r < -46'sd549755813888) round20 = 40'sh8000000000;
      else round20 = r[39:0];
    end
  endfunction
  function automatic signed [39:0] round30(input logic signed [71:0] a);
    logic signed [42:0] r;
    begin
      r = $signed({a[71],a[71:30]}) +
          $signed({1'b0,(a[29] && (a[30] || (|a[28:0])))});
      if (r > 43'sd549755813887) round30 = 40'sh7fffffffff;
      else if (r < -43'sd549755813888) round30 = 40'sh8000000000;
      else round30 = r[39:0];
    end
  endfunction
  function automatic signed [41:0] sat42(input logic signed [43:0] a);
    if (a > 44'sd2199023255551) sat42 = 42'sh1ffffffffff;
    else if (a < -44'sd2199023255552) sat42 = 42'sh20000000000;
    else sat42 = a[41:0];
  endfunction
  function automatic signed [39:0] sat40(input logic signed [43:0] a);
    if (a > 44'sd549755813887) sat40 = 40'sh7fffffffff;
    else if (a < -44'sd549755813888) sat40 = 40'sh8000000000;
    else sat40 = a[39:0];
  endfunction
  function automatic signed [43:0] sat44(input logic signed [44:0] a);
    if (a > 45'sd8796093022207) sat44 = 44'sh7ffffffffff;
    else if (a < -45'sd8796093022208) sat44 = 44'sh80000000000;
    else sat44 = a[43:0];
  endfunction
  function automatic signed [31:0] sat32(input logic signed [43:0] a);
    if (a > 44'sd2147483647) sat32 = 32'sh7fffffff;
    else if (a < -44'sd2147483648) sat32 = 32'sh80000000;
    else sat32 = a[31:0];
  endfunction
  function automatic signed [24:0] output_format(input logic signed [41:0] a);
    logic signed [27:0] r;
    begin
      r = $signed({a[41],a[41:15]}) +
          $signed({1'b0,(a[14] && (a[15] || (|a[13:0])))});
      if (r > 28'sd16777215) output_format = 25'sh0ffffff;
      else if (r < -28'sd16777216) output_format = 25'sh1000000;
      else output_format = r[24:0];
    end
  endfunction

  logic signed [32:0] e, abs_extended, signed_error;
  logic signed [31:0] abs_ref;
  logic signed [33:0] sign_product;
  logic signed [64:0] p_product, i_product;
  logic signed [71:0] aw_product;
  logic signed [39:0] p, inc, aw, d_next;
  logic signed [43:0] u_acc, excess_acc, update_stage1, update, candidate;
  logic signed [44:0] update_stage2;
  logic signed [41:0] u, limited;
  logic signed [31:0] x_next;
  logic hard, reset_int;
  always_comb begin
    e = $signed({ref_q[31],ref_q}) - $signed({meas_q[31],meas_q});
    // Positive coefficient encoded in signed 33 bits; exact B1 65/50 products.
    p_product = e * 33'sd19363296;
    i_product = e * 33'sd1549064;
    aw_product = d * 33'sd85899346;
    p = round20(p_product); inc = round20(i_product); aw = round30(aw_product);
    u_acc = $signed({{4{p[39]}},p}) + $signed({{12{x[31]}},x});
    u = sat42(u_acc);
    if (u > 42'sd1073741824) limited = 42'sd1073741824;
    else if (u < -42'sd1073741824) limited = -42'sd1073741824;
    else limited = u;
    excess_acc = $signed({{2{u[41]}},u}) - $signed({{2{limited[41]}},limited});
    d_next = sat40(excess_acc);
    // Explicit B1 44-bit first sum, then 45-bit subtraction and 44-bit cast.
    update_stage1 = $signed({{12{x[31]}},x}) + $signed({{4{inc[39]}},inc});
    update_stage2 = $signed({update_stage1[43],update_stage1}) -
                    $signed({{5{aw[39]}},aw});
    update = sat44(update_stage2);
    if (update > 44'sd536870912) candidate = 44'sd536870912;
    else if (update < -44'sd536870912) candidate = -44'sd536870912;
    else candidate = update;
    // B1 Signum is int32, but only -1/0/+1. The narrower exact sign product
    // has the same subsequent saturating s33/20 cast, including its minimum.
    abs_extended = ref_q[31] ? -$signed({ref_q[31],ref_q}) : $signed({ref_q[31],ref_q});
    abs_ref = abs_extended > 33'sd2147483647 ? 32'sh7fffffff : abs_extended[31:0];
    if (ref_q > 0) sign_product = $signed({e[32],e});
    else if (ref_q < 0) sign_product = -$signed({e[32],e});
    else sign_product = 0;
    if (sign_product > 34'sd4294967295) signed_error = 33'sh0ffffffff;
    else if (sign_product < -34'sd4294967296) signed_error = 33'sh100000000;
    else signed_error = sign_product[32:0];
    hard = reset_q || angle_q || test_q || !enable_q;
    reset_int = hard || (abs_ref < 32'sd0) ||
                ((abs_ref > 32'sd524288) && (signed_error < -33'sd3145728));
    x_next = reset_int ? 32'sd0 : sat32(candidate);
  end

  always_ff @(posedge clk) begin
    if (init_reset) begin
      ref_q<=0; meas_q<=0; enable_q<=0; reset_q<=0; tick_q<=0; angle_q<=0; test_q<=0;
      tick_previous<=1; x<=0; d<=0;
      iq_ref_A<=0; iq_unlimited_A<=0; integrator_A<=0; saturation_active<=0;
      integrator_next_A<=0; previous_excess_A<=0; excess_next_A<=0;
      hard_reset<=0; int_reset<=0; iq_limited_A<=0; error_mmps<=0;
      P_A<=0; KiTs_A<=0; AW_A<=0;
    end else if (clk_enable) begin
      ref_q<=v_ref_mmps; meas_q<=v_meas_mmps;
      enable_q<=enable; reset_q<=pi_reset; tick_q<=sample_tick; angle_q<=angle_init; test_q<=test_mode;
      tick_previous<=tick_q;
      if (event_ce) begin
        // Output uses OLD x/d. Semantic resets never clear previous excess.
        x<=x_next; d<=d_next;
        iq_ref_A<=hard ? 25'sd0 : output_format(limited);
        iq_unlimited_A<=u; integrator_A<=x; saturation_active<=(u != limited);
        integrator_next_A<=x_next; previous_excess_A<=d; excess_next_A<=d_next;
        hard_reset<=hard; int_reset<=reset_int; iq_limited_A<=limited; error_mmps<=e;
        P_A<=p; KiTs_A<=inc; AW_A<=aw;
      end
    end
  end
endmodule
