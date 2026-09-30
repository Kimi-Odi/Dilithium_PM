// ============================================================================
//  tb_mod_sub.v  --  mod_sub       testbench
//       (x - y + q) mod q        cycle
// ============================================================================
`timescale 1ns/1ps
`include "dilithium_params.vh"

module tb_mod_sub;
    localparam W = `DILI_CW;
    localparam integer Q = `DILI_Q;
    localparam integer NRAND = 200000;     //

    reg              clk = 1'b0, rst_n = 1'b0, in_valid = 1'b0;
    reg  [W-1:0]     x = 0, y = 0;
    wire             out_valid;
    wire [W-1:0]     r;

    integer errors = 0, checked = 0, i;
    reg  [31:0]      rx, ry;

    //         1    DUT
    reg              ev;
    reg  [W-1:0]     er;

    mod_sub dut (.clk(clk), .rst_n(rst_n), .in_valid(in_valid),
                 .x(x), .y(y), .out_valid(out_valid), .r(r));

    always #5 clk = ~clk;                   //

    //        DUT
    always @(posedge clk) begin
        if (!rst_n) begin ev <= 1'b0; er <= {W{1'b0}}; end
        else        begin ev <= in_valid; er <= (x + Q - y) % Q; end
    end

    //              DUT
    always @(negedge clk) begin
        if (rst_n) begin
            if (out_valid !== ev) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("[VALID] t=%0t  got=%b exp=%b", $time, out_valid, ev);
            end
            if (ev) begin
                checked = checked + 1;
                if (r !== er) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("[DATA ] t=%0t  got=%h exp=%h", $time, r, er);
                end
            end
        end
    end

    //                DUT
    task apply(input [W-1:0] xi, input [W-1:0] yi, input vi);
        begin @(negedge clk); x = xi; y = yi; in_valid = vi; end
    endtask

    initial begin
        repeat (3) @(negedge clk); rst_n = 1'b1;

        // ---- directed      ----
        apply(0, 0, 1);
        apply(Q-1, 0, 1);
        apply(0, Q-1, 1);                // -(q-1) mod q = 1
        apply(0, 1, 1);                  // q-1
        apply(5, 5, 1);                  // 0
        apply(Q-1, Q-1, 1);              // 0
        apply(1, Q-1, 1);                // 2
        apply(Q-1, 1, 1);                // q-2
        apply(777, 999, 0);              // in_valid=0 out_valid
        apply(0, Q-1, 1);

        // ----      in_valid      ----
        for (i = 0; i < NRAND; i = i + 1) begin
            rx = $random; ry = $random;
            apply(rx % Q, ry % Q, (i % 7 != 0));
        end

        @(negedge clk); in_valid = 1'b0;
        repeat (4) @(negedge clk);

        $display("----------------------------------------------------------");
        $display(" tb_mod_sub : checked=%0d  errors=%0d  ->  %s",
                 checked, errors, (errors == 0) ? "PASS" : "FAIL");
        $display("----------------------------------------------------------");
        $finish;
    end
endmodule
