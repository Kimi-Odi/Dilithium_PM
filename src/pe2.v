// ============================================================================
//  pe2.v -- FAU PE2
//
//  Assumption:
//    1. FAU     operation   sel
//    2. mode       pipeline flush
//    3. mod_mult latency = 4 cycles
//       mod_add / mod_sub latency = 1 cycle
//
//  sel:
//    2'd0 : NTT
//    2'd1 : INTT
//    2'd2 : PWM / Z +/- X*Y framework
//
//  Important latency:
//    out1:
//      4-cycle latency, direct mult1_out.
//      PWM mode uses this to feed PE1.
//
//    out2/out3:
//      5-cycle latency.
//      NTT/PWM: PE2 internal add/sub result.
//      INTT   : mult1_out/mult2_out.
//
//  PWM mode mapping:
//    upper path:
//      out1 = in2 * in1
//           = X1 * Y1
//      This goes to PE1, where PE1 computes Z1 + X1*Y1.
//
//    lower path:
//      out2 = in3 + in4*in5
//           = Z2 + X2*Y2
//      out3 = in3 - in4*in5
//           = Z2 - X2*Y2
//
//    PE2 internally delays in3 by 4 cycles in PWM mode,
//    so interconnector should feed raw Z2 to in3.
// ============================================================================

