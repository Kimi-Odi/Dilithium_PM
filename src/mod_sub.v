// ============================================================================
//  mod_sub.v  --        r = (x - y) mod q
//
//       Pu et al. TCAS-I 2025, Fig.5 ModSub
//    diff = x - y                  W+1 bit     MSB =
//      diff < 0 MSB=1  r = diff + q          q
//                       r = diff
//             ->       = 1 cycle
//
//              in_valid      out_valid
//      /            [0, q-1]
// ============================================================================
`include "dilithium_params.vh"

module mod_sub #(
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

    wire [W:0]   diff = {1'b0, x} - {1'b0, y};   // 24-bit bit[W] =
    wire [W:0]   addq = diff + Q;                // diff + q
    wire         neg  = diff[W];                 // x < y
    wire [W-1:0] res  = neg ? addq[W-1:0] : diff[W-1:0];

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
