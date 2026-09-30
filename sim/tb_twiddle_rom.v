// tb_twiddle_rom.v - twiddle ROM +       bit-exact
`timescale 1ns/1ps
module tb_twiddle_rom;
    reg  [1:0] mode, stage;
    reg  [5:0] group;
    wire [6:0] addr;
    wire [22:0] w0, w1, w2, w3;

    tw_addr_gen u_ag (.mode(mode), .stage(stage), .group(group), .addr(addr));
    twiddle_rom u_rom(.mode(mode), .addr(addr),
                      .w0(w0), .w1(w1), .w2(w2), .w3(w3));

    //          96-bit = w0(24)|w1(24)|w2(24)|w3(24)
    reg [95:0] expect_n [0:255];
    reg [95:0] expect_i [0:255];

    integer s, g, idx, errs;
    reg [22:0] ew0, ew1, ew2, ew3;
    reg [95:0] e;

    initial begin
        $readmemh("tw_expect_ntt.hex",  expect_n);
        $readmemh("tw_expect_intt.hex", expect_i);
        errs = 0;

        // ---- NTT   256 ----
        mode = 2'd0;
        for (s = 0; s < 4; s = s + 1) begin
            stage = s[1:0];
            for (g = 0; g < 64; g = g + 1) begin
                group = g[5:0];
                idx = s * 64 + g;
                #1;
                e = expect_n[idx];
                ew0 = e[95:72]; ew1 = e[71:48]; ew2 = e[47:24]; ew3 = e[23:0];
                if (w0 !== ew0 || w1 !== ew1 || w2 !== ew2 || w3 !== ew3) begin
                    $display("NTT FAIL s=%0d g=%0d addr=%0d got=%h %h %h %h exp=%h %h %h %h",
                             s, g, addr, w0, w1, w2, w3, ew0, ew1, ew2, ew3);
                    errs = errs + 1;
                end
            end
        end

        // ---- INTT   256 ----
        mode = 2'd1;
        for (s = 0; s < 4; s = s + 1) begin
            stage = s[1:0];
            for (g = 0; g < 64; g = g + 1) begin
                group = g[5:0];
                idx = s * 64 + g;
                #1;
                e = expect_i[idx];
                ew0 = e[95:72]; ew1 = e[71:48]; ew2 = e[47:24]; ew3 = e[23:0];
                if (w0 !== ew0 || w1 !== ew1 || w2 !== ew2 || w3 !== ew3) begin
                    $display("INTT FAIL s=%0d g=%0d addr=%0d got=%h %h %h %h exp=%h %h %h %h",
                             s, g, addr, w0, w1, w2, w3, ew0, ew1, ew2, ew3);
                    errs = errs + 1;
                end
            end
        end

        if (errs == 0)
            $display("twiddle_rom + tw_addr_gen TB: NTT 256 + INTT 256    PASS");
        else
            $display("twiddle_rom + tw_addr_gen TB: %0d    ", errs);
        $finish;
    end
endmodule
