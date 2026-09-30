// ============================================================================
//  tb_mod_div4.v  --  mod_div4       testbench
//        r     <=>  (r*4) mod q == x     r < q
//   4   q    x 4^{-1} mod q        TB
// ============================================================================
`timescale 1ns/1ps
`include "dilithium_params.vh"

module tb_mod_div4;
    localparam W = `DILI_CW;
    localparam integer Q = `DILI_Q;
    localparam integer NRAND = 300000;

    reg              clk = 1'b0, rst_n = 1'b0, in_valid = 1'b0;
    reg  [W-1:0]     x = 0;
    wire             out_valid;
    wire [W-1:0]     r;

    integer errors = 0, checked = 0, i;
    reg  [31:0]      rx;

    //      1      DUT
    reg              xv;
    reg  [W-1:0]     xd;

    mod_div4 dut (.clk(clk), .rst_n(rst_n), .in_valid(in_valid),
                  .x(x), .out_valid(out_valid), .r(r));

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin xv <= 1'b0; xd <= {W{1'b0}}; end
        else        begin xv <= in_valid; xd <= x; end
    end

    //      DUT
    always @(negedge clk) begin
        if (rst_n) begin
            if (out_valid !== xv) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("[VALID] t=%0t got=%b exp=%b", $time, out_valid, xv);
            end
            if (xv) begin
                checked = checked + 1;
                //    r<q   (r*4) mod q ==     x
                if ((r >= Q) || (((r * 4) % Q) !== xd)) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("[DATA ] t=%0t x=%h r=%h  (r*4)%%q=%h",
                                 $time, xd, r, (r*4)%Q);
                end
            end
        end
    end

    task apply(input [W-1:0] xi, input vi);
        begin @(negedge clk); x = xi; in_valid = vi; end
    endtask

    initial begin
        repeat (3) @(negedge clk); rst_n = 1'b1;

        // ---- directed       x%4 = 0/1/2/3       ----
        apply(0, 1);
        apply(1, 1);
        apply(2, 1);
        apply(3, 1);
        apply(4, 1);
        apply(Q-1, 1);
        apply(Q-2, 1);
        apply(Q-3, 1);
        apply(Q-4, 1);
        apply((Q-1)/2, 1);
        apply(8380416, 1);              // q-1
        apply(8380415, 1);              // q-2
        apply(123456, 0);               // in_valid=0 out_valid
        apply(7, 1);

        // ----    in_valid      ----
        for (i = 0; i < NRAND; i = i + 1) begin
            rx = $random;
            apply(rx % Q, (i % 7 != 0));
        end

        @(negedge clk); in_valid = 1'b0;
        repeat (4) @(negedge clk);

        $display("----------------------------------------------------------");
        $display(" tb_mod_div4 : checked=%0d  errors=%0d  ->  %s",
                 checked, errors, (errors == 0) ? "PASS" : "FAIL");
        $display("----------------------------------------------------------");
        $finish;
    end
endmodule
