// tb_fau_top.v - fau_top
//      4 stage   64 group   {NTT, INTT} = 512 case
//           out_valid       dout
`timescale 1ns/1ps
`include "dilithium_params.vh"

module tb_fau_top;
    localparam W = `DILI_CW;

    reg          clk, rst_n, in_valid;
    reg  [1:0]   mode, stage;
    reg  [5:0]   group;
    reg  [W-1:0] c1_0,c1_1,c1_2,c1_3;
    reg  [W-1:0] c2_0,c2_1,c2_2,c2_3;
    reg  [W-1:0] c3_0,c3_1,c3_2,c3_3;
    wire         out_valid;
    wire [W-1:0] out0,out1,out2,out3;

    fau_top u_dut (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .mode(mode), .stage(stage), .group(group),
        .coe1_0(c1_0), .coe1_1(c1_1), .coe1_2(c1_2), .coe1_3(c1_3),
        .coe2_0(c2_0), .coe2_1(c2_1), .coe2_2(c2_2), .coe2_3(c2_3),
        .coe3_0(c3_0), .coe3_1(c3_1), .coe3_2(c3_2), .coe3_3(c3_3),
        .out_valid(out_valid),
        .out0(out0), .out1(out1), .out2(out2), .out3(out3)
    );

    // clock
    initial clk = 0;
    always #5 clk = ~clk;

    //
    reg [191:0] vec_n [0:255];
    reg [191:0] vec_i [0:255];

    integer s, g, idx, errs;
    reg [W-1:0] ex0,ex1,ex2,ex3;

    task drive_and_check(input integer mm, input integer ss, input integer gg);
        reg [191:0] v;
        begin
            v = (mm==0) ? vec_n[ss*64+gg] : vec_i[ss*64+gg];
            //     X = coe3 (NTT/INTT)
            c3_0 = v[191:168]; c3_1 = v[167:144];
            c3_2 = v[143:120]; c3_3 = v[119:96];
            //
            ex0 = v[95:72]; ex1 = v[71:48];
            ex2 = v[47:24]; ex3 = v[23:0];
            // coe1/coe2 NTT/INTT
            c1_0=0; c1_1=0; c1_2=0; c1_3=0;
            c2_0=0; c2_1=0; c2_2=0; c2_3=0;
            mode  = mm[1:0];
            stage = ss[1:0];
            group = gg[5:0];

            @(posedge clk) in_valid = 1'b1;
            @(posedge clk) in_valid = 1'b0;
            //   out_valid
            @(posedge out_valid);
            @(posedge clk);          //
            if (out0 !== ex0 || out1 !== ex1 || out2 !== ex2 || out3 !== ex3) begin
                $display("FAIL mode=%0d s=%0d g=%0d  got=%h %h %h %h  exp=%h %h %h %h",
                         mm, ss, gg, out0, out1, out2, out3, ex0, ex1, ex2, ex3);
                errs = errs + 1;
            end
            //   1    out_valid
            @(posedge clk);
        end
    endtask

    initial begin
        $readmemh("fautop_ntt.hex",  vec_n);
        $readmemh("fautop_intt.hex", vec_i);
        rst_n = 1'b0; in_valid = 1'b0;
        mode = 0; stage = 0; group = 0;
        c1_0=0;c1_1=0;c1_2=0;c1_3=0;
        c2_0=0;c2_1=0;c2_2=0;c2_3=0;
        c3_0=0;c3_1=0;c3_2=0;c3_3=0;
        errs = 0;
        #25 rst_n = 1'b1;
        @(posedge clk);

        // NTT   256
        for (s=0; s<4; s=s+1)
            for (g=0; g<64; g=g+1)
                drive_and_check(0, s, g);

        // INTT   256
        for (s=0; s<4; s=s+1)
            for (g=0; g<64; g=g+1)
                drive_and_check(1, s, g);

        if (errs == 0)
            $display("tb_fau_top: NTT 256 + INTT 256    PASS");
        else
            $display("tb_fau_top: %0d    ", errs);
        $finish;
    end

    //
    initial begin
        #5000000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
