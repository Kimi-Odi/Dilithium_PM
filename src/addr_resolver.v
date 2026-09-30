// addr_resolver.v - Conflict-free banking
//   logical_addr (6-bit) -> (bank_id, internal_addr)
//   bank     = (low + SN) mod 4,  SN = (high[3:2] + high[1:0]) mod 4
//   internal = high (4-bit)
//        batch   4   logical addrs    4   distinct banks
module addr_resolver(
    input  wire [5:0] logical_addr,
    output wire [1:0] bank_id,
    output wire [3:0] internal_addr
);
    wire [1:0] low = logical_addr[1:0];
    wire [1:0] h0  = logical_addr[3:2];
    wire [1:0] h1  = logical_addr[5:4];
    wire [1:0] sn  = h0 + h1;            // mod 4    (2-bit wrap)
    assign bank_id       = low + sn;     // mod 4
    assign internal_addr = logical_addr[5:2];
endmodule
