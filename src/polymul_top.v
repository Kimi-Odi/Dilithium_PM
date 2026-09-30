// ntt_engine.v - NTT-only      Pu
//
//     : 4-bank PMM + conflict-free banking + CTU 4 4 + fau_top
//       : ext_we/ext_waddr/ext_wdata    PMM (S_IDLE/S_DONE  ),
//             ext_raddr/ext_rdata    PMM (       ).
//     : start   S_RUN,   4 stage   16 batch   15 cycle/batch   done
//
//     batch 15 cycle:
//     sub=0:      PMM 4-bank parallel read   CTU 4 row parallel write
//     sub=1..4:   CTU col-read   fau in_valid (4    pipeline  )
//     sub=11..14: fau out_valid   PMM 4-bank cell-wise write (4      )
`include "dilithium_params.vh"

module polymul_top #(
    parameter W = `DILI_CW
)(
    input  wire             clk, rst_n,
    input  wire             start,
    input  wire [1:0]       op_mode,
    output reg              done,
    // ----    PMM_A access (logical addr) ----
    input  wire             ext_we,           //   PMM_A (NTT input / final result read  )
    input  wire [5:0]       ext_waddr,
    input  wire [4*W-1:0]   ext_wdata,
    input  wire [5:0]       ext_raddr,
    output wire [4*W-1:0]   ext_rdata,
    // ----    PMM_B access (   b_hat   PWM  ) ----
    input  wire             ext_we_b,
    input  wire [5:0]       ext_waddr_b,
    input  wire [4*W-1:0]   ext_wdata_b
);
    // =====================================================================
    // FSM state
    // =====================================================================
    localparam S_IDLE = 2'd0, S_RUN = 2'd1, S_RUN_PWM = 2'd2, S_DONE = 2'd3;
    reg [1:0]  state;
    reg [1:0]  stage_cnt;       // 0..3
    reg [3:0]  batch_cnt;       // 0..15
    reg [4:0]  sub_cnt;         // 0..14
    reg [6:0]  pwm_cnt;         // 0..68 (PWM 64 dispatch + 5 drain)
    wire running = (state == S_RUN);
    wire pwm_running = (state == S_RUN_PWM);

    // PWM    wire: pwm_cnt 0..63 dispatch, 5..68 writeback (addr = pwm_cnt-5)
    wire [5:0] pwm_r_addr = pwm_cnt[5:0];                 // read addr
    wire [5:0] pwm_w_addr = pwm_cnt[5:0] - 6'd5;          // write addr
    wire [1:0] pwm_r_bk,  pwm_w_bk;
    wire [3:0] pwm_r_id,  pwm_w_id;
    addr_resolver u_pwm_rr(.logical_addr(pwm_r_addr), .bank_id(pwm_r_bk), .internal_addr(pwm_r_id));
    addr_resolver u_pwm_wr(.logical_addr(pwm_w_addr), .bank_id(pwm_w_bk), .internal_addr(pwm_w_id));
    wire pwm_disp     = pwm_running && (pwm_cnt < 7'd64);          // dispatch 0..63
    wire pwm_writeb   = pwm_running && (pwm_cnt >= 7'd5) && (pwm_cnt < 7'd69);

    // =====================================================================
    //    batch   4   logical addresses + group base
    // =====================================================================
    reg  [5:0] addr_a, addr_b, addr_c, addr_d;
    wire [5:0] grp_base = {batch_cnt, 2'b00};   // batch*4
    always @(*) begin
        case (stage_cnt)
            2'd0: begin
                addr_a = {2'b00, batch_cnt};
                addr_b = addr_a + 6'd16;
                addr_c = addr_a + 6'd32;
                addr_d = addr_a + 6'd48;
            end
            2'd1: begin
                addr_a = {batch_cnt[3:2], 2'b00, batch_cnt[1:0]};
                addr_b = addr_a + 6'd4;
                addr_c = addr_a + 6'd8;
                addr_d = addr_a + 6'd12;
            end
            default: begin                  // stage 2/3
                addr_a = {batch_cnt, 2'b00};
                addr_b = addr_a + 6'd1;
                addr_c = addr_a + 6'd2;
                addr_d = addr_a + 6'd3;
            end
        endcase
    end

    // =====================================================================
    // Address resolver   6 (4 batch + 2 ext)
    // =====================================================================
    wire [1:0] bk_a, bk_b, bk_c, bk_d, ext_w_bk, ext_r_bk;
    wire [3:0] id_a, id_b, id_c, id_d, ext_w_id, ext_r_id;
    addr_resolver u_ra(.logical_addr(addr_a),   .bank_id(bk_a),   .internal_addr(id_a));
    addr_resolver u_rb(.logical_addr(addr_b),   .bank_id(bk_b),   .internal_addr(id_b));
    addr_resolver u_rc(.logical_addr(addr_c),   .bank_id(bk_c),   .internal_addr(id_c));
    addr_resolver u_rd(.logical_addr(addr_d),   .bank_id(bk_d),   .internal_addr(id_d));
    addr_resolver u_rew(.logical_addr(ext_waddr), .bank_id(ext_w_bk), .internal_addr(ext_w_id));
    addr_resolver u_rer(.logical_addr(ext_raddr), .bank_id(ext_r_bk), .internal_addr(ext_r_id));

    // =====================================================================
    // PMM 4 banks
    // =====================================================================
    reg  [3:0]        pmm_r_a0, pmm_r_a1, pmm_r_a2, pmm_r_a3;
    wire [4*W-1:0]    pmm_r_d0, pmm_r_d1, pmm_r_d2, pmm_r_d3;
    reg  [3:0]        pmm_w_a0, pmm_w_a1, pmm_w_a2, pmm_w_a3;
    reg  [3:0]        pmm_w_e0, pmm_w_e1, pmm_w_e2, pmm_w_e3;
    reg  [4*W-1:0]    pmm_w_d0, pmm_w_d1, pmm_w_d2, pmm_w_d3;

    poly_mem_4bank u_pmm(
        .clk(clk), .rst_n(rst_n),
        .r_addr0(pmm_r_a0), .r_addr1(pmm_r_a1), .r_addr2(pmm_r_a2), .r_addr3(pmm_r_a3),
        .r_data0(pmm_r_d0), .r_data1(pmm_r_d1), .r_data2(pmm_r_d2), .r_data3(pmm_r_d3),
        .w_addr0(pmm_w_a0), .w_addr1(pmm_w_a1), .w_addr2(pmm_w_a2), .w_addr3(pmm_w_a3),
        .w_we0(pmm_w_e0), .w_we1(pmm_w_e1), .w_we2(pmm_w_e2), .w_we3(pmm_w_e3),
        .w_data0(pmm_w_d0), .w_data1(pmm_w_d1), .w_data2(pmm_w_d2), .w_data3(pmm_w_d3)
    );

    // External read = pick bank by ext_r_bk
    assign ext_rdata = (ext_r_bk == 2'd0) ? pmm_r_d0 :
                       (ext_r_bk == 2'd1) ? pmm_r_d1 :
                       (ext_r_bk == 2'd2) ? pmm_r_d2 : pmm_r_d3;

    // =====================================================================
    // PMM_B (PWM  ,   b_hat = NTT(b)) - 4 bank
    // =====================================================================
    wire [1:0] ext_wb_bk;
    wire [3:0] ext_wb_id;
    addr_resolver u_rewb(.logical_addr(ext_waddr_b), .bank_id(ext_wb_bk), .internal_addr(ext_wb_id));

    reg  [3:0]        pmb_r_a0, pmb_r_a1, pmb_r_a2, pmb_r_a3;
    wire [4*W-1:0]    pmb_r_d0, pmb_r_d1, pmb_r_d2, pmb_r_d3;
    reg  [3:0]        pmb_w_a0, pmb_w_a1, pmb_w_a2, pmb_w_a3;
    reg  [3:0]        pmb_w_e0, pmb_w_e1, pmb_w_e2, pmb_w_e3;
    reg  [4*W-1:0]    pmb_w_d0, pmb_w_d1, pmb_w_d2, pmb_w_d3;

    poly_mem_4bank u_pmb(
        .clk(clk), .rst_n(rst_n),
        .r_addr0(pmb_r_a0), .r_addr1(pmb_r_a1), .r_addr2(pmb_r_a2), .r_addr3(pmb_r_a3),
        .r_data0(pmb_r_d0), .r_data1(pmb_r_d1), .r_data2(pmb_r_d2), .r_data3(pmb_r_d3),
        .w_addr0(pmb_w_a0), .w_addr1(pmb_w_a1), .w_addr2(pmb_w_a2), .w_addr3(pmb_w_a3),
        .w_we0(pmb_w_e0), .w_we1(pmb_w_e1), .w_we2(pmb_w_e2), .w_we3(pmb_w_e3),
        .w_data0(pmb_w_d0), .w_data1(pmb_w_d1), .w_data2(pmb_w_d2), .w_data3(pmb_w_d3)
    );

    // =====================================================================
    // CTU 4x4 - instantiated as separate ctu module
    // =====================================================================
    reg          ctu_we;
    reg [4*W-1:0] ctu_row_d0, ctu_row_d1, ctu_row_d2, ctu_row_d3;
    wire [4*4*W-1:0] ctu_mat_flat;

    ctu #( .W(W) ) u_ctu (
        .clk(clk), .rst_n(rst_n),
        .row_we(ctu_we),
        .row_d0(ctu_row_d0), .row_d1(ctu_row_d1),
        .row_d2(ctu_row_d2), .row_d3(ctu_row_d3),
        .mat_flat(ctu_mat_flat)
    );

    // =====================================================================
    // fau_top
    // =====================================================================
    reg          fau_in_valid;
    reg  [5:0]   fau_group_in;
    reg  [W-1:0] fau_d0, fau_d1, fau_d2, fau_d3;
    wire         fau_out_valid;
    wire [W-1:0] fau_o0, fau_o1, fau_o2, fau_o3;

    // PWM mode   coe1 (X=a_hat) / coe2 (Y=b_hat)
    //   PWM   PMM_A/PMM_B    bank   word,   4 cells   fau
    wire [4*W-1:0] pwm_a_word = (pwm_r_bk == 2'd0) ? pmm_r_d0 :
                                (pwm_r_bk == 2'd1) ? pmm_r_d1 :
                                (pwm_r_bk == 2'd2) ? pmm_r_d2 : pmm_r_d3;
    wire [4*W-1:0] pwm_b_word = (pwm_r_bk == 2'd0) ? pmb_r_d0 :
                                (pwm_r_bk == 2'd1) ? pmb_r_d1 :
                                (pwm_r_bk == 2'd2) ? pmb_r_d2 : pmb_r_d3;
    wire [W-1:0] pwm_a_c0 = pwm_a_word[1*W-1:0*W];
    wire [W-1:0] pwm_a_c1 = pwm_a_word[2*W-1:1*W];
    wire [W-1:0] pwm_a_c2 = pwm_a_word[3*W-1:2*W];
    wire [W-1:0] pwm_a_c3 = pwm_a_word[4*W-1:3*W];
    wire [W-1:0] pwm_b_c0 = pwm_b_word[1*W-1:0*W];
    wire [W-1:0] pwm_b_c1 = pwm_b_word[2*W-1:1*W];
    wire [W-1:0] pwm_b_c2 = pwm_b_word[3*W-1:2*W];
    wire [W-1:0] pwm_b_c3 = pwm_b_word[4*W-1:3*W];

    wire is_pwm = (op_mode == 2'd2);
    fau_top u_fau(
        .clk(clk), .rst_n(rst_n), .in_valid(fau_in_valid),
        .mode(op_mode), .stage(stage_cnt), .group(fau_group_in),
        .coe1_0(is_pwm ? pwm_a_c0 : {W{1'b0}}),
        .coe1_1(is_pwm ? pwm_a_c1 : {W{1'b0}}),
        .coe1_2(is_pwm ? pwm_a_c2 : {W{1'b0}}),
        .coe1_3(is_pwm ? pwm_a_c3 : {W{1'b0}}),
        .coe2_0(is_pwm ? pwm_b_c0 : {W{1'b0}}),
        .coe2_1(is_pwm ? pwm_b_c1 : {W{1'b0}}),
        .coe2_2(is_pwm ? pwm_b_c2 : {W{1'b0}}),
        .coe2_3(is_pwm ? pwm_b_c3 : {W{1'b0}}),
        .coe3_0(is_pwm ? {W{1'b0}} : fau_d0),
        .coe3_1(is_pwm ? {W{1'b0}} : fau_d1),
        .coe3_2(is_pwm ? {W{1'b0}} : fau_d2),
        .coe3_3(is_pwm ? {W{1'b0}} : fau_d3),
        .out_valid(fau_out_valid),
        .out0(fau_o0), .out1(fau_o1), .out2(fau_o2), .out3(fau_o3)
    );

    // =====================================================================
    //    c (0..3)     group index + 4
    // =====================================================================
    // c_in / c_out   wire     sub_cnt      always @(*) reg propagation
    wire [2:0]  c_in_w  = sub_cnt[2:0] - 3'd1;      // valid for sub 1..4
    wire [2:0]  c_out_w = sub_cnt - 5'd11;          // valid for sub 11..14
    wire [5:0] grp_idx_in  = grp_base + {3'b0, c_in_w[1:0]};
    wire [5:0] grp_idx_out = grp_base + {3'b0, c_out_w[1:0]};

    //   group g   4     (pos_j, pos_l1, pos_l2, pos_l1l2)
    //    stage_cnt   group g_idx
    function automatic [31:0] gen_positions;
        input [1:0] s;
        input [5:0] g;
        reg [7:0] pj, pl1, pl2, pl1l2;
        begin
            case (s)
                2'd0: begin pj = {2'b00, g}; pl1 = pj + 8'd128; pl2 = pj + 8'd64; pl1l2 = pj + 8'd192; end
                2'd1: begin pj = {g[5:4], 2'b00, g[3:0]}; pl1 = pj + 8'd32; pl2 = pj + 8'd16; pl1l2 = pj + 8'd48; end
                2'd2: begin pj = {g[5:2], 2'b00, g[1:0]}; pl1 = pj + 8'd8; pl2 = pj + 8'd4; pl1l2 = pj + 8'd12; end
                default: begin pj = {g, 2'b00}; pl1 = pj + 8'd2; pl2 = pj + 8'd1; pl1l2 = pj + 8'd3; end
            endcase
            gen_positions = {pj, pl1, pl2, pl1l2};
        end
    endfunction

    wire [31:0] pos_in_pack  = gen_positions(stage_cnt, grp_idx_in);
    wire [7:0]  pos_j_in     = pos_in_pack[31:24];
    wire [7:0]  pos_l1_in    = pos_in_pack[23:16];
    wire [7:0]  pos_l2_in    = pos_in_pack[15:8];
    wire [7:0]  pos_l1l2_in  = pos_in_pack[7:0];

    wire [31:0] pos_out_pack = gen_positions(stage_cnt, grp_idx_out);
    wire [7:0]  pos_j_out    = pos_out_pack[31:24];
    wire [7:0]  pos_l1_out   = pos_out_pack[23:16];
    wire [7:0]  pos_l2_out   = pos_out_pack[15:8];
    wire [7:0]  pos_l1l2_out = pos_out_pack[7:0];

    //       logical addr     CTU row (input phase)
    function [1:0] row_of;
        input [5:0] la;
        begin
            row_of = (la == addr_a) ? 2'd0 :
                     (la == addr_b) ? 2'd1 :
                     (la == addr_c) ? 2'd2 : 2'd3;
        end
    endfunction

    wire [1:0] r_j     = row_of(pos_j_in[7:2]);
    wire [1:0] r_l1    = row_of(pos_l1_in[7:2]);
    wire [1:0] r_l2    = row_of(pos_l2_in[7:2]);
    wire [1:0] r_l1l2  = row_of(pos_l1l2_in[7:2]);
    wire [1:0] c_j_in  = pos_j_in[1:0];
    wire [1:0] c_l1_in = pos_l1_in[1:0];
    wire [1:0] c_l2_in = pos_l2_in[1:0];
    wire [1:0] c_l1l2_in = pos_l1l2_in[1:0];

    // CTU col-read   FAU    (  )
    wire [W-1:0] x0_in = ctu_mat_flat[(r_j   *4 + c_j_in   )*W +: W];
    wire [W-1:0] x1_in = ctu_mat_flat[(r_l1  *4 + c_l1_in  )*W +: W];
    wire [W-1:0] x2_in = ctu_mat_flat[(r_l2  *4 + c_l2_in  )*W +: W];
    wire [W-1:0] x3_in = ctu_mat_flat[(r_l1l2*4 + c_l1l2_in)*W +: W];

    //     Writeback phase: 4        (bank, cell)
    //   NTT (ntt_r4):  A0 pos_j, A1 pos_l2, A2 pos_l1, A3 pos_l1l2
    //   INTT (intt_r4): B0 pos_j, B1 pos_l1, B2 pos_l2, B3 pos_l1l2
    //          slot1/slot2   fau_o   :    slot1=pos_l2_out, slot2=pos_l1_out,
    //       INTT     fau_o1<->fau_o2      (   wire mux   NTT      iverilog
    //     propagation   )
    wire [1:0] bw_a0, bw_a1, bw_a2, bw_a3;
    wire [3:0] iw_a0, iw_a1, iw_a2, iw_a3;
    wire [1:0] cw_a0 = pos_j_out[1:0];
    wire [1:0] cw_a1 = pos_l2_out[1:0];
    wire [1:0] cw_a2 = pos_l1_out[1:0];
    wire [1:0] cw_a3 = pos_l1l2_out[1:0];
    addr_resolver u_wa0(.logical_addr(pos_j_out[7:2]),    .bank_id(bw_a0), .internal_addr(iw_a0));
    addr_resolver u_wa1(.logical_addr(pos_l2_out[7:2]),   .bank_id(bw_a1), .internal_addr(iw_a1));
    addr_resolver u_wa2(.logical_addr(pos_l1_out[7:2]),   .bank_id(bw_a2), .internal_addr(iw_a2));
    addr_resolver u_wa3(.logical_addr(pos_l1l2_out[7:2]), .bank_id(bw_a3), .internal_addr(iw_a3));

    // Slot data: NTT   fau_o    , INTT   slot1/slot2     fau_o
    wire [W-1:0] wd0 = fau_o0;
    wire [W-1:0] wd1 = (op_mode == 2'd1) ? fau_o2 : fau_o1;
    wire [W-1:0] wd2 = (op_mode == 2'd1) ? fau_o1 : fau_o2;
    wire [W-1:0] wd3 = fau_o3;

    //     per bank b:    targets     bank
    // target i: (bank=bw_ai, cell=cw_ai, value=fau_oi)
    wire wb_active = running && fau_out_valid && (sub_cnt >= 5'd11) && (sub_cnt <= 5'd14);

    //   bank b: 4 targets    match
    // since conflict-free for stage 0/1/2: 4 banks distinct
    // for stage 3: all 4 targets same bank (=bw_a0), cells (0,1,2,3) all
    function [W-1:0] pick_data;
        input [1:0] b;
        input [1:0] c;
        begin
            pick_data = (bw_a0 == b && cw_a0 == c) ? wd0 :
                        (bw_a1 == b && cw_a1 == c) ? wd1 :
                        (bw_a2 == b && cw_a2 == c) ? wd2 :
                        (bw_a3 == b && cw_a3 == c) ? wd3 : {W{1'b0}};
        end
    endfunction

    function pick_we;
        input [1:0] b;
        input [1:0] c;
        begin
            pick_we = (bw_a0 == b && cw_a0 == c) ||
                      (bw_a1 == b && cw_a1 == c) ||
                      (bw_a2 == b && cw_a2 == c) ||
                      (bw_a3 == b && cw_a3 == c);
        end
    endfunction

    function [3:0] pick_addr;
        input [1:0] b;
        begin
            pick_addr = (bw_a0 == b) ? iw_a0 :
                        (bw_a1 == b) ? iw_a1 :
                        (bw_a2 == b) ? iw_a2 : iw_a3;
        end
    endfunction

    // =====================================================================
    //    datapath /
    // =====================================================================

    // PMM read addr:    bank,   batch     bank     logical addr   internal id
    wire [3:0] pmm_run_r0 = (bk_a==2'd0) ? id_a :
                            (bk_b==2'd0) ? id_b :
                            (bk_c==2'd0) ? id_c : id_d;
    wire [3:0] pmm_run_r1 = (bk_a==2'd1) ? id_a :
                            (bk_b==2'd1) ? id_b :
                            (bk_c==2'd1) ? id_c : id_d;
    wire [3:0] pmm_run_r2 = (bk_a==2'd2) ? id_a :
                            (bk_b==2'd2) ? id_b :
                            (bk_c==2'd2) ? id_c : id_d;
    wire [3:0] pmm_run_r3 = (bk_a==2'd3) ? id_a :
                            (bk_b==2'd3) ? id_b :
                            (bk_c==2'd3) ? id_c : id_d;

    // PMM   port mux: RUN    FSM internals, PWM    pwm_r_id, IDLE    ext_r_id
    always @(*) begin
        if (running) begin
            pmm_r_a0 = pmm_run_r0;
            pmm_r_a1 = pmm_run_r1;
            pmm_r_a2 = pmm_run_r2;
            pmm_r_a3 = pmm_run_r3;
        end else if (pwm_running) begin
            pmm_r_a0 = pwm_r_id;
            pmm_r_a1 = pwm_r_id;
            pmm_r_a2 = pwm_r_id;
            pmm_r_a3 = pwm_r_id;
        end else begin
            pmm_r_a0 = ext_r_id;
            pmm_r_a1 = ext_r_id;
            pmm_r_a2 = ext_r_id;
            pmm_r_a3 = ext_r_id;
        end
    end

    // PMM_B   port: PWM    pwm_r_id,    default 0
    always @(*) begin
        if (pwm_running) begin
            pmb_r_a0 = pwm_r_id;
            pmb_r_a1 = pwm_r_id;
            pmb_r_a2 = pwm_r_id;
            pmb_r_a3 = pwm_r_id;
        end else begin
            pmb_r_a0 = 4'h0;
            pmb_r_a1 = 4'h0;
            pmb_r_a2 = 4'h0;
            pmb_r_a3 = 4'h0;
        end
    end

    // CTU row data: row r    logical addr_{a/b/c/d}
    //   ctu_row_dR = PMM word at bank bk_{r}
    wire [4*W-1:0] word_a = (bk_a == 2'd0) ? pmm_r_d0 :
                            (bk_a == 2'd1) ? pmm_r_d1 :
                            (bk_a == 2'd2) ? pmm_r_d2 : pmm_r_d3;
    wire [4*W-1:0] word_b = (bk_b == 2'd0) ? pmm_r_d0 :
                            (bk_b == 2'd1) ? pmm_r_d1 :
                            (bk_b == 2'd2) ? pmm_r_d2 : pmm_r_d3;
    wire [4*W-1:0] word_c = (bk_c == 2'd0) ? pmm_r_d0 :
                            (bk_c == 2'd1) ? pmm_r_d1 :
                            (bk_c == 2'd2) ? pmm_r_d2 : pmm_r_d3;
    wire [4*W-1:0] word_d = (bk_d == 2'd0) ? pmm_r_d0 :
                            (bk_d == 2'd1) ? pmm_r_d1 :
                            (bk_d == 2'd2) ? pmm_r_d2 : pmm_r_d3;

    //      (per sub_cnt / pwm_cnt)
    always @(*) begin
        //
        ctu_we = 1'b0;
        ctu_row_d0 = word_a; ctu_row_d1 = word_b;
        ctu_row_d2 = word_c; ctu_row_d3 = word_d;
        fau_in_valid = 1'b0;
        fau_group_in = grp_base;
        fau_d0 = 0; fau_d1 = 0; fau_d2 = 0; fau_d3 = 0;

        // PMM_A write
        pmm_w_a0 = 4'h0; pmm_w_a1 = 4'h0; pmm_w_a2 = 4'h0; pmm_w_a3 = 4'h0;
        pmm_w_e0 = 4'h0; pmm_w_e1 = 4'h0; pmm_w_e2 = 4'h0; pmm_w_e3 = 4'h0;
        pmm_w_d0 = 0; pmm_w_d1 = 0; pmm_w_d2 = 0; pmm_w_d3 = 0;
        // PMM_B write
        pmb_w_a0 = 4'h0; pmb_w_a1 = 4'h0; pmb_w_a2 = 4'h0; pmb_w_a3 = 4'h0;
        pmb_w_e0 = 4'h0; pmb_w_e1 = 4'h0; pmb_w_e2 = 4'h0; pmb_w_e3 = 4'h0;
        pmb_w_d0 = 0; pmb_w_d1 = 0; pmb_w_d2 = 0; pmb_w_d3 = 0;

        if (running) begin
            // sub=0: PMM 4-bank parallel read   CTU 4-row parallel write
            if (sub_cnt == 5'd0) begin
                ctu_we = 1'b1;
            end
            // sub=1..4: CTU col-read   FAU input
            else if (sub_cnt >= 5'd1 && sub_cnt <= 5'd4) begin
                fau_in_valid = 1'b1;
                fau_group_in = grp_idx_in;
                fau_d0 = x0_in;
                fau_d1 = (op_mode == 2'd1) ? x2_in : x1_in;
                fau_d2 = (op_mode == 2'd1) ? x1_in : x2_in;
                fau_d3 = x3_in;
            end
            // sub=11..14: FAU output   PMM cell-wise write
            else if (sub_cnt >= 5'd11 && sub_cnt <= 5'd14) begin
                if (fau_out_valid) begin
                    //   4 banks     (addr, we, data)   4 cells per bank
                    pmm_w_a0 = pick_addr(2'd0);
                    pmm_w_a1 = pick_addr(2'd1);
                    pmm_w_a2 = pick_addr(2'd2);
                    pmm_w_a3 = pick_addr(2'd3);
                    pmm_w_e0 = { pick_we(2'd0, 2'd3), pick_we(2'd0, 2'd2),
                                 pick_we(2'd0, 2'd1), pick_we(2'd0, 2'd0) };
                    pmm_w_e1 = { pick_we(2'd1, 2'd3), pick_we(2'd1, 2'd2),
                                 pick_we(2'd1, 2'd1), pick_we(2'd1, 2'd0) };
                    pmm_w_e2 = { pick_we(2'd2, 2'd3), pick_we(2'd2, 2'd2),
                                 pick_we(2'd2, 2'd1), pick_we(2'd2, 2'd0) };
                    pmm_w_e3 = { pick_we(2'd3, 2'd3), pick_we(2'd3, 2'd2),
                                 pick_we(2'd3, 2'd1), pick_we(2'd3, 2'd0) };
                    pmm_w_d0 = { pick_data(2'd0,2'd3), pick_data(2'd0,2'd2),
                                 pick_data(2'd0,2'd1), pick_data(2'd0,2'd0) };
                    pmm_w_d1 = { pick_data(2'd1,2'd3), pick_data(2'd1,2'd2),
                                 pick_data(2'd1,2'd1), pick_data(2'd1,2'd0) };
                    pmm_w_d2 = { pick_data(2'd2,2'd3), pick_data(2'd2,2'd2),
                                 pick_data(2'd2,2'd1), pick_data(2'd2,2'd0) };
                    pmm_w_d3 = { pick_data(2'd3,2'd3), pick_data(2'd3,2'd2),
                                 pick_data(2'd3,2'd1), pick_data(2'd3,2'd0) };
                end
            end
        end else if (pwm_running) begin
            // PWM: dispatch when cnt<64, fau valid
            if (pwm_disp) fau_in_valid = 1'b1;
            // writeback: cnt>=5 (=      fau output    5 cycle pipeline)
            if (pwm_writeb && fau_out_valid) begin
                //     word   pwm_w_bk    bank
                case (pwm_w_bk)
                    2'd0: begin
                        pmm_w_a0 = pwm_w_id;
                        pmm_w_e0 = 4'b1111;
                        pmm_w_d0 = {fau_o3, fau_o2, fau_o1, fau_o0};
                    end
                    2'd1: begin
                        pmm_w_a1 = pwm_w_id;
                        pmm_w_e1 = 4'b1111;
                        pmm_w_d1 = {fau_o3, fau_o2, fau_o1, fau_o0};
                    end
                    2'd2: begin
                        pmm_w_a2 = pwm_w_id;
                        pmm_w_e2 = 4'b1111;
                        pmm_w_d2 = {fau_o3, fau_o2, fau_o1, fau_o0};
                    end
                    default: begin
                        pmm_w_a3 = pwm_w_id;
                        pmm_w_e3 = 4'b1111;
                        pmm_w_d3 = {fau_o3, fau_o2, fau_o1, fau_o0};
                    end
                endcase
            end
        end else begin
            // IDLE/DONE:      ext_we   PMM_A   ext_we_b   PMM_B
            if (ext_we) begin
                pmm_w_a0 = ext_w_id; pmm_w_a1 = ext_w_id;
                pmm_w_a2 = ext_w_id; pmm_w_a3 = ext_w_id;
                pmm_w_d0 = ext_wdata; pmm_w_d1 = ext_wdata;
                pmm_w_d2 = ext_wdata; pmm_w_d3 = ext_wdata;
                case (ext_w_bk)
                    2'd0: pmm_w_e0 = 4'b1111;
                    2'd1: pmm_w_e1 = 4'b1111;
                    2'd2: pmm_w_e2 = 4'b1111;
                    default: pmm_w_e3 = 4'b1111;
                endcase
            end
            if (ext_we_b) begin
                pmb_w_a0 = ext_wb_id; pmb_w_a1 = ext_wb_id;
                pmb_w_a2 = ext_wb_id; pmb_w_a3 = ext_wb_id;
                pmb_w_d0 = ext_wdata_b; pmb_w_d1 = ext_wdata_b;
                pmb_w_d2 = ext_wdata_b; pmb_w_d3 = ext_wdata_b;
                case (ext_wb_bk)
                    2'd0: pmb_w_e0 = 4'b1111;
                    2'd1: pmb_w_e1 = 4'b1111;
                    2'd2: pmb_w_e2 = 4'b1111;
                    default: pmb_w_e3 = 4'b1111;
                endcase
            end
        end
    end


    // FSM next-state
    // =====================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            stage_cnt <= 0; batch_cnt <= 0; sub_cnt <= 0;
            pwm_cnt <= 0;
            done <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        if (op_mode == 2'd2) begin
                            state <= S_RUN_PWM;
                            pwm_cnt <= 0;
                        end else begin
                            state <= S_RUN;
                            stage_cnt <= (op_mode == 2'd1) ? 2'd3 : 2'd0;
                            batch_cnt <= 0; sub_cnt <= 0;
                        end
                        done <= 1'b0;
                    end
                end
                S_RUN: begin
                    if (sub_cnt == 5'd14) begin
                        sub_cnt <= 0;
                        if (batch_cnt == 4'd15) begin
                            batch_cnt <= 0;
                            if ((op_mode == 2'd1) ? (stage_cnt == 2'd0) : (stage_cnt == 2'd3)) begin
                                state <= S_DONE;
                                done <= 1'b1;
                            end else begin
                                stage_cnt <= (op_mode == 2'd1) ? (stage_cnt - 2'd1) : (stage_cnt + 2'd1);
                            end
                        end else begin
                            batch_cnt <= batch_cnt + 1;
                        end
                    end else begin
                        sub_cnt <= sub_cnt + 1;
                    end
                end
                S_RUN_PWM: begin
                    if (pwm_cnt == 7'd68) begin
                        state <= S_DONE;
                        done <= 1'b1;
                        pwm_cnt <= 0;
                    end else begin
                        pwm_cnt <= pwm_cnt + 1;
                    end
                end
                S_DONE: begin
                    if (start) begin
                        if (op_mode == 2'd2) begin
                            state <= S_RUN_PWM;
                            pwm_cnt <= 0;
                        end else begin
                            state <= S_RUN;
                            stage_cnt <= (op_mode == 2'd1) ? 2'd3 : 2'd0;
                            batch_cnt <= 0; sub_cnt <= 0;
                        end
                        done <= 1'b0;
                    end
                end
            endcase
        end
    end
endmodule