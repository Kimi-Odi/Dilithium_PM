// ============================================================================
//  mod_div4.v  --       4 r = (x * 4^{-1}) mod q
//
//     Pu et al. TCAS-I 2025, Fig.5 ModDiv4     2
//  q          x 2^{-1} mod q = x   ? (x>>1) : (x>>1)+(q+1)/2
//   4 =        2
//
//     INTT radix-4      twiddle      trivial
//             4^{-1}    B            twiddle ROM
//
//              in_valid      out_valid
//      /          = 1 cycle        [0, q-1]
// ============================================================================
`include "dilithium_params.vh"

module mod_div4 #(
    parameter W = `DILI_CW                 //      23
)(
    input  wire          clk,
    input  wire          rst_n,            //
    input  wire          in_valid,
    input  wire [W-1:0]  x,
    output reg           out_valid,
    output reg  [W-1:0]  r
);
    localparam [W:0]   Q    = `DILI_Q;             //
    localparam [W-1:0] HALF = (`DILI_Q + 1) >> 1;  // (q+1)/2 = 4190209

    // ----      2 ----
    wire [W-1:0] d1   = x >> 1;                         // x>>1   0
    wire [W:0]   s1   = {1'b0, d1} + {1'b0, HALF};      // (x>>1)+(q+1)/2
    wire [W-1:0] half1 = x[0] ? s1[W-1:0] : d1;         //   x   LSB

    // ----      2 ----
    wire [W-1:0] d2   = half1 >> 1;
    wire [W:0]   s2   = {1'b0, d2} + {1'b0, HALF};
    wire [W-1:0] quat = half1[0] ? s2[W-1:0] : d2;      //   half1   LSB

    // ----       1 cycle ----
    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            r         <= {W{1'b0}};
        end else begin
            out_valid <= in_valid;             //
            r         <= quat;                 // x/4 mod q
        end
    end
endmodule
