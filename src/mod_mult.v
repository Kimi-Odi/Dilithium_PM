// ============================================================================
//  mod_mult.v  --        P = (A * B) mod q
//
//     Pham et al. TCAS-I 2023, Fig.3 Barrett    q
//  q = 8380417 = 2^23 - 2^13 + 1    T = floor(2^46/q) = 8396807
//
//        (b)       A*B   Design Compiler    23x23
//           FPGA->ASIC          DSP    23x6+23x17     ASIC
//  MR          shift-add     V1/V2/VT/W/Wq/X     Eq.(4)-(7)
//             q    Python    200    +
//                  = 1     Barrett      [0,2q)   2q < 2^24
//
//  4       b
//    S1: U = A*B
//    S2: W = UH-Mult(V*T>>24)              U   24-bit
//    S3: X = LH-Mult(W*q mod 2^24)
//    S4:    U[23:0]-X     q   ->
//       = 4 cycle in_valid   4    out_valid
//         rst_n   mod_add/mod_sub
// ============================================================================
`include "dilithium_params.vh"

module mod_mult #(
    parameter W = `DILI_CW                  //      23
)(
    input  wire          clk,
    input  wire          rst_n,             //
    input  wire          in_valid,
    input  wire [W-1:0]  A,
    input  wire [W-1:0]  B,
    output reg           out_valid,
    output reg  [W-1:0]  P
);
    localparam [W:0] Q = `DILI_Q;           //    24-bit    q

    // ===================== S1     U = A*B ===============================
    //        46-bit                23-bit context
    wire [45:0] A46 = {{(46-W){1'b0}}, A};
    wire [45:0] B46 = {{(46-W){1'b0}}, B};
    wire [45:0] U_comb = A46 * B46;          // A*B < 2^46   DC

    reg  [45:0] U_r;
    reg         v1;
    always @(posedge clk) begin
        if (!rst_n) begin U_r <= 46'd0; v1 <= 1'b0; end
        else        begin U_r <= U_comb;  v1 <= in_valid; end
    end

    // ===================== S2 UH-Mult  W = (V*T) >> 24 =====================
    // V = U[45:22] 24-bit  VT = 2^13 V1 + 2^1 V2 + V[0] = V*T  (Eq.4)
    wire [23:0] V  = U_r[45:22];
    wire [34:0] V1 = ({{11{1'b0}}, V} << 10) + {{11{1'b0}}, V};      // 2^10 V + V
    wire [25:0] V2 = ({{2{1'b0}},  V} << 1)                          // 2 V
                   + {{2{1'b0}},  V}                                 // + V
                   + {{2{1'b0}},  V[23:1]};                          // + (V>>1)
    wire [47:0] VT = ({13'd0, V1} << 13)                             // 2^13 V1
                   + ({22'd0, V2} << 1)                              // 2^1 V2
                   + {47'd0, V[0]};                                  // + V[0]
    wire [23:0] W_comb = VT[47:24];          // (V*T) >> 24  (Eq.5)

    reg  [23:0] W_r;
    reg  [23:0] Ulo_r;                       // U[23:0]     S2
    reg         v2;
    always @(posedge clk) begin
        if (!rst_n) begin
            W_r <= 24'd0; Ulo_r <= 24'd0; v2 <= 1'b0;
        end else begin
            W_r <= W_comb; Ulo_r <= U_r[23:0]; v2 <= v1;
        end
    end

    // ===================== S3 LH-Mult  X = (W*q) mod 2^24 ==================
    // Wq = 2^23 W - 2^13 W + W = W*q  (Eq.6)    24-bit = X  (Eq.7)
    wire [46:0] Wq = ({23'd0, W_r} << 23)
                   - ({23'd0, W_r} << 13)
                   + {23'd0, W_r};
    wire [23:0] X_comb = Wq[23:0];

    reg  [23:0] X_r;
    reg  [23:0] Ulo_r2;                      // U[23:0]      S3
    reg         v3;
    always @(posedge clk) begin
        if (!rst_n) begin
            X_r <= 24'd0; Ulo_r2 <= 24'd0; v3 <= 1'b0;
        end else begin
            X_r <= X_comb; Ulo_r2 <= Ulo_r; v3 <= v2;
        end
    end

    // ===================== S4    Y = U[23:0]-X       q =============
    wire [23:0] raw  = Ulo_r2 - X_r;                 // 24-bit
    wire [24:0] subq = {1'b0, raw} - {1'b0, Q};      // raw - q bit24=
    wire        lt_q = subq[24];                     //   =1 -> raw < q
    wire [23:0] res  = lt_q ? raw : subq[23:0];      //

    always @(posedge clk) begin
        if (!rst_n) begin
            P <= {W{1'b0}}; out_valid <= 1'b0;
        end else begin
            P <= res[W-1:0];                         //      [0,q) < 2^23
            out_valid <= v3;
        end
    end
endmodule
