// ntt_intt_engine.v - NTT+INTT wrapper
//
// Vivado XSim workaround: wrap polymul_top, expose op_mode (0=NTT, 1=INTT).
// PMM_B input ports tied to 0 (unused for NTT/INTT-only).
`include "dilithium_params.vh"

module ntt_intt_engine #(
    parameter W = `DILI_CW
)(
    input  wire             clk, rst_n,
    input  wire             start,
    input  wire [1:0]       op_mode,        // 0=NTT, 1=INTT
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
        .op_mode     (op_mode),
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