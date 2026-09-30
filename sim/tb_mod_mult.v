// ============================================================================
//  tb_mod_mult.v  --  mod_mult       testbench
//  oracle = (A*B) mod q            4      DUT
//  directed    +        cycle      out_valid
// ============================================================================
`timescale 1ns/1ps
`include "dilithium_params.vh"

module tb_mod_mult;
    localparam W = `DILI_CW;
    localparam integer Q = `DILI_Q;
    localparam integer NRAND = 300000;       //

    reg              clk = 1'b0, rst_n = 1'b0, in_valid = 1'b0;
    reg  [W-1:0]     A = 0, B = 0;
    wire             out_valid;
    wire [W-1:0]     P;

    integer errors = 0, checked = 0, i;
    reg  [31:0]      ra, rb;
    reg  [63:0]      mab;

    //      4      DUT 4-cycle
    reg              ev1, ev2, ev3, ev4;
    reg  [W-1:0]     er1, er2, er3, er4;

    mod_mult dut (.clk(clk), .rst_n(rst_n), .in_valid(in_valid),
                  .A(A), .B(B), .out_valid(out_valid), .P(P));

    always #5 clk = ~clk;

    //    (A*B)%q        DUT      4
    always @(posedge clk) begin
        if (!rst_n) begin
            ev1<=0; ev2<=0; ev3<=0; ev4<=0;
            er1<=0; er2<=0; er3<=0; er4<=0;
        end else begin
            mab = {41'd0, A} * {41'd0, B};       // 64-bit
            er1 <= mab % Q;  ev1 <= in_valid;
            er2 <= er1;      ev2 <= ev1;
            er3 <= er2;      ev3 <= ev2;
            er4 <= er3;      ev4 <= ev3;
        end
    end

    //            DUT
    always @(negedge clk) begin
        if (rst_n) begin
            if (out_valid !== ev4) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("[VALID] t=%0t got=%b exp=%b", $time, out_valid, ev4);
            end
            if (ev4) begin
                checked = checked + 1;
                if (P !== er4) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("[DATA ] t=%0t got=%h exp=%h", $time, P, er4);
                end
            end
        end
    end

    task apply(input [W-1:0] ai, input [W-1:0] bi, input vi);
        begin @(negedge clk); A = ai; B = bi; in_valid = vi; end
    endtask

    initial begin
        repeat (3) @(negedge clk); rst_n = 1'b1;

        // ---- directed    ----
        apply(0, 0, 1);
        apply(1, 1, 1);
        apply(Q-1, Q-1, 1);                 //    *
        apply(Q-1, 1, 1);
        apply(1, Q-1, 1);
        apply((Q-1)/2, 2, 1);
        apply(24'h400000, 24'h400000, 1);   // 2^22 * 2^22
        apply(8192, 8192, 1);               // 2^13 * 2^13
        apply(Q-8192, Q-8192, 1);
        apply(12345, 0, 0);                 // in_valid=0 out_valid
        apply(Q-1, Q-2, 1);

        // ----    in_valid      ----
        for (i = 0; i < NRAND; i = i + 1) begin
            ra = $random; rb = $random;
            apply(ra % Q, rb % Q, (i % 7 != 0));
        end

        @(negedge clk); in_valid = 1'b0;
        repeat (6) @(negedge clk);          //

        $display("----------------------------------------------------------");
        $display(" tb_mod_mult : checked=%0d  errors=%0d  ->  %s",
                 checked, errors, (errors == 0) ? "PASS" : "FAIL");
        $display("----------------------------------------------------------");
        $finish;
    end
endmodule
