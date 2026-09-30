// fau            NTT/INTT   10 PWM   5
// out_valid
`timescale 1ns/1ps
`include "dilithium_params.vh"

module tb_fau;
    localparam W=`DILI_CW;
    localparam integer Q=`DILI_Q;
    reg clk=0,rst_n=0,in_valid=0; reg [1:0] mode=0;
    reg [W-1:0] c1_0,c1_1,c1_2,c1_3, c2_0,c2_1,c2_2,c2_3, c3_0,c3_1,c3_2,c3_3;
    wire [W-1:0] o0,o1,o2,o3; wire ov;

    fau #(.W(W)) dut(
        .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.mode(mode),
        .coe1_0(c1_0),.coe1_1(c1_1),.coe1_2(c1_2),.coe1_3(c1_3),
        .coe2_0(c2_0),.coe2_1(c2_1),.coe2_2(c2_2),.coe2_3(c2_3),
        .coe3_0(c3_0),.coe3_1(c3_1),.coe3_2(c3_2),.coe3_3(c3_3),
        .out_valid(ov),.out0(o0),.out1(o1),.out2(o2),.out3(o3));
    always #5 clk=~clk;

    reg [W-1:0] VN [0:512*12-1];
    reg [W-1:0] VI [0:512*12-1];
    reg [W-1:0] VP [0:512*12-1];
    integer n,hit,cyc;
    reg [W-1:0] e0,e1,e2,e3;

    task run1(input [W-1:0] a0,a1,a2,a3,b0,b1,b2,b3,d0,d1,d2,d3,
              input [1:0] m);
        begin
            @(negedge clk);
            c3_0=a0;c3_1=a1;c3_2=a2;c3_3=a3;
            c1_0=b0;c1_1=b1;c1_2=b2;c1_3=b3;
            c2_0=d0;c2_1=d1;c2_2=d2;c2_3=d3;
            mode=m; in_valid=1;
            @(negedge clk); in_valid=0;
            repeat(16) @(negedge clk);
        end
    endtask

    initial begin
        $readmemh("fau_ntt.hex",  VN);
        $readmemh("fau_intt.hex", VI);
        $readmemh("fau_pwm.hex",  VP);
        repeat(3) @(negedge clk); rst_n=1;

        hit=0;
        for (n=0;n<512;n=n+1) begin
            e0=VN[n*12+8]; e1=VN[n*12+9]; e2=VN[n*12+10]; e3=VN[n*12+11];
            fork
              run1(VN[n*12+0],VN[n*12+1],VN[n*12+2],VN[n*12+3],
                   VN[n*12+4],VN[n*12+5],VN[n*12+6],VN[n*12+7],
                   0,0,0,0, 2'd0);
              begin for(cyc=0;cyc<20;cyc=cyc+1) begin @(posedge clk);
                if(ov&&o0===e0&&o1===e1&&o2===e2&&o3===e3) hit=hit+1; end end
            join
        end
        $display("[NTT ] hit = %0d / 512", hit);

        hit=0;
        for (n=0;n<512;n=n+1) begin
            e0=VI[n*12+8]; e1=VI[n*12+9]; e2=VI[n*12+10]; e3=VI[n*12+11];
            fork
              run1(VI[n*12+0],VI[n*12+1],VI[n*12+2],VI[n*12+3],
                   VI[n*12+4],VI[n*12+5],VI[n*12+6],VI[n*12+7],
                   0,0,0,0, 2'd1);
              begin for(cyc=0;cyc<20;cyc=cyc+1) begin @(posedge clk);
                if(ov&&o0===e0&&o1===e1&&o2===e2&&o3===e3) hit=hit+1; end end
            join
        end
        $display("[INTT] hit = %0d / 512", hit);

        hit=0;
        for (n=0;n<512;n=n+1) begin
            e0=VP[n*12+8]; e1=VP[n*12+9]; e2=VP[n*12+10]; e3=VP[n*12+11];
            fork
              run1(0,0,0,0,
                   VP[n*12+0],VP[n*12+1],VP[n*12+2],VP[n*12+3],
                   VP[n*12+4],VP[n*12+5],VP[n*12+6],VP[n*12+7],
                   2'd2);
              begin for(cyc=0;cyc<20;cyc=cyc+1) begin @(posedge clk);
                if(ov&&o0===e0&&o1===e1&&o2===e2&&o3===e3) hit=hit+1; end end
            join
        end
        $display("[PWM ] hit = %0d / 512", hit);
        $finish;
    end
endmodule
