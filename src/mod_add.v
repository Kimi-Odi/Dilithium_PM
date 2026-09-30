// ============================================================================
//  mod_add.v  --        r = (x + y) mod q
//
//       Pu et al. TCAS-I 2025, Fig.5 ModAdd
//    sum = x + y                   W+1 bit x,y   [0,q-1]   sum   [0,2q-2]
//      sum >= q   r = sum - q       > q          q
//                r = sum
//             ->       = 1 cycle
//
//              in_valid      out_valid
//      /            [0, q-1]
// ============================================================================
`include "dilithium_params.vh"

module mod_add #(
    parameter W = `DILI_CW                 //      23
)(
    input  wire          clk,
    input  wire          rst_n,            //
    input  wire          in_valid,
    input  wire [W-1:0]  x,
    input  wire [W-1:0]  y,
    output reg           out_valid,
    output reg  [W-1:0]  r
);
    localparam [W:0] Q = `DILI_Q;          //    W+1 bit     q

    wire [W:0]   sum  = {1'b0, x} + {1'b0, y};   // 24-bit
    wire [W:0]   subq = sum - Q;                 // sum - q
    wire         ge_q = (sum >= Q);              //
    wire [W-1:0] res  = ge_q ? subq[W-1:0] : sum[W-1:0];

    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            r         <= {W{1'b0}};
        end else begin
            out_valid <= in_valid;             //
            r         <= res;                  //
        end
    end
endmodule
