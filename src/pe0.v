// ============================================================================
//  pe0.v -- FAU PE0
//
//  Mode:
//    sel = 2'd0 : NTT
//      t    = in2 * in3
//      out1 = in1 + t
//      out2 = in1 - t
//
//    sel = 2'd1 : INTT
//      s    = in1 + in2
//      d    = in1 - in2
//      out1 = s / 4
//      out2 = d * in3
//
//    sel = 2'd2 : PWM / Z + X*Y
//      t    = in2 * in3
//      out1 = in1 + t     // PWM ??? interconnect �? in1 = Z，�?�常 Z=0
//      out2 = in1 - t     // ?�常不用
//
//  Pipeline:
//    NTT/PWM:
//      cycle1~4 : in1 delay / mult
//      cycle5   : add/sub
//
//    INTT:
//      cycle1 : add/sub
//      cycle2 : div4 / mult stage1
//      cycle3 : pipe / mult stage2
//      cycle4 : pipe / mult stage3
//      cycle5 : pipe / mult stage4
//
//  Shared pipeline:
//    NTT/PWM : in1 -> pipe1 -> pipe2 -> pipe3 -> pipe4 -> add/sub
//    INTT    : add_out -> div4 -> pipe2 -> pipe3 -> pipe4 -> out1
//
//  Latency:
//    out_valid = in_valid delay 5 cycles
// ============================================================================

`include "dilithium_params.vh"

module pe0 #(
    parameter W = `DILI_CW
)(
    input  wire          clk,
    input  wire          rst_n,      // synchronous, active-low
    input  wire          in_valid,
    input  wire [1:0]    sel,        // 0: NTT, 1: INTT, 2: PWM

    input  wire [W-1:0]  in1,
    input  wire [W-1:0]  in2,
    input  wire [W-1:0]  in3,

    output wire          out_valid,
    output wire [W-1:0]  out1,       // B0
    output wire [W-1:0]  out2        // B1
);

    localparam MODE_NTT  = 2'd0;
    localparam MODE_INTT = 2'd1;
    localparam MODE_PWM  = 2'd2;

    // ============================================================
    // valid pipe: fixed latency = 5 cycles
    // ============================================================
    reg [4:0] vld_pipe;

    always @(posedge clk) begin
        if (!rst_n) begin
            vld_pipe <= 5'b0;
        end else begin
            vld_pipe <= {vld_pipe[3:0], in_valid};
        end
    end

    assign out_valid = vld_pipe[4];

    // ============================================================
    // add/sub
    //
    // NTT/PWM:
    //   x = pipe4
    //   y = mult_out
    //
    // INTT:
    //   x = in1
    //   y = in2
    // ============================================================
    wire [W-1:0] addsub_x;
    wire [W-1:0] addsub_y;

    // forward declarations for symbols used before their main declaration block
    reg  [W-1:0] pipe4;
    wire [W-1:0] mult_out;

    assign addsub_x = (sel == MODE_INTT) ? in1  : pipe4;
    assign addsub_y = (sel == MODE_INTT) ? in2  : mult_out;

    wire [W-1:0] add_out;
    wire [W-1:0] sub_out;
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
    // div4
    //
    // INTT:
    //   div4 input = add_out
    //
    // NTT/PWM:
    //   div4 output is ignored
    // ============================================================
    wire [W-1:0] div4_out;
    wire         div4_valid_unused;

    mod_div4 #( .W(W) ) u_div4 (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (1'b1),
        .x         (add_out),
        .out_valid (div4_valid_unused),
        .r         (div4_out)
    );

    // ============================================================
    // shared pipeline
    //
    // NTT/PWM:
    //   in1 -> pipe1 -> pipe2 -> pipe3 -> pipe4
    //
    // INTT:
    //   div4_out -> pipe2 -> pipe3 -> pipe4
    //
    // 注�?��??
    //   INTT 不使?�� pipe1??
    // ============================================================
    reg [W-1:0] pipe1;
    reg [W-1:0] pipe2;
    reg [W-1:0] pipe3;

    wire [W-1:0] pipe2_in;

    assign pipe2_in = (sel == MODE_INTT) ? div4_out : pipe1;

    always @(posedge clk) begin
        if (!rst_n) begin
            pipe1 <= {W{1'b0}};
            pipe2 <= {W{1'b0}};
            pipe3 <= {W{1'b0}};
            pipe4 <= {W{1'b0}};
        end else begin
            pipe1 <= in1;
            pipe2 <= pipe2_in;
            pipe3 <= pipe2;
            pipe4 <= pipe3;
        end
    end

    // ============================================================
    // in3 delay for INTT multiplier
    //
    // INTT:
    //   cycle0 : in3 input
    //   cycle1 : sub_out valid
    //   multiplier should capture sub_out with delayed in3
    // ============================================================
    reg [W-1:0] in3_d1;

    always @(posedge clk) begin
        if (!rst_n) begin
            in3_d1 <= {W{1'b0}};
        end else begin
            in3_d1 <= in3;
        end
    end

    // ============================================================
    // multiplier
    //
    // NTT/PWM:
    //   mult = in2 * in3
    //
    // INTT:
    //   mult = sub_out * in3_d1
    // ============================================================
    wire [W-1:0] mult_A;
    wire [W-1:0] mult_B;

    assign mult_A = (sel == MODE_INTT) ? sub_out : in2;
    assign mult_B = (sel == MODE_INTT) ? in3_d1  : in3;

    wire         mult_valid_unused;

    mod_mult #( .W(W) ) u_mult (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (1'b1),
        .A         (mult_A),
        .B         (mult_B),
        .out_valid (mult_valid_unused),
        .P         (mult_out)
    );

    // ============================================================
    // output mux
    //
    // sel ?���?�? operation ??��?��?��?��?��?��?��?以�?��?? sel pipeline??
    // mode ??��?��?��?��?? PE/FAU pipeline flush 完�??
    // ============================================================
    assign out1 = (sel == MODE_INTT) ? pipe4    : add_out;
    assign out2 = (sel == MODE_INTT) ? mult_out : sub_out;

endmodule