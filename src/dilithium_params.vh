// ============================================================================
//  dilithium_params.vh  --  Dilithium
//           RTL        `include "dilithium_params.vh"
//                 rst_n
// ============================================================================
`ifndef DILITHIUM_PARAMS_VH
`define DILITHIUM_PARAMS_VH

// -----   /     ----------------------------------------------------------
`define DILI_Q        8380417     //    q = 2^23 - 2^13 + 1
`define DILI_N        256         //
`define DILI_LOGN     8

// -----        ---------------------------------------------------------
`define DILI_CW       23          //      bit           --
`define DILI_CW1      24          //    +1               --

// ----- Barrett       mod_mult    -----------------------------------
`define DILI_TBAR     8396807     // floor(2^46 / q)
`define DILI_BARW     24          // Barrett

// ----- radix-4       NTT/INTT      -------------------------------
`define DILI_RADIX    4
`define DILI_NSTAGE   4           // 256 = 4^4
`define DILI_BFPS     64          //    stage   radix-4

`endif // DILITHIUM_PARAMS_VH