`include "dilithium_params.vh"

module pe2 #(
    parameter W = `DILI_CW
)(
    input  wire          clk,
    input  wire          rst_n,       // synchronous, active-low
    input  wire          in_valid,
    input  wire [1:0]    sel,         // 0: NTT, 1: INTT, 2: PWM

    input  wire [W-1:0]  in1,
    input  wire [W-1:0]  in2,
    input  wire [W-1:0]  in3,
    input  wire [W-1:0]  in4,
    input  wire [W-1:0]  in5,

    output wire          out_valid,   // same as out23_valid
    output wire          out1_valid,  // 4-cycle valid
    output wire          out23_valid, // 5-cycle valid

    output wire [W-1:0]  out1,        // B4 / PE2 mult1 output to PE1
    output wire [W-1:0]  out2,        // PE2 result 1
    output wire [W-1:0]  out3         // PE2 result 2
);

    localparam MODE_NTT  = 2'd0;
    localparam MODE_INTT = 2'd1;
    localparam MODE_PWM  = 2'd2;

    // ============================================================
    // valid pipes
    // ============================================================
    reg [3:0] vld_pipe4;
    reg [4:0] vld_pipe5;

    always @(posedge clk) begin
        if (!rst_n) begin
            vld_pipe4 <= 4'b0;
            vld_pipe5 <= 5'b0;
        end else begin
            vld_pipe4 <= {vld_pipe4[2:0], in_valid};
            vld_pipe5 <= {vld_pipe5[3:0], in_valid};
        end
    end

    assign out1_valid  = vld_pipe4[3];
    assign out23_valid = vld_pipe5[4];
    assign out_valid   = out23_valid;

    // ============================================================
    // Delay operands for INTT
    //
    // INTT:
    //   cycle0 : add/sub use in3, in4
    //   cycle1 : add_out/sub_out available
    //   cycle1 : multiplier should capture add_out/sub_out
    //            with delayed in1/in5
    // ============================================================
    reg [W-1:0] in1_d1;
    reg [W-1:0] in5_d1;

    always @(posedge clk) begin
        if (!rst_n) begin
            in1_d1 <= {W{1'b0}};
            in5_d1 <= {W{1'b0}};
        end else begin
            in1_d1 <= in1;
            in5_d1 <= in5;
        end
    end

    // ============================================================
    // Delay in3 for PWM lower Z path
    //
    // PWM lower:
    //   out2/out3 = Z2 +/- X2*Y2
    //
    //   X2*Y2 comes from mult2_out after 4 cycles.
    //   Therefore Z2 = in3 must be delayed 4 cycles.
    //
    // NTT/INTT do not use this delayed value.
    // ============================================================
    reg [W-1:0] in3_d1;
    reg [W-1:0] in3_d2;
    reg [W-1:0] in3_d3;
    reg [W-1:0] in3_d4;

    always @(posedge clk) begin
        if (!rst_n) begin
            in3_d1 <= {W{1'b0}};
            in3_d2 <= {W{1'b0}};
            in3_d3 <= {W{1'b0}};
            in3_d4 <= {W{1'b0}};
        end else begin
            in3_d1 <= in3;
            in3_d2 <= in3_d1;
            in3_d3 <= in3_d2;
            in3_d4 <= in3_d3;
        end
    end

    // ============================================================
    // Multiplier 1
    //
    // NTT:
    //   mult1 = in3 * in1
    //
    // INTT:
    //   mult1 = add_out * in1_d1
    //
    // PWM:
    //   mult1 = in2 * in1
    //   out1 = mult1_out, 4-cycle latency, sent to PE1
    // ============================================================
    wire [W-1:0] mult1_A;
    wire [W-1:0] mult1_B;

    // forward declarations for symbols used before their main declaration block
    wire [W-1:0] add_out;
    wire [W-1:0] sub_out;

    assign mult1_A =
        (sel == MODE_NTT ) ? in3     :
        (sel == MODE_INTT) ? add_out :
                              in2;

    assign mult1_B =
        (sel == MODE_INTT) ? in1_d1 : in1;

    wire [W-1:0] mult1_out;
    wire         mult1_valid_unused;

    mod_mult #( .W(W) ) u_mult1 (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (1'b1),
        .A         (mult1_A),
        .B         (mult1_B),
        .out_valid (mult1_valid_unused),
        .P         (mult1_out)
    );

    // ============================================================
    // Multiplier 2
    //
    // NTT:
    //   mult2 = in4 * in5
    //
    // INTT:
    //   mult2 = sub_out * in5_d1
    //
    // PWM:
    //   mult2 = in4 * in5
    // ============================================================
    wire [W-1:0] mult2_A;
    wire [W-1:0] mult2_B;

    assign mult2_A = (sel == MODE_INTT) ? sub_out : in4;
    assign mult2_B = (sel == MODE_INTT) ? in5_d1  : in5;

    wire [W-1:0] mult2_out;
    wire         mult2_valid_unused;

    mod_mult #( .W(W) ) u_mult2 (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (1'b1),
        .A         (mult2_A),
        .B         (mult2_B),
        .out_valid (mult2_valid_unused),
        .P         (mult2_out)
    );

    // ============================================================
    // Add/Sub
    //
    // NTT:
    //   add/sub = mult1_out +/- mult2_out
    //
    // INTT:
    //   add/sub = in3 +/- in4
    //
    // PWM:
    //   add/sub = delayed in3 +/- mult2_out
    //            = Z2 +/- X2*Y2
    // ============================================================
    wire [W-1:0] addsub_x;
    wire [W-1:0] addsub_y;

    assign addsub_x =
        (sel == MODE_NTT ) ? mult1_out :
        (sel == MODE_INTT) ? in3       :
                              in3_d4;

    assign addsub_y =
        (sel == MODE_NTT ) ? mult2_out :
        (sel == MODE_INTT) ? in4       :
                              mult2_out;

    wire         add_valid_unused;
    wire         sub_valid_unused;

    mod_add #( .W(W) ) u_add (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (1'b1),
        .x         (addsub_x),
        .y         (addsub_y),
        .out_valid (add_valid_unused),
        .r         (add_out)
    );

    mod_sub #( .W(W) ) u_sub (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (1'b1),
        .x         (addsub_x),
        .y         (addsub_y),
        .out_valid (sub_valid_unused),
        .r         (sub_out)
    );

    // ============================================================
    // Output
    //
    // out1:
    //   direct mult1_out, 4-cycle latency.
    //   In PWM, this goes to PE1 for final add/sub.
    //
    // out2/out3:
    //   5-cycle latency.
    // ============================================================
    assign out1 = mult1_out;

    assign out2 = (sel == MODE_INTT) ? mult1_out : add_out;
    assign out3 = (sel == MODE_INTT) ? mult2_out : sub_out;

endmodule