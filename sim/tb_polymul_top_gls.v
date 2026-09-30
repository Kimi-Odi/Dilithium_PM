// tb_polymul_top_gls.v - Gate-level simulation TB
// 對 DC 合成後的 polymul_top_syn.v 做 timing back-annotated 模擬,
// 確認 gate-level 行為與 RTL 一致.

`timescale 1ns/10ps

module tb_polymul_top_gls;
    localparam W = 23;
    localparam NPOLY = 4;          // GLS 比 RTL sim 慢, 跑少一點

    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg [1:0] op_mode = 0;
    reg ext_we = 0;
    reg [5:0] ext_waddr = 0;
    reg [4*W-1:0] ext_wdata = 0;
    reg [5:0] ext_raddr = 0;
    wire [4*W-1:0] ext_rdata;
    wire done;

    reg ext_we_b = 0;
    reg [5:0] ext_waddr_b = 0;
    reg [4*W-1:0] ext_wdata_b = 0;

    // DUT = 合成後 netlist 的 polymul_top
    polymul_top u_dut (
        .clk(clk), .rst_n(rst_n), .start(start), .op_mode(op_mode), .done(done),
        .ext_we(ext_we), .ext_waddr(ext_waddr), .ext_wdata(ext_wdata),
        .ext_raddr(ext_raddr), .ext_rdata(ext_rdata),
        .ext_we_b(ext_we_b), .ext_waddr_b(ext_waddr_b), .ext_wdata_b(ext_wdata_b)
    );

    // SDF back-annotation
    initial begin
        $sdf_annotate("polymul_top_syn.sdf", u_dut);
        $display("===== SDF annotated to u_dut =====");
    end

    // VCD dump (optional)
    initial begin
        $dumpfile("polymul_top_gls.vcd");
        $dumpvars(2, tb_polymul_top_gls);
    end

    // Clock period 8 ns matches DC 合成 SDC
    always #4 clk = ~clk;   // 4 + 4 = 8 ns period (125 MHz)

    reg [W-1:0] a_poly   [0:NPOLY*256-1];
    reg [W-1:0] b_hat    [0:NPOLY*256-1];
    reg [W-1:0] c_expect [0:NPOLY*256-1];

    integer trial, i, errs, total_errs;
    reg [W-1:0] gv;

    initial begin
        $readmemh("pmt_a.hex",    a_poly);
        $readmemh("pmt_bhat.hex", b_hat);
        $readmemh("pmt_c.hex",    c_expect);
        total_errs = 0;

        #20 rst_n = 1;
        @(posedge clk);

        for (trial = 0; trial < NPOLY; trial = trial + 1) begin
            // 寫 a 到 PMM_A
            ext_we = 1;
            for (i = 0; i < 64; i = i + 1) begin
                @(posedge clk); #1;
                ext_waddr = i[5:0];
                ext_wdata = { a_poly[trial*256 + i*4 + 3],
                              a_poly[trial*256 + i*4 + 2],
                              a_poly[trial*256 + i*4 + 1],
                              a_poly[trial*256 + i*4 + 0] };
            end
            @(posedge clk); #1;
            ext_we = 0;

            // 寫 b_hat 到 PMM_B
            ext_we_b = 1;
            for (i = 0; i < 64; i = i + 1) begin
                @(posedge clk); #1;
                ext_waddr_b = i[5:0];
                ext_wdata_b = { b_hat[trial*256 + i*4 + 3],
                                b_hat[trial*256 + i*4 + 2],
                                b_hat[trial*256 + i*4 + 1],
                                b_hat[trial*256 + i*4 + 0] };
            end
            @(posedge clk); #1;
            ext_we_b = 0;

            // NTT
            @(posedge clk); #1; op_mode = 2'd0; start = 1;
            @(posedge clk); #1; start = 0;
            wait(done);
            @(posedge clk); #1;

            // PWM
            @(posedge clk); #1; op_mode = 2'd2; start = 1;
            @(posedge clk); #1; start = 0;
            wait(done);
            @(posedge clk); #1;

            // INTT
            @(posedge clk); #1; op_mode = 2'd1; start = 1;
            @(posedge clk); #1; start = 0;
            wait(done);
            @(posedge clk); #1;

            // 讀回比對
            errs = 0;
            for (i = 0; i < 64; i = i + 1) begin
                ext_raddr = i[5:0]; #1;
                gv = ext_rdata[1*W-1:0*W];
                if (gv !== c_expect[trial*256 + i*4 + 0]) errs = errs + 1;
                gv = ext_rdata[2*W-1:1*W];
                if (gv !== c_expect[trial*256 + i*4 + 1]) errs = errs + 1;
                gv = ext_rdata[3*W-1:2*W];
                if (gv !== c_expect[trial*256 + i*4 + 2]) errs = errs + 1;
                gv = ext_rdata[4*W-1:3*W];
                if (gv !== c_expect[trial*256 + i*4 + 3]) errs = errs + 1;
            end
            $display("GLS trial=%0d polymul errs=%0d", trial, errs);
            total_errs = total_errs + errs;
        end

        $display("tb_polymul_top_gls: NPOLY=%0d  total_errs=%0d  %s",
                 NPOLY, total_errs, (total_errs==0)?"PASS":"FAIL");
        $finish;
    end

    initial begin
        #500000000;   // 500 ms timeout
        $display("GLS TIMEOUT");
        $finish;
    end
endmodule