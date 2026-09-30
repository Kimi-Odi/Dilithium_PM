// tb_ntt_intt_engine.v -   INTT(NTT(x)) == x bit-exact
`timescale 1ns/1ps
`include "dilithium_params.vh"

module tb_ntt_intt_engine;
    localparam W = `DILI_CW;
    localparam NPOLY = 20;

    reg clk=0, rst_n=0, start=0;
    reg [1:0] op_mode=0;
    reg ext_we=0;
    reg [5:0]   ext_waddr=0, ext_raddr=0;
    reg [4*W-1:0] ext_wdata=0;
    wire [4*W-1:0] ext_rdata;
    wire done;

    ntt_intt_engine u_dut(
        .clk(clk), .rst_n(rst_n), .start(start), .op_mode(op_mode), .done(done),
        .ext_we(ext_we), .ext_waddr(ext_waddr), .ext_wdata(ext_wdata),
        .ext_raddr(ext_raddr), .ext_rdata(ext_rdata)
    );

    always #5 clk = ~clk;

    reg [W-1:0] in_poly  [0:NPOLY*256-1];
    reg [W-1:0] exp_ntt  [0:NPOLY*256-1];
    integer trial, i, errs, total_errs;
    reg [W-1:0] got;

    initial begin
        $readmemh("ntt_in.hex",  in_poly);
        $readmemh("ntt_out.hex", exp_ntt);
        total_errs = 0;

        #20 rst_n = 1;
        @(posedge clk);

        for (trial = 0; trial < NPOLY; trial = trial + 1) begin
            //   input poly   PMM
            ext_we = 1;
            for (i = 0; i < 64; i = i + 1) begin
                @(posedge clk); #1;
                ext_waddr = i[5:0];
                ext_wdata = { in_poly[trial*256+i*4+3], in_poly[trial*256+i*4+2],
                              in_poly[trial*256+i*4+1], in_poly[trial*256+i*4+0] };
            end
            @(posedge clk); #1;
            ext_we = 0;

            // Sanity
            begin: sanity_w
                integer ew;
                reg [W-1:0] gv;
                ew = 0;
                for (i = 0; i < 64; i = i + 1) begin
                    ext_raddr = i[5:0]; #1;
                    gv = ext_rdata[1*W-1:0*W];
                    if (gv !== in_poly[trial*256+i*4+0]) ew = ew + 1;
                    gv = ext_rdata[2*W-1:1*W];
                    if (gv !== in_poly[trial*256+i*4+1]) ew = ew + 1;
                    gv = ext_rdata[3*W-1:2*W];
                    if (gv !== in_poly[trial*256+i*4+2]) ew = ew + 1;
                    gv = ext_rdata[4*W-1:3*W];
                    if (gv !== in_poly[trial*256+i*4+3]) ew = ew + 1;
                end
                $display("trial=%0d write-sanity errs=%0d", trial, ew);
            end

            //   NTT
            @(posedge clk); #1;
            op_mode = 2'd0; start = 1;
            @(posedge clk); #1; start = 0;
            wait (done);
            @(posedge clk); #1;

            //    NTT   PMM
            begin: chk_ntt
                integer errs_n;
                reg [W-1:0] gv;
                errs_n = 0;
                for (i = 0; i < 64; i = i + 1) begin
                    ext_raddr = i[5:0]; #1;
                    gv = ext_rdata[1*W-1:0*W];
                    if (gv !== exp_ntt[trial*256+i*4+0]) errs_n = errs_n + 1;
                    gv = ext_rdata[2*W-1:1*W];
                    if (gv !== exp_ntt[trial*256+i*4+1]) errs_n = errs_n + 1;
                    gv = ext_rdata[3*W-1:2*W];
                    if (gv !== exp_ntt[trial*256+i*4+2]) errs_n = errs_n + 1;
                    gv = ext_rdata[4*W-1:3*W];
                    if (gv !== exp_ntt[trial*256+i*4+3]) errs_n = errs_n + 1;
                end
                $display("trial=%0d NTT-after errs=%0d", trial, errs_n);
                if (trial == 0) begin
                    ext_raddr = 0; #1;
                    $display("  trial=0 raddr=0 got_word=%h", ext_rdata);
                    $display("  trial=0 raddr=0 exp cells (0..3) = %h %h %h %h",
                        exp_ntt[0], exp_ntt[1], exp_ntt[2], exp_ntt[3]);
                    ext_raddr = 1; #1;
                    $display("  trial=0 raddr=1 got_word=%h", ext_rdata);
                    $display("  trial=0 raddr=1 exp cells (4..7) = %h %h %h %h",
                        exp_ntt[4], exp_ntt[5], exp_ntt[6], exp_ntt[7]);
                end
            end

            //   INTT
            @(posedge clk); #1;
            op_mode = 2'd1; start = 1;
            @(posedge clk); #1; start = 0;
            wait (done);
            @(posedge clk); #1;

            //      input
            errs = 0;
            for (i = 0; i < 64; i = i + 1) begin
                ext_raddr = i[5:0]; #1;
                got = ext_rdata[1*W-1:0*W];
                if (got !== in_poly[trial*256+i*4+0]) begin
                    if (errs < 3) $display("FAIL trial=%0d i=%0d c=0 got=%h exp=%h", trial, i*4+0, got, in_poly[trial*256+i*4+0]);
                    errs = errs + 1;
                end
                got = ext_rdata[2*W-1:1*W];
                if (got !== in_poly[trial*256+i*4+1]) begin
                    if (errs < 3) $display("FAIL trial=%0d i=%0d c=1 got=%h exp=%h", trial, i*4+1, got, in_poly[trial*256+i*4+1]);
                    errs = errs + 1;
                end
                got = ext_rdata[3*W-1:2*W];
                if (got !== in_poly[trial*256+i*4+2]) begin
                    if (errs < 3) $display("FAIL trial=%0d i=%0d c=2 got=%h exp=%h", trial, i*4+2, got, in_poly[trial*256+i*4+2]);
                    errs = errs + 1;
                end
                got = ext_rdata[4*W-1:3*W];
                if (got !== in_poly[trial*256+i*4+3]) begin
                    if (errs < 3) $display("FAIL trial=%0d i=%0d c=3 got=%h exp=%h", trial, i*4+3, got, in_poly[trial*256+i*4+3]);
                    errs = errs + 1;
                end
            end
            $display("trial=%0d  INTT(NTT(x))==x errs=%0d", trial, errs);
            total_errs = total_errs + errs;
        end

        $display("tb_ntt_intt_engine: NPOLY=%0d total_errs=%0d %s",
                 NPOLY, total_errs, (total_errs==0)?"PASS":"FAIL");
        $finish;
    end

    initial begin #30000000; $display("TIMEOUT"); $finish; end
endmodule