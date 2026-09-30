// tb_ntt_engine.v -   ntt_engine     256-point bit-exact
`timescale 1ns/1ps
`include "dilithium_params.vh"

module tb_ntt_engine;
    localparam W = `DILI_CW;
    localparam NPOLY = 20;  //   4     poly

    reg clk=0, rst_n=0, start=0;
    reg ext_we=0;
    reg [5:0]   ext_waddr=0, ext_raddr=0;
    reg [4*W-1:0] ext_wdata=0;
    wire [4*W-1:0] ext_rdata;
    wire done;

    ntt_engine u_dut(
        .clk(clk), .rst_n(rst_n), .start(start), .done(done),
        .ext_we(ext_we), .ext_waddr(ext_waddr), .ext_wdata(ext_wdata),
        .ext_raddr(ext_raddr), .ext_rdata(ext_rdata)
    );

    always #5 clk = ~clk;

    //         Python        256   23-bit       hex string
    //     TB     2   hex
    //   poly_in_${i}.hex: 256      6-hex 1     (input poly)
    //   poly_ntt_${i}.hex: 256      ntt_ref output
    reg [W-1:0] in_poly  [0:NPOLY*256-1];
    reg [W-1:0] exp_ntt  [0:NPOLY*256-1];

    integer trial, i, errs, total_errs;
    reg [W-1:0] got_v;

    initial begin
        $readmemh("ntt_in.hex",  in_poly);
        $readmemh("ntt_out.hex", exp_ntt);
        total_errs = 0;

        #20 rst_n = 1;
        @(posedge clk);

        for (trial = 0; trial < NPOLY; trial = trial + 1) begin
            //        poly   PMM (64 logical words)
            ext_we = 1;
            for (i = 0; i < 64; i = i + 1) begin
                @(posedge clk); #1;
                ext_waddr = i[5:0];
                ext_wdata = { in_poly[trial*256 + i*4 + 3],
                              in_poly[trial*256 + i*4 + 2],
                              in_poly[trial*256 + i*4 + 1],
                              in_poly[trial*256 + i*4 + 0] };
            end
            @(posedge clk); #1;
            ext_we = 0;

            //     Sanity:          input
            begin: sanity
                integer errs_w;
                reg [W-1:0] gv;
                errs_w = 0;
                for (i = 0; i < 64; i = i + 1) begin
                    ext_raddr = i[5:0]; #1;
                    gv = ext_rdata[1*W-1:0*W];
                    if (gv !== in_poly[trial*256 + i*4 + 0]) errs_w = errs_w + 1;
                    gv = ext_rdata[2*W-1:1*W];
                    if (gv !== in_poly[trial*256 + i*4 + 1]) errs_w = errs_w + 1;
                    gv = ext_rdata[3*W-1:2*W];
                    if (gv !== in_poly[trial*256 + i*4 + 2]) errs_w = errs_w + 1;
                    gv = ext_rdata[4*W-1:3*W];
                    if (gv !== in_poly[trial*256 + i*4 + 3]) errs_w = errs_w + 1;
                end
                $display("trial=%0d sanity (    ): errs_w=%0d", trial, errs_w);
            end

            //        NTT
            @(posedge clk); #1;
            start = 1;
            @(posedge clk); #1;
            start = 0;

            //       done
            wait (done);
            @(posedge clk); #1;

            //        +
            errs = 0;
            for (i = 0; i < 64; i = i + 1) begin
                ext_raddr = i[5:0]; #1;
                // 4   cells
                got_v = ext_rdata[1*W-1:0*W];
                if (got_v !== exp_ntt[trial*256 + i*4 + 0]) begin
                    if (errs < 5) $display("trial=%0d FAIL i=%0d cell=0 got=%h exp=%h",
                                            trial, i*4+0, got_v, exp_ntt[trial*256+i*4+0]);
                    errs = errs + 1;
                end
                got_v = ext_rdata[2*W-1:1*W];
                if (got_v !== exp_ntt[trial*256 + i*4 + 1]) begin
                    if (errs < 5) $display("trial=%0d FAIL i=%0d cell=1 got=%h exp=%h",
                                            trial, i*4+1, got_v, exp_ntt[trial*256+i*4+1]);
                    errs = errs + 1;
                end
                got_v = ext_rdata[3*W-1:2*W];
                if (got_v !== exp_ntt[trial*256 + i*4 + 2]) begin
                    if (errs < 5) $display("trial=%0d FAIL i=%0d cell=2 got=%h exp=%h",
                                            trial, i*4+2, got_v, exp_ntt[trial*256+i*4+2]);
                    errs = errs + 1;
                end
                got_v = ext_rdata[4*W-1:3*W];
                if (got_v !== exp_ntt[trial*256 + i*4 + 3]) begin
                    if (errs < 5) $display("trial=%0d FAIL i=%0d cell=3 got=%h exp=%h",
                                            trial, i*4+3, got_v, exp_ntt[trial*256+i*4+3]);
                    errs = errs + 1;
                end
            end
            $display("trial=%0d  errs=%0d", trial, errs);
            total_errs = total_errs + errs;
        end

        $display("tb_ntt_engine: NPOLY=%0d  total_errs=%0d  %s",
                 NPOLY, total_errs, (total_errs==0)?"PASS":"FAIL");
        $finish;
    end

    // Timeout
    initial begin
        #20000000;
        $display("TIMEOUT");
        $finish;
    end
endmodule