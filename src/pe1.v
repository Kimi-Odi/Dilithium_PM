// ============================================================================
//  pe1.v -- FAU PE1
//
//  Assumption:
//    1. FAU     operation   sel
//    2. mode       pipeline flush
//    3. mod_add / mod_sub latency = 1 cycle
//
//  sel:
//    2'd0 : NTT
//    2'd1 : INTT
//    2'd2 : PWM
//
//  Function:
//    add_out = in1 + in2 mod q
//    sub_out = in1 - in2 mod q
//
//  NTT / INTT:
//    out1 = add_out delayed 4 cycles
//    out2 = sub_out delayed 4 cycles
//    total latency = 5 cycles
//
//  PWM:
//    out1 = add_out
//    out2 = sub_out
//    total latency = 1 cycle
//
//  Note:
//    PWM mode is used as the final add/sub stage for PE2.out1.
// ============================================================================

`include "dilithium_params.vh"

module pe1 #(
    parameter W = `DILI_CW
)(
    input  wire          clk,
    input  wire          rst_n,       // synchronous, active-low
    input  wire          in_valid,
    input  wire [1:0]    sel,         // 0: NTT, 1: INTT, 2: PWM

    input  wire [W-1:0]  in1,
    input  wire [W-1:0]  in2,

    output wire          out_valid,
    output wire [W-1:0]  out1,        // A0
    output wire [W-1:0]  out2         // A1
);

    localparam MODE_NTT  = 2'd0;
    localparam MODE_INTT = 2'd1;
    localparam MODE_PWM  = 2'd2;

    // ============================================================
    // valid pipes
    //
    // add/sub itself is 1-cycle latency.
    // NTT/INTT need additional 4-cycle delay after add/sub.
    //
    // Therefore:
    //   PWM      latency = 1
    //   NTT/INTT latency = 5
    // ============================================================
    reg [4:0] vld_pipe5;
    reg       vld_pipe1;

    always @(posedge clk) begin
        if (!rst_n) begin
            vld_pipe1 <= 1'b0;
            vld_pipe5 <= 5'b0;
        end else begin
            vld_pipe1 <= in_valid;
            vld_pipe5 <= {vld_pipe5[3:0], in_valid};
        end
    end

    assign out_valid = (sel == MODE_PWM) ? vld_pipe1 : vld_pipe5[4];

    // ============================================================
    // add/sub
    // ============================================================
    wire [W-1:0] add_out;
    wire [W-1:0] sub_out;
    wire         add_valid_unused;
    wire         sub_valid_unused;

    mod_add #( .W(W) ) u_add (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (1'b1),
        .x         (in1),
        .y         (in2),
        .out_valid (add_valid_unused),
        .r         (add_out)
    );

    mod_sub #( .W(W) ) u_sub (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (1'b1),
        .x         (in1),
        .y         (in2),
        .out_valid (sub_valid_unused),
        .r         (sub_out)
    );

    // ============================================================
    // delay add_out for NTT/INTT
    // ============================================================
    reg [W-1:0] pipe1_stg1, pipe1_stg2, pipe1_stg3, pipe1_stg4;

    always @(posedge clk) begin
        if (!rst_n) begin
            pipe1_stg1 <= {W{1'b0}};
            pipe1_stg2 <= {W{1'b0}};
            pipe1_stg3 <= {W{1'b0}};
            pipe1_stg4 <= {W{1'b0}};
        end else begin
            pipe1_stg1 <= add_out;
            pipe1_stg2 <= pipe1_stg1;
            pipe1_stg3 <= pipe1_stg2;
            pipe1_stg4 <= pipe1_stg3;
        end
    end

    // ============================================================
    // delay sub_out for NTT/INTT
    // ============================================================
    reg [W-1:0] pipe2_stg1, pipe2_stg2, pipe2_stg3, pipe2_stg4;

    always @(posedge clk) begin
        if (!rst_n) begin
            pipe2_stg1 <= {W{1'b0}};
            pipe2_stg2 <= {W{1'b0}};
            pipe2_stg3 <= {W{1'b0}};
            pipe2_stg4 <= {W{1'b0}};
        end else begin
            pipe2_stg1 <= sub_out;
            pipe2_stg2 <= pipe2_stg1;
            pipe2_stg3 <= pipe2_stg2;
            pipe2_stg4 <= pipe2_stg3;
        end
    end

    // ============================================================
    // output mux
    //
    // PWM:
    //   PE1 is the final add/sub stage, output immediately after 1 cycle.
    //
    // NTT/INTT:
    //   output after add/sub + 4-cycle delay.
    // ============================================================
    assign out1 = (sel == MODE_PWM) ? add_out : pipe1_stg4;
    assign out2 = (sel == MODE_PWM) ? sub_out : pipe2_stg4;

endmodule