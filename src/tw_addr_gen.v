// tw_addr_gen.v - twiddle ROM
// addr = base[stage] + (group >> (6 - 2*stage))
//   stage=0: base=0,  shift=6, group 1   (addr 0)
//   stage=1: base=1,  shift=4, group 4   (addr 1..4)
//   stage=2: base=5,  shift=2, group 16  (addr 5..20)
//   stage=3: base=21, shift=0, group 64  (addr 21..84)
module tw_addr_gen(
    input  [1:0] mode,    // 0=NTT,1=INTT,2=PWM (PWM    ROM)
    input  [1:0] stage,
    input  [5:0] group,
    output reg [6:0] addr
);
    reg [6:0] base;
    reg [2:0] sh;
    always @(*) begin
        case (stage)
            2'd0: begin base = 7'd0;  sh = 3'd6; end
            2'd1: begin base = 7'd1;  sh = 3'd4; end
            2'd2: begin base = 7'd5;  sh = 3'd2; end
            2'd3: begin base = 7'd21; sh = 3'd0; end
            default: begin base = 7'd0; sh = 3'd0; end
        endcase
        addr = base + ({1'b0, group} >> sh);
    end
endmodule
