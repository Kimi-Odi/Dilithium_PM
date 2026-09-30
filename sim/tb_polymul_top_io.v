// tb_polymul_top_io.v - ?”¨ cell-wise serial IO è·‘å?Œæ•´ polymul (NTT -> PWM -> INTT)
`timescale 1ns/1ps
`include "dilithium_params.vh"

module tb_polymul_top_io;
    localparam W = `DILI_CW;
    localparam NPOLY = 50;

    reg clk=0, rst_n=0, start=0;
    reg [1:0] op_mode = 0;
    reg ext_we=0, ext_target=0;
    reg [5:0] ext_waddr=0, ext_raddr=0;
    reg [1:0] ext_wcell=0, ext_rcell=0;
    reg [W-1:0] ext_wdata=0;
    wire [W-1:0] ext_rdata;
    wire done;

    polymul_top_io u_dut(
        .clk(clk), .rst_n(rst_n), .start(start), .op_mode(op_mode), .done(done),
        .ext_we(ext_we), .ext_target(ext_target),
        .ext_waddr(ext_waddr), .ext_wcell(ext_wcell), .ext_wdata(ext_wdata),
        .ext_raddr(ext_raddr), .ext_rcell(ext_rcell), .ext_rdata(ext_rdata)
    );

    always #5 clk = ~clk;

    reg [W-1:0] a_poly   [0:NPOLY*256-1];
    reg [W-1:0] b_hat    [0:NPOLY*256-1];
    reg [W-1:0] c_expect [0:NPOLY*256-1];

    integer trial, i, c, errs, total_errs;
    reg [W-1:0] gv;

    initial begin
        $readmemh("pmt_a.hex",    a_poly);
        $readmemh("pmt_bhat.hex", b_hat);
        $readmemh("pmt_c.hex",    c_expect);
        total_errs = 0;

        #20 rst_n = 1;
        @(posedge clk);

        for (trial = 0; trial < NPOLY; trial = trial + 1) begin
            // --- 1) Cell-wise write a to PMM_A ---
            ext_target = 1'b0;
            ext_we = 1;
            for (i = 0; i < 64; i = i + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    @(posedge clk); #1;
                    ext_waddr = i[5:0];
                    ext_wcell = c[1:0];
                    ext_wdata = a_poly[trial*256 + i*4 + c];
                end
            end
            @(posedge clk); #1;
            ext_we = 0;

            // --- 2) Cell-wise write b_hat to PMM_B ---
            ext_target = 1'b1;
            ext_we = 1;
            for (i = 0; i < 64; i = i + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    @(posedge clk); #1;
                    ext_waddr = i[5:0];
                    ext_wcell = c[1:0];
                    ext_wdata = b_hat[trial*256 + i*4 + c];
                end
            end
            @(posedge clk); #1;
            ext_we = 0;
            ext_target = 1'b0;

            // --- 3) NTT(a) ---
            @(posedge clk); #1; op_mode = 2'd0; start = 1;
            @(posedge clk); #1; start = 0;
            wait(done);
            @(posedge clk); #1;

            // --- 4) PWM ---
            @(posedge clk); #1; op_mode = 2'd2; start = 1;
            @(posedge clk); #1; start = 0;
            wait(done);
            @(posedge clk); #1;

            // --- 5) INTT ---
            @(posedge clk); #1; op_mode = 2'd1; start = 1;
            @(posedge clk); #1; start = 0;
            wait(done);
            @(posedge clk); #1;

            // --- 6) Cell-wise read PMM_A and compare schoolbook c ---
            errs = 0;
            for (i = 0; i < 64; i = i + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    ext_raddr = i[5:0];
                    ext_rcell = c[1:0]; #1;
                    gv = ext_rdata;
                    if (gv !== c_expect[trial*256 + i*4 + c]) begin
                        if (errs < 5) $display("FAIL trial=%0d i=%0d c=%0d got=%h exp=%h",
                                                trial, i*4+c, c, gv, c_expect[trial*256+i*4+c]);
                        errs = errs + 1;
                    end
                end
            end
            $display("trial=%0d polymul errs=%0d", trial, errs);
            total_errs = total_errs + errs;
        end

        $display("tb_polymul_top_io: NPOLY=%0d  total_errs=%0d  %s",
                 NPOLY, total_errs, (total_errs==0)?"PASS":"FAIL");
        $finish;
    end

    initial begin
        #1000000000;
        $display("TIMEOUT");
        $finish;
    end
endmodule