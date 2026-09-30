// ntt_engine.v - NTT-only wrapper
//
// Vivado XSim workaround: wrap polymul_top with op_mode tied to NTT (2'd0).
// Internal logic is identical to polymul_top (which Vivado XSim runs correctly).
// PMM_B input ports tied to 0 (unused for NTT-only).
`include "dilithium_params.vh"

module ntt_engine #(
    parameter W = `DILI_CW
)(
    input  wire             clk, rst_n,
    input  wire             start,
    output wire             done,
    input  wire             ext_we,
    input  wire [5:0]       ext_waddr,
    input  wire [4*W-1:0]   ext_wdata,
    input  wire [5:0]       ext_raddr,
    output wire [4*W-1:0]   ext_rdata
);

    polymul_top #( .W(W) ) u_inner (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .op_mode     (2'd0),
        .done        (done),
        .ext_we      (ext_we),
        .ext_waddr   (ext_waddr),
        .ext_wdata   (ext_wdata),
        .ext_raddr   (ext_raddr),
        .ext_rdata   (ext_rdata),
        .ext_we_b    (1'b0),
        .ext_waddr_b (6'd0),
        .ext_wdata_b ({(4*W){1'b0}})
    );

endmodule