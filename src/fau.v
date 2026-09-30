// ============================================================================
//  fau.v -- Flexible Arithmetic Unit Top Wrapper
//
//  This module instantiates:
//    - PE0
//    - PE1
//    - PE2
//    - PE3
//    - FAU interconnector
//
//  Mode:
//    mode = 2'd0 : NTT
//    mode = 2'd1 : INTT
//    mode = 2'd2 : PWM
//
//  Coe mapping:
//    NTT / INTT:
//      coe1 = TF
//      coe2 = unused
//      coe3 = X
//
//    PWM:
//      coe1 = X
//      coe2 = Y
//      coe3 = Z, normally 0
//
//  Important:
//    1. mode must stay stable during one FAU operation.
//    2. external FSM must wait for pipeline flush before switching mode.
//    3. PE2.out1 has 4-cycle latency.
//    4. PE2.out2/out3 have 5-cycle latency.
// ============================================================================

`include "dilithium_params.vh"

module fau #(
    parameter W = `DILI_CW
)(
    input  wire          clk,
    input  wire          rst_n,       // synchronous, active-low
    input  wire          in_valid,
    input  wire [1:0]    mode,        // 0: NTT, 1: INTT, 2: PWM

    // ------------------------------------------------------------
    // Coe1
    // NTT/INTT: TF
    // PWM     : X
    // ------------------------------------------------------------
    input  wire [W-1:0]  coe1_0,
    input  wire [W-1:0]  coe1_1,
    input  wire [W-1:0]  coe1_2,
    input  wire [W-1:0]  coe1_3,

    // ------------------------------------------------------------
    // Coe2
    // NTT/INTT: unused
    // PWM     : Y
    // ------------------------------------------------------------
    input  wire [W-1:0]  coe2_0,
    input  wire [W-1:0]  coe2_1,
    input  wire [W-1:0]  coe2_2,
    input  wire [W-1:0]  coe2_3,

    // ------------------------------------------------------------
    // Coe3
    // NTT/INTT: X
    // PWM     : Z, normally 0
    // ------------------------------------------------------------
    input  wire [W-1:0]  coe3_0,
    input  wire [W-1:0]  coe3_1,
    input  wire [W-1:0]  coe3_2,
    input  wire [W-1:0]  coe3_3,

    // ------------------------------------------------------------
    // FAU outputs
    // ------------------------------------------------------------
    output wire          out_valid,
    output wire [W-1:0]  out0,
    output wire [W-1:0]  out1,
    output wire [W-1:0]  out2,
    output wire [W-1:0]  out3
);

    // ============================================================
    // PE0 wires
    // ============================================================
    wire          pe0_in_valid;
    wire [W-1:0] pe0_in1;
    wire [W-1:0] pe0_in2;
    wire [W-1:0] pe0_in3;

    wire          pe0_out_valid;
    wire [W-1:0] pe0_out1;
    wire [W-1:0] pe0_out2;

    // ============================================================
    // PE1 wires
    // ============================================================
    wire          pe1_in_valid;
    wire [W-1:0] pe1_in1;
    wire [W-1:0] pe1_in2;

    wire          pe1_out_valid;
    wire [W-1:0] pe1_out1;
    wire [W-1:0] pe1_out2;

    // ============================================================
    // PE2 wires
    // ============================================================
    wire          pe2_in_valid;
    wire [W-1:0] pe2_in1;
    wire [W-1:0] pe2_in2;
    wire [W-1:0] pe2_in3;
    wire [W-1:0] pe2_in4;
    wire [W-1:0] pe2_in5;

    wire          pe2_out_valid;
    wire          pe2_out1_valid;
    wire          pe2_out23_valid;
    wire [W-1:0] pe2_out1;
    wire [W-1:0] pe2_out2;
    wire [W-1:0] pe2_out3;

    // ============================================================
    // PE3 wires
    // ============================================================
    wire          pe3_in_valid;
    wire [W-1:0] pe3_in1;
    wire [W-1:0] pe3_in2;
    wire [W-1:0] pe3_in3;

    wire          pe3_out_valid;
    wire [W-1:0] pe3_out1;
    wire [W-1:0] pe3_out2;

    // ============================================================
    // Interconnector
    // ============================================================
    interconnector #( .W(W) ) u_interconnector (
        .clk              (clk),
        .rst_n            (rst_n),

        .in_valid         (in_valid),
        .mode             (mode),

        .coe1_0           (coe1_0),
        .coe1_1           (coe1_1),
        .coe1_2           (coe1_2),
        .coe1_3           (coe1_3),

        .coe2_0           (coe2_0),
        .coe2_1           (coe2_1),
        .coe2_2           (coe2_2),
        .coe2_3           (coe2_3),

        .coe3_0           (coe3_0),
        .coe3_1           (coe3_1),
        .coe3_2           (coe3_2),
        .coe3_3           (coe3_3),

        // PE0 outputs into interconnector
        .pe0_out_valid    (pe0_out_valid),
        .pe0_out1         (pe0_out1),
        .pe0_out2         (pe0_out2),

        // PE1 outputs into interconnector
        .pe1_out_valid    (pe1_out_valid),
        .pe1_out1         (pe1_out1),
        .pe1_out2         (pe1_out2),

        // PE2 outputs into interconnector
        .pe2_out_valid    (pe2_out_valid),
        .pe2_out1_valid   (pe2_out1_valid),
        .pe2_out23_valid  (pe2_out23_valid),
        .pe2_out1         (pe2_out1),
        .pe2_out2         (pe2_out2),
        .pe2_out3         (pe2_out3),

        // PE3 outputs into interconnector
        .pe3_out_valid    (pe3_out_valid),
        .pe3_out1         (pe3_out1),
        .pe3_out2         (pe3_out2),

        // PE0 inputs from interconnector
        .pe0_in_valid     (pe0_in_valid),
        .pe0_in1          (pe0_in1),
        .pe0_in2          (pe0_in2),
        .pe0_in3          (pe0_in3),

        // PE1 inputs from interconnector
        .pe1_in_valid     (pe1_in_valid),
        .pe1_in1          (pe1_in1),
        .pe1_in2          (pe1_in2),

        // PE2 inputs from interconnector
        .pe2_in_valid     (pe2_in_valid),
        .pe2_in1          (pe2_in1),
        .pe2_in2          (pe2_in2),
        .pe2_in3          (pe2_in3),
        .pe2_in4          (pe2_in4),
        .pe2_in5          (pe2_in5),

        // PE3 inputs from interconnector
        .pe3_in_valid     (pe3_in_valid),
        .pe3_in1          (pe3_in1),
        .pe3_in2          (pe3_in2),
        .pe3_in3          (pe3_in3),

        // FAU final outputs
        .out_valid        (out_valid),
        .out0             (out0),
        .out1             (out1),
        .out2             (out2),
        .out3             (out3)
    );

    // ============================================================
    // PE0
    // ============================================================
    pe0 #( .W(W) ) u_pe0 (
        .clk        (clk),
        .rst_n      (rst_n),
        .in_valid   (pe0_in_valid),
        .sel        (mode),

        .in1        (pe0_in1),
        .in2        (pe0_in2),
        .in3        (pe0_in3),

        .out_valid  (pe0_out_valid),
        .out1       (pe0_out1),
        .out2       (pe0_out2)
    );

    // ============================================================
    // PE1
    // ============================================================
    pe1 #( .W(W) ) u_pe1 (
        .clk        (clk),
        .rst_n      (rst_n),
        .in_valid   (pe1_in_valid),
        .sel        (mode),

        .in1        (pe1_in1),
        .in2        (pe1_in2),

        .out_valid  (pe1_out_valid),
        .out1       (pe1_out1),
        .out2       (pe1_out2)
    );

    // ============================================================
    // PE2
    // ============================================================
    pe2 #( .W(W) ) u_pe2 (
        .clk          (clk),
        .rst_n        (rst_n),
        .in_valid     (pe2_in_valid),
        .sel          (mode),

        .in1          (pe2_in1),
        .in2          (pe2_in2),
        .in3          (pe2_in3),
        .in4          (pe2_in4),
        .in5          (pe2_in5),

        .out_valid    (pe2_out_valid),
        .out1_valid   (pe2_out1_valid),
        .out23_valid  (pe2_out23_valid),

        .out1         (pe2_out1),
        .out2         (pe2_out2),
        .out3         (pe2_out3)
    );

    // ============================================================
    // PE3
    // ============================================================
    pe3 #( .W(W) ) u_pe3 (
        .clk        (clk),
        .rst_n      (rst_n),
        .in_valid   (pe3_in_valid),
        .sel        (mode),

        .in1        (pe3_in1),
        .in2        (pe3_in2),
        .in3        (pe3_in3),

        .out_valid  (pe3_out_valid),
        .out1       (pe3_out1),
        .out2       (pe3_out2)
    );

endmodule