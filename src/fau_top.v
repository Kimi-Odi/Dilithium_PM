// fau_top.v - FAU      twiddle_rom + tw_addr_gen + fau
//
//
//   NTT/INTT   :   4       X   coe3_0..3; coe1/coe2    (twiddle     ROM   )
//   PWM        : coe1=X, coe2=Y, coe3=Z (  fau      )
//   stage/group: NTT/INTT   PWM    don't care
//
//     tw_addr_gen + twiddle_rom
//   (mode,stage,group) -> tw_addr -> rom -> (w0,w1,w2,w3) ->   NTT/INTT      coe1   fau
//   in_valid    twiddle   din     fau
`include "dilithium_params.vh"

module fau_top #(
    parameter W = `DILI_CW
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          in_valid,
    input  wire [1:0]    mode,        // 0=NTT, 1=INTT, 2=PWM
    input  wire [1:0]    stage,       // 0..3 (NTT/INTT); PWM
    input  wire [5:0]    group,       // 0..63 (NTT/INTT); PWM

    // PWM: coe1=X, coe2=Y, coe3=Z
    // NTT/INTT: coe3=X (4      ); coe1      ROM   ; coe2 unused
    input  wire [W-1:0]  coe1_0, coe1_1, coe1_2, coe1_3,
    input  wire [W-1:0]  coe2_0, coe2_1, coe2_2, coe2_3,
    input  wire [W-1:0]  coe3_0, coe3_1, coe3_2, coe3_3,

    output wire          out_valid,
    output wire [W-1:0]  out0, out1, out2, out3
);

    // ---- twiddle    (  ) ----
    wire [6:0]    tw_addr;
    wire [W-1:0]  w0, w1, w2, w3;

    tw_addr_gen u_ag (
        .mode(mode), .stage(stage), .group(group), .addr(tw_addr)
    );
    twiddle_rom u_rom (
        .mode(mode), .addr(tw_addr),
        .w0(w0), .w1(w1), .w2(w2), .w3(w3)
    );

    // ====================================================================
    // INTT    twiddle 5-stage delay
    //     : INTT    cascade   PE3/PE1 stage1   5 cycle, PE2/PE0 stage2
    //         PE3/PE1       PE2/PE0   c1_1/c1_2/c1_0 (twiddle),
    //             dispatch   group      twiddle,   5
    //     :   INTT mode   w0/w1/w2    5    fau (NTT   )
    //         w3   INTT   INTT_W3     ; PWM    ROM
    // ====================================================================
    reg [W-1:0] w0_q [0:4];
    reg [W-1:0] w1_q [0:4];
    reg [W-1:0] w2_q [0:4];
    integer iw;
    integer init_q;
    // synthesis translate_off
    initial begin
        for (init_q = 0; init_q < 5; init_q = init_q + 1) begin
            w0_q[init_q] = {W{1'b0}};
            w1_q[init_q] = {W{1'b0}};
            w2_q[init_q] = {W{1'b0}};
        end
    end
    // synthesis translate_on
    always @(posedge clk) begin
        if (!rst_n) begin
            for (iw=0; iw<5; iw=iw+1) begin
                w0_q[iw] <= {W{1'b0}};
                w1_q[iw] <= {W{1'b0}};
                w2_q[iw] <= {W{1'b0}};
            end
        end else begin
            w0_q[0] <= w0;
            w1_q[0] <= w1;
            w2_q[0] <= w2;
            for (iw=1; iw<5; iw=iw+1) begin
                w0_q[iw] <= w0_q[iw-1];
                w1_q[iw] <= w1_q[iw-1];
                w2_q[iw] <= w2_q[iw-1];
            end
        end
    end
    wire [W-1:0] w0_eff = (mode == 2'd1) ? w0_q[4] : w0;
    wire [W-1:0] w1_eff = (mode == 2'd1) ? w1_q[4] : w1;
    wire [W-1:0] w2_eff = (mode == 2'd1) ? w2_q[4] : w2;

    // ---- NTT/INTT   coe1   ROM    PWM        ----
    wire is_tf = (mode != 2'd2);
    wire [W-1:0] fau_c1_0 = is_tf ? w0_eff : coe1_0;
    wire [W-1:0] fau_c1_1 = is_tf ? w1_eff : coe1_1;
    wire [W-1:0] fau_c1_2 = is_tf ? w2_eff : coe1_2;
    wire [W-1:0] fau_c1_3 = is_tf ? w3     : coe1_3;

    // ----   fau ----
    fau u_fau (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .mode(mode),
        .coe1_0(fau_c1_0), .coe1_1(fau_c1_1), .coe1_2(fau_c1_2), .coe1_3(fau_c1_3),
        .coe2_0(coe2_0),   .coe2_1(coe2_1),   .coe2_2(coe2_2),   .coe2_3(coe2_3),
        .coe3_0(coe3_0),   .coe3_1(coe3_1),   .coe3_2(coe3_2),   .coe3_3(coe3_3),
        .out_valid(out_valid),
        .out0(out0), .out1(out1), .out2(out2), .out3(out3)
    );

endmodule