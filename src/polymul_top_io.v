// polymul_top_io.v - IO-minimized wrapper for polymul_top
//
// Cell-wise serial interface: 寫/讀以 23-bit cell 為單位, 一個 92-bit PMM word
// 用 4 個 cycle 寫入(cell 0..3). 內部把 cell-wise 寫拼成 word 一次寫進 polymul_top.
//
// I/O count = 70 ports (fit FPGA 7k70t 200-pin limit).
`include "dilithium_params.vh"

module polymul_top_io #(
    parameter W = `DILI_CW
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,
    input  wire [1:0]       op_mode,         // 0=NTT, 1=INTT, 2=PWM
    output wire             done,

    // 寫端口 (cell-wise, 23-bit data per cycle)
    input  wire             ext_we,
    input  wire             ext_target,      // 0=PMM_A, 1=PMM_B
    input  wire [5:0]       ext_waddr,       // logical word addr 0..63
    input  wire [1:0]       ext_wcell,       // cell idx 0..3 within word
    input  wire [W-1:0]     ext_wdata,       // 23-bit cell value

    // 讀端口 (cell-wise, 23-bit per cycle)
    input  wire [5:0]       ext_raddr,
    input  wire [1:0]       ext_rcell,
    output wire [W-1:0]     ext_rdata
);

    // --- Cell-wise write buffer: 收 cell 0..2 到 reg, cell 3 cycle 一次寫進 polymul_top ---
    reg [W-1:0] wbuf_c0, wbuf_c1, wbuf_c2;
    always @(posedge clk) begin
        if (!rst_n) begin
            wbuf_c0 <= 0; wbuf_c1 <= 0; wbuf_c2 <= 0;
        end else if (ext_we) begin
            case (ext_wcell)
                2'd0: wbuf_c0 <= ext_wdata;
                2'd1: wbuf_c1 <= ext_wdata;
                2'd2: wbuf_c2 <= ext_wdata;
                default: ; // cell 3: 不存 buffer (直接 combine)
            endcase
        end
    end

    // 當 cell==3 cycle 把 buffered c0/c1/c2 加上即時 c3 (=ext_wdata) 拼成 92-bit word,
    // 並觸發 polymul_top 的 ext_we
    wire [4*W-1:0] full_wdata = { ext_wdata, wbuf_c2, wbuf_c1, wbuf_c0 };
    wire           inner_we   = ext_we & (ext_wcell == 2'd3);

    wire [4*W-1:0] inner_rdata;
    polymul_top #( .W(W) ) u_inner (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .op_mode     (op_mode),
        .done        (done),
        .ext_we      (inner_we & ~ext_target),
        .ext_waddr   (ext_waddr),
        .ext_wdata   (full_wdata),
        .ext_raddr   (ext_raddr),
        .ext_rdata   (inner_rdata),
        .ext_we_b    (inner_we &  ext_target),
        .ext_waddr_b (ext_waddr),
        .ext_wdata_b (full_wdata)
    );

    // --- Read mux: 從 92-bit inner_rdata 取對應 cell ---
    assign ext_rdata = (ext_rcell == 2'd0) ? inner_rdata[1*W-1:0*W] :
                       (ext_rcell == 2'd1) ? inner_rdata[2*W-1:1*W] :
                       (ext_rcell == 2'd2) ? inner_rdata[3*W-1:2*W] :
                                             inner_rdata[4*W-1:3*W];

endmodule