// poly_mem_4bank.v
//   4 banks   16 words   4 cells   23-bit, conflict-free banking
//     bank: 1      port + 1      port (cell-wise WE, 4-bit)
//        4 banks          FSM     bank   (read addr, write addr, cell-WE, write data)
`include "dilithium_params.vh"

module poly_mem_4bank #(
    parameter W = `DILI_CW
)(
    input  wire             clk, rst_n,

    // ---- Read (  ) ----
    input  wire [3:0]       r_addr0, r_addr1, r_addr2, r_addr3,
    output wire [4*W-1:0]   r_data0, r_data1, r_data2, r_data3,

    // ---- Write (  , per-cell WE) ----
    input  wire [3:0]       w_addr0, w_addr1, w_addr2, w_addr3,
    input  wire [3:0]       w_we0,   w_we1,   w_we2,   w_we3,   // 4-bit cell WE per bank
    input  wire [4*W-1:0]   w_data0, w_data1, w_data2, w_data3
);
    reg [4*W-1:0] bank0 [0:15];
    reg [4*W-1:0] bank1 [0:15];
    reg [4*W-1:0] bank2 [0:15];
    reg [4*W-1:0] bank3 [0:15];

    integer init_i;
    // synthesis translate_off
    initial begin
        for (init_i = 0; init_i < 16; init_i = init_i + 1) begin
            bank0[init_i] = {(4*W){1'b0}};
            bank1[init_i] = {(4*W){1'b0}};
            bank2[init_i] = {(4*W){1'b0}};
            bank3[init_i] = {(4*W){1'b0}};
        end
    end
    // synthesis translate_on

    assign r_data0 = bank0[r_addr0];
    assign r_data1 = bank1[r_addr1];
    assign r_data2 = bank2[r_addr2];
    assign r_data3 = bank3[r_addr3];

    //     generate 4 banks
    always @(posedge clk) begin
        if (rst_n) begin
            // bank 0
            if (w_we0[0]) bank0[w_addr0][1*W-1:0*W] <= w_data0[1*W-1:0*W];
            if (w_we0[1]) bank0[w_addr0][2*W-1:1*W] <= w_data0[2*W-1:1*W];
            if (w_we0[2]) bank0[w_addr0][3*W-1:2*W] <= w_data0[3*W-1:2*W];
            if (w_we0[3]) bank0[w_addr0][4*W-1:3*W] <= w_data0[4*W-1:3*W];
            // bank 1
            if (w_we1[0]) bank1[w_addr1][1*W-1:0*W] <= w_data1[1*W-1:0*W];
            if (w_we1[1]) bank1[w_addr1][2*W-1:1*W] <= w_data1[2*W-1:1*W];
            if (w_we1[2]) bank1[w_addr1][3*W-1:2*W] <= w_data1[3*W-1:2*W];
            if (w_we1[3]) bank1[w_addr1][4*W-1:3*W] <= w_data1[4*W-1:3*W];
            // bank 2
            if (w_we2[0]) bank2[w_addr2][1*W-1:0*W] <= w_data2[1*W-1:0*W];
            if (w_we2[1]) bank2[w_addr2][2*W-1:1*W] <= w_data2[2*W-1:1*W];
            if (w_we2[2]) bank2[w_addr2][3*W-1:2*W] <= w_data2[3*W-1:2*W];
            if (w_we2[3]) bank2[w_addr2][4*W-1:3*W] <= w_data2[4*W-1:3*W];
            // bank 3
            if (w_we3[0]) bank3[w_addr3][1*W-1:0*W] <= w_data3[1*W-1:0*W];
            if (w_we3[1]) bank3[w_addr3][2*W-1:1*W] <= w_data3[2*W-1:1*W];
            if (w_we3[2]) bank3[w_addr3][3*W-1:2*W] <= w_data3[3*W-1:2*W];
            if (w_we3[3]) bank3[w_addr3][4*W-1:3*W] <= w_data3[4*W-1:3*W];
        end
    end
endmodule