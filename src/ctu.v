// ctu.v - 4x4 Corner Turn Unit (4-row parallel write + cell-random read)
//
// Pu (ML-DSA FAU) single-address-four-coefficient
// row_we = 1 in one cycle, write all 4 rows in parallel
// (PMM 4-bank parallel read -> CTU rows, then random cell access).
//
// mat_flat layout: cell at (row r, col c) -> mat_flat[(r*4+c)*W +: W]
`include "dilithium_params.vh"

module ctu #(
    parameter W = `DILI_CW
)(
    input  wire             clk,
    input  wire             rst_n,

    // Row-parallel write: writes 4 rows in same cycle when row_we high
    input  wire             row_we,
    input  wire [4*W-1:0]   row_d0,   // row 0 (4 cells packed {c3,c2,c1,c0})
    input  wire [4*W-1:0]   row_d1,
    input  wire [4*W-1:0]   row_d2,
    input  wire [4*W-1:0]   row_d3,

    // Combinational cell-random output: 4x4 matrix flattened
    //   cell(r,c) = mat_flat[(r*4 + c)*W +: W]
    output wire [4*4*W-1:0] mat_flat
);
    reg [4*W-1:0] r0, r1, r2, r3;

    integer i_init;
    // synthesis translate_off
    initial begin
        r0 = {(4*W){1'b0}}; r1 = {(4*W){1'b0}};
        r2 = {(4*W){1'b0}}; r3 = {(4*W){1'b0}};
    end
    // synthesis translate_on

    always @(posedge clk) begin
        if (!rst_n) begin
            r0 <= 0; r1 <= 0; r2 <= 0; r3 <= 0;
        end else if (row_we) begin
            r0 <= row_d0;
            r1 <= row_d1;
            r2 <= row_d2;
            r3 <= row_d3;
        end
    end

    // Flatten 4 rows into one bus. row r at bits [(r+1)*4*W-1 : r*4*W].
    assign mat_flat = {r3, r2, r1, r0};
endmodule