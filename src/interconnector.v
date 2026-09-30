// ============================================================================
//  fau_interconnector.v
//
//  FAU PE interconnection layer
//
//  This module only does routing / muxing.
//  PE0~PE3 should be instantiated in fau.v.
//
//  Mode:
//    2'd0 : NTT
//    2'd1 : INTT
//    2'd2 : PWM
//
//  Coe mapping:
//    NTT  : Coe1/Coe2/Coe3 = TF / - / X
//    INTT : Coe1/Coe2/Coe3 = TF / - / X
//    PWM  : Coe1/Coe2/Coe3 = X  / Y / 0
//
//  Datapath:
//    NTT  : PE0, PE2 -> PE1, PE3
//    INTT : PE1, PE3 -> PE0, PE2
//    PWM  : PE0, PE2, PE3 + PE2.out1 -> PE1
//
//  Important:
//    1. mode must remain stable during one operation.
//    2. external FSM must wait for pipeline flush before changing mode.
//    3. PE2.out1 is 4-cycle valid, used by PE1 in PWM.
//    4. PE2.out2/out3 are 5-cycle valid.
// ============================================================================

`include "dilithium_params.vh"

module interconnector #(
    parameter W = `DILI_CW
)(
    input  wire          clk,
    input  wire          rst_n,

    input  wire          in_valid,
    input  wire [1:0]    mode,

    // ------------------------------------------------------------
    // Coe inputs
    //
    // NTT / INTT:
    //   coe1_x = TF
    //   coe2_x = unused
    //   coe3_x = X
    //
    // PWM:
    //   coe1_x = X
    //   coe2_x = Y
    //   coe3_x = Z, usually 0
    // ------------------------------------------------------------
    input  wire [W-1:0]  coe1_0,
    input  wire [W-1:0]  coe1_1,
    input  wire [W-1:0]  coe1_2,
    input  wire [W-1:0]  coe1_3,

    input  wire [W-1:0]  coe2_0,
    input  wire [W-1:0]  coe2_1,
    input  wire [W-1:0]  coe2_2,
    input  wire [W-1:0]  coe2_3,

    input  wire [W-1:0]  coe3_0,
    input  wire [W-1:0]  coe3_1,
    input  wire [W-1:0]  coe3_2,
    input  wire [W-1:0]  coe3_3,

    // ------------------------------------------------------------
    // PE0 outputs
    // ------------------------------------------------------------
    input  wire          pe0_out_valid,
    input  wire [W-1:0]  pe0_out1,
    input  wire [W-1:0]  pe0_out2,

    // ------------------------------------------------------------
    // PE1 outputs
    // ------------------------------------------------------------
    input  wire          pe1_out_valid,
    input  wire [W-1:0]  pe1_out1,
    input  wire [W-1:0]  pe1_out2,

    // ------------------------------------------------------------
    // PE2 outputs
    // ------------------------------------------------------------
    input  wire          pe2_out_valid,
    input  wire          pe2_out1_valid,
    input  wire          pe2_out23_valid,
    input  wire [W-1:0]  pe2_out1,
    input  wire [W-1:0]  pe2_out2,
    input  wire [W-1:0]  pe2_out3,

    // ------------------------------------------------------------
    // PE3 outputs
    // ------------------------------------------------------------
    input  wire          pe3_out_valid,
    input  wire [W-1:0]  pe3_out1,
    input  wire [W-1:0]  pe3_out2,

    // ------------------------------------------------------------
    // PE0 inputs
    // ------------------------------------------------------------
    output wire          pe0_in_valid,
    output wire [W-1:0]  pe0_in1,
    output wire [W-1:0]  pe0_in2,
    output wire [W-1:0]  pe0_in3,

    // ------------------------------------------------------------
    // PE1 inputs
    // ------------------------------------------------------------
    output wire          pe1_in_valid,
    output wire [W-1:0]  pe1_in1,
    output wire [W-1:0]  pe1_in2,

    // ------------------------------------------------------------
    // PE2 inputs
    // ------------------------------------------------------------
    output wire          pe2_in_valid,
    output wire [W-1:0]  pe2_in1,
    output wire [W-1:0]  pe2_in2,
    output wire [W-1:0]  pe2_in3,
    output wire [W-1:0]  pe2_in4,
    output wire [W-1:0]  pe2_in5,

    // ------------------------------------------------------------
    // PE3 inputs
    // ------------------------------------------------------------
    output wire          pe3_in_valid,
    output wire [W-1:0]  pe3_in1,
    output wire [W-1:0]  pe3_in2,
    output wire [W-1:0]  pe3_in3,

    // ------------------------------------------------------------
    // FAU final outputs
    // ------------------------------------------------------------
    output wire          out_valid,
    output wire [W-1:0]  out0,
    output wire [W-1:0]  out1,
    output wire [W-1:0]  out2,
    output wire [W-1:0]  out3
);

    localparam MODE_NTT  = 2'd0;
    localparam MODE_INTT = 2'd1;
    localparam MODE_PWM  = 2'd2;

    wire [W-1:0] ZERO;
    assign ZERO = {W{1'b0}};

    // ============================================================
    // Delay Coe3 for PWM Z path
    //
    // PWM:
    //   PE2.out1 = X1*Y1 appears after 4 cycles.
    //   PE1 then computes Z1 + PE2.out1.
    //   Therefore Z1 must be delayed 4 cycles before feeding PE1.
    //
    //   PE2 lower path internally computes Z2 + X2*Y2,
    //   but PE2 does not delay its in3 by itself.
    //   Therefore Z2 must be delayed 4 cycles before feeding PE2.in3.
    //
    // For pure PWM in the paper, Coe3 is 0, so this delay still works.
    // ============================================================
    reg [W-1:0] coe3_1_d1, coe3_1_d2, coe3_1_d3, coe3_1_d4;

    always @(posedge clk) begin
        if (!rst_n) begin
            coe3_1_d1 <= {W{1'b0}};
            coe3_1_d2 <= {W{1'b0}};
            coe3_1_d3 <= {W{1'b0}};
            coe3_1_d4 <= {W{1'b0}};

        end else begin
            coe3_1_d1 <= coe3_1;
            coe3_1_d2 <= coe3_1_d1;
            coe3_1_d3 <= coe3_1_d2;
            coe3_1_d4 <= coe3_1_d3;

        end
    end

    // ============================================================
    // Valid routing helpers
    // ============================================================

    wire ntt_stage1_valid;
    wire intt_stage1_valid;

    assign ntt_stage1_valid  = pe0_out_valid & pe2_out23_valid;
    assign intt_stage1_valid = pe1_out_valid & pe3_out_valid;

    // ============================================================
    // PE0 input routing
    //
    // NTT:
    //   PE0 first stage:
    //     in1 = Coe3,0 = X0
    //     in2 = Coe3,1 = X1
    //     in3 = Coe1,0 = TF0
    //
    // INTT:
    //   PE0 second stage, fed by PE1:
    //     in1 = PE1.out1
    //     in2 = PE1.out2
    //     in3 = Coe1,0 = TF0
    //
    // PWM:
    //   PE0 computes Coe3,0 + Coe1,0 * Coe2,0
    //     in1 = Coe3,0 = Z0, usually 0
    //     in2 = Coe1,0 = X0
    //     in3 = Coe2,0 = Y0
    // ============================================================
    assign pe0_in_valid =
        (mode == MODE_INTT) ? pe1_out_valid :
                              in_valid;

    assign pe0_in1 =
        (mode == MODE_INTT) ? pe1_out1 :
        (mode == MODE_PWM ) ? coe3_0  :
                              coe3_0;

    assign pe0_in2 =
        (mode == MODE_INTT) ? pe3_out1 :
        (mode == MODE_PWM ) ? coe1_0  :
                              coe3_1;

    assign pe0_in3 =
        (mode == MODE_PWM ) ? coe2_0 :
                              coe1_0;

    // ============================================================
    // PE2 input routing
    //
    // PE2 port meaning in current pe2.v:
    //
    // NTT:
    //   mult1 = in3 * in1 = Coe3,2 * Coe1,1
    //   mult2 = in4 * in5 = Coe3,3 * Coe1,2
    //   out2/out3 = mult1 +/- mult2
    //
    // INTT:
    //   add/sub = in3 +/- in4 = PE3.out1 +/- PE3.out2
    //   mult1 = add_out * in1
    //   mult2 = sub_out * in5
    //
    // PWM:
    //   upper:
    //     out1 = in2 * in1 = Coe1,1 * Coe2,1
    //
    //   lower:
    //     out2 = in3 + in4*in5 = Coe3,2 + Coe1,2*Coe2,2
    // ============================================================
    assign pe2_in_valid =
        (mode == MODE_INTT) ? pe3_out_valid :
                              in_valid;

    assign pe2_in1 =
        (mode == MODE_PWM ) ? coe2_1 :
                              coe1_1;

    assign pe2_in2 =
        (mode == MODE_PWM ) ? coe1_1 :
                              ZERO;

    assign pe2_in3 =
        (mode == MODE_NTT ) ? coe3_2   :
        (mode == MODE_INTT) ? pe1_out2 :
                            coe3_2;     // PWM: raw Z2, PE2      delay

    assign pe2_in4 =
        (mode == MODE_NTT ) ? coe3_3   :
        (mode == MODE_INTT) ? pe3_out2 :
                              coe1_2;

    assign pe2_in5 =
        (mode == MODE_PWM ) ? coe2_2 :
                              coe1_2;

    // ============================================================
    // PE1 input routing
    //
    // NTT:
    //   PE1 second stage:
    //     in1 = PE0.out1 = B0
    //     in2 = PE2.out2 = B2
    //
    // INTT:
    //   PE1 first stage:
    //     in1 = Coe3,0
    //     in2 = Coe3,1
    //
    // PWM:
    //   PE1 final add/sub for PE2 upper product:
    //     in1 = delayed Coe3,1 = Z1
    //     in2 = PE2.out1 = Coe1,1 * Coe2,1
    // ============================================================
    assign pe1_in_valid =
        (mode == MODE_NTT ) ? ntt_stage1_valid  :
        (mode == MODE_PWM ) ? pe2_out1_valid    :
                              in_valid;

    assign pe1_in1 =
        (mode == MODE_NTT ) ? pe0_out1  :
        (mode == MODE_PWM ) ? coe3_1_d4 :
                              coe3_0;

    assign pe1_in2 =
        (mode == MODE_NTT ) ? pe2_out2 :
        (mode == MODE_PWM ) ? pe2_out1 :
                              coe3_1;

    // ============================================================
    // PE3 input routing
    //
    // NTT:
    //   PE3 second stage:
    //     in1 = PE0.out2 = B1
    //     in2 = PE2.out3 = B3
    //     in3 = Coe1,3 = TF3
    //
    // INTT:
    //   PE3 first stage:
    //     in1 = Coe3,2
    //     in2 = Coe3,3
    //     in3 = Coe1,3
    //
    // PWM:
    //   PE3 computes Coe3,3 + Coe1,3 * Coe2,3
    //     in1 = Coe3,3 = Z3
    //     in2 = Coe1,3 = X3
    //     in3 = Coe2,3 = Y3
    // ============================================================
    assign pe3_in_valid =
        (mode == MODE_NTT ) ? ntt_stage1_valid :
                              in_valid;

    assign pe3_in1 =
        (mode == MODE_NTT ) ? pe0_out2 :
        (mode == MODE_PWM ) ? coe3_3   :
                              coe3_2;

    assign pe3_in2 =
        (mode == MODE_NTT ) ? pe2_out3 :
        (mode == MODE_PWM ) ? coe1_3   :
                              coe3_3;

    assign pe3_in3 =
        (mode == MODE_PWM ) ? coe2_3 :
                              coe1_3;

    // ============================================================
    // Final output routing
    //
    // NTT:
    //   final outputs from PE1 and PE3
    //
    // INTT:
    //   final outputs from PE0 and PE2
    //
    // PWM:
    //   out0 = PE0.out1 = Z0 + X0*Y0
    //   out1 = PE1.out1 = Z1 + X1*Y1
    //   out2 = PE2.out2 = Z2 + X2*Y2
    //   out3 = PE3.out1 = Z3 + X3*Y3
    // ============================================================
    assign out0 =
        (mode == MODE_NTT ) ? pe1_out1 :
        (mode == MODE_INTT) ? pe0_out1 :
                              pe0_out1;

    assign out1 =
        (mode == MODE_NTT ) ? pe1_out2 :
        (mode == MODE_INTT) ? pe0_out2 :
                              pe1_out1;

    assign out2 =
        (mode == MODE_NTT ) ? pe3_out1 :
        (mode == MODE_INTT) ? pe2_out2 :
                              pe2_out2;

    assign out3 =
        (mode == MODE_NTT ) ? pe3_out2 :
        (mode == MODE_INTT) ? pe2_out3 :
                              pe3_out1;

    assign out_valid =
        (mode == MODE_NTT ) ? (pe1_out_valid & pe3_out_valid) :
        (mode == MODE_INTT) ? (pe0_out_valid & pe2_out23_valid) :
        (mode == MODE_PWM ) ? (pe0_out_valid & pe1_out_valid & pe2_out23_valid & pe3_out_valid) :
                              1'b0;

endmodule