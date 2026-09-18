module mc_sincos_lut (
  input  logic                     clk,
  input  logic                     reset_n,
  input  logic                     input_valid,
  input  logic [15:0]              theta_e,
  output logic                     output_valid,
  output logic signed [17:0]       sin_theta,
  output logic signed [17:0]       cos_theta
);
  import mc_fxp_pkg::*;

  (* rom_style = "block" *) logic signed [17:0] sin_qw_rom [0:4095];

  logic signed [17:0] q_read_data;
  logic signed [17:0] mirror_read_data;
  logic [1:0] quadrant_read;
  logic q_zero_read;
  logic valid_read;

  logic [11:0] q_address;
  logic [11:0] mirror_address;

  assign q_address = theta_e[13:2];
  // Twelve-bit modular subtraction is exactly 4096-q for q=1..4095.
  // q=0 wraps to address 0, but that endpoint is bypassed by SIN_COS_ONE.
  assign mirror_address = 12'd0 - q_address;

  initial begin
    $readmemh("sin_qw_4096x18.mem", sin_qw_rom);
  end

  // The ROM output registers deliberately have no asynchronous reset so the
  // two ports remain inference-friendly.  Reads occur only for accepted input.
  always_ff @(posedge clk) begin
    if (input_valid) begin
      q_read_data <= sin_qw_rom[q_address];
      if (q_address != 12'd0)
        mirror_read_data <= sin_qw_rom[mirror_address];
    end
  end

  // One registered ROM-read stage followed by quadrant reconstruction gives
  // output for a transaction at the clock edge after its input sampling edge.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      quadrant_read <= '0;
      q_zero_read    <= 1'b0;
      valid_read     <= 1'b0;
      output_valid   <= 1'b0;
      sin_theta      <= '0;
      cos_theta      <= '0;
    end else begin
      valid_read   <= input_valid;
      output_valid <= valid_read;

      if (input_valid) begin
        quadrant_read <= theta_e[15:14];
        q_zero_read    <= (theta_e[13:2] == 12'd0);
      end

      if (valid_read) begin
        case (quadrant_read)
          2'd0: begin
            sin_theta <= q_read_data;
            cos_theta <= q_zero_read ? SIN_COS_ONE : mirror_read_data;
          end
          2'd1: begin
            sin_theta <= q_zero_read ? SIN_COS_ONE : mirror_read_data;
            cos_theta <= -q_read_data;
          end
          2'd2: begin
            sin_theta <= -q_read_data;
            cos_theta <= q_zero_read ? -SIN_COS_ONE : -mirror_read_data;
          end
          default: begin
            sin_theta <= q_zero_read ? -SIN_COS_ONE : -mirror_read_data;
            cos_theta <= q_read_data;
          end
        endcase
      end
    end
  end
endmodule
