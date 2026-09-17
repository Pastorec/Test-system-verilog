//systemVerilog HDL for "MZNOVA_design", "stim_REG_VDDPIX_TOP" "systemVerilog"
//
// -------------------------------------------------------------------------------
//  REVISION NOTE -- see doc/DEBUG_NOTES.md
//
//  The original stimulus drove every analog pin as a 1-bit `logic` and powered up
//  with 'b1, which lands on the analog nets as 1.0. That put AVDD at 1.0 V (spec
//  2.4 .. 3.7), both grounds at 1.0 V (spec < 0.1), IBIAS at 1.0 A (spec 5 uA) and
//  VREF at 1.0 V (spec 1.1 V). It also assigned vana (2.5) to AVDD1V1 and vdig
//  (1.2) to the 4-bit SELDRIVE bus -- the two constants were swapped.
//
//  Result: s_enable_power and s_enable_ref were 0 for the whole run and VDDPIX
//  never left 0 V. That is the reason VDDPIX stayed low.
//
//  Fixed here:
//    - analog pins are real_net and are driven with real voltages / currents
//    - vana / vdig applied to the right pins
//    - VDDPIX is read as an analog value, not as a bit
//    - SEL dwell time is longer than the regulator settling time, so each code
//      is sampled after VDDPIX has actually settled
//    - the commented-out chk_bit() calls are replaced by working chk_real()
//      checks; a bit-compare is meaningless on an analog output
// -------------------------------------------------------------------------------

`timescale 1ps/1ps

module stim_REG_VDDPIX_TOP ( REGVDDPIX_ENABLE_PULLUP_GO1,
 VDDPIX, BG_ENABLE_OK_AVDD, VBG_REGVDDPIX_1V1, REGVDDPIX_DISABLE_PULLDOWN_GO1,
 DVDD1V1, REGVDDPIX_SEL_GO1, POR_DVDD1V1_AVDD, REGVDDPIX_ATEST,
 REGVDDPIX_ENABLE_GO1, AVSS_REF_REGVDDPIX, AVSS, REGVDDPIX_SEL_ATEST_GO1,
 REGVDDPIX_SELDRIVE_GO1, IBIAS_REGVDDPIX_5U, AVDD, AVSSPIX,
 AVDD1V1 );

   import elec_net_pkg::*;

   // ---- digital ----------------------------------------------------------
   output logic          REGVDDPIX_ENABLE_PULLUP_GO1;
   output logic          BG_ENABLE_OK_AVDD;
   output logic          REGVDDPIX_DISABLE_PULLDOWN_GO1;
   output logic   [3:0]  REGVDDPIX_SEL_GO1;
   output logic          POR_DVDD1V1_AVDD;
   output logic          REGVDDPIX_ENABLE_GO1;
   output logic          REGVDDPIX_SEL_ATEST_GO1;
   output logic   [3:0]  REGVDDPIX_SELDRIVE_GO1;

   // ---- analog (was `logic` -- that is the bug) ---------------------------
   input  real_net       VDDPIX;
   input  real_net       REGVDDPIX_ATEST;
   output real_net       VBG_REGVDDPIX_1V1;
   output real_net       DVDD1V1;
   output real_net       AVSS_REF_REGVDDPIX;
   output real_net       AVSS;
   output real_net       IBIAS_REGVDDPIX_5U;
   output real_net       AVDD;
   output real_net       AVSSPIX;
   output real_net       AVDD1V1;

// -----------------------------------------------------------------------------
// Operating point
// -----------------------------------------------------------------------------
parameter real vana    = 2.5;      // AVDD            spec 2.4 .. 3.7 V
parameter real vdig    = 1.2;      // AVDD1V1/DVDD1V1 spec 0.8 .. 1.3 V
parameter real vref    = 1.1;      // VBG             spec 1.078 .. 1.122 V
parameter real ibias5u = 5.0e-6;   // 5 x 1uA         spec 4.5u .. 5.5u A
parameter real vss     = 0.0;

// SEL dwell time. Must exceed the regulator settling time (POR_VDDPIX_ASSERT,
// 10us by default) or every code is sampled mid-transition. The original 1us
// step was 10x too short.
parameter time T_STEP        = 20us;
parameter time T_SETTLE      = 12us;   // > POR_VDDPIX_ASSERT
parameter time T_RELEASE     = 360us;  // > POR_VDDPIX_RELEASE

// Expected transfer function, mirrored from the model parameters.
parameter real VDDPIX_BASE   = 0.87;
parameter real VDDPIX_STEP   = 0.08;
parameter real VDDPIX_TOL    = 0.001;

// -----------------------------------------------------------------------------
// Analog nets are nettypes: drive them from a real variable via a continuous
// assignment (same pattern the model uses for VDDPIX).
// -----------------------------------------------------------------------------
real r_avdd, r_avdd1v1, r_dvdd1v1, r_avss, r_avss_ref, r_avsspix;
real r_ibias, r_vbg;

assign AVDD               = r_avdd;
assign AVDD1V1            = r_avdd1v1;
assign DVDD1V1            = r_dvdd1v1;
assign AVSS               = r_avss;
assign AVSS_REF_REGVDDPIX = r_avss_ref;
assign AVSSPIX            = r_avsspix;
assign IBIAS_REGVDDPIX_5U = r_ibias;
assign VBG_REGVDDPIX_1V1  = r_vbg;

int n_pass = 0;
int n_fail = 0;

// -----------------------------------------------------------------------------
// Checkers
// -----------------------------------------------------------------------------
task automatic chk_real (input real expected, input real actual,
                         input real tol, input string msg);
  if (actual > expected - tol && actual < expected + tol) begin
    n_pass++;
    $display("   PASS  [%0t] %-52s exp=%7.4f got=%7.4f", $time, msg, expected, actual);
  end
  else begin
    n_fail++;
    $display("***FAIL  [%0t] %-52s exp=%7.4f got=%7.4f", $time, msg, expected, actual);
  end
endtask

task automatic chk_low (input real actual, input string msg);
  chk_real(0.0, actual, VDDPIX_TOL, msg);
endtask

// -----------------------------------------------------------------------------
// Stimulus
// -----------------------------------------------------------------------------
initial begin
  $display("=============================================================================");
  $display(" stim_REG_VDDPIX_TOP");
  $display("=============================================================================");

  // --- everything off -------------------------------------------------------
  $display("\n-- all outputs set to 0 --");
  REGVDDPIX_ENABLE_PULLUP_GO1    = 1'b0;
  BG_ENABLE_OK_AVDD              = 1'b0;
  REGVDDPIX_DISABLE_PULLDOWN_GO1 = 1'b0;
  REGVDDPIX_SEL_GO1              = 4'b0000;
  POR_DVDD1V1_AVDD               = 1'b0;
  REGVDDPIX_ENABLE_GO1           = 1'b0;
  REGVDDPIX_SEL_ATEST_GO1        = 1'b0;
  REGVDDPIX_SELDRIVE_GO1         = 4'b0000;

  r_avdd = 0.0; r_avdd1v1 = 0.0; r_dvdd1v1 = 0.0;
  r_avss = 0.0; r_avss_ref = 0.0; r_avsspix = 0.0;
  r_ibias = 0.0; r_vbg = 0.0;

  #1us;
  $display("\n-- no supplies --");
  chk_low(VDDPIX, "VDDPIX with no supplies");

  // --- supplies up ----------------------------------------------------------
  r_avdd     = vana;    // 2.5 V   (was 'b1 -> 1.0 V, out of spec)
  r_avdd1v1  = vdig;    // 1.2 V   (was vana = 2.5 V, out of spec)
  r_dvdd1v1  = vdig;
  r_avss     = vss;     // 0.0 V   (was 'b1 -> 1.0 V, out of spec)
  r_avss_ref = vss;     // 0.0 V   (was 'b1 -> 1.0 V, out of spec)
  r_avsspix  = vss;
  REGVDDPIX_SELDRIVE_GO1 = 4'b1000;

  #1us;
  $display("\n-- with supplies, references still off --");
  chk_low(VDDPIX, "VDDPIX with supplies but no references");

  // --- references up --------------------------------------------------------
  r_ibias = ibias5u;    // 5 uA    (was 'b1 -> 1.0 A)
  r_vbg   = vref;       // 1.1 V   (was 'b1 -> 1.0 V)
  POR_DVDD1V1_AVDD            = 1'b1;
  BG_ENABLE_OK_AVDD           = 1'b1;
  REGVDDPIX_ENABLE_PULLUP_GO1 = 1'b1;
  REGVDDPIX_SEL_ATEST_GO1     = 1'b1;

  #1us;
  $display("\n-- references up, regulator still disabled --");
  chk_low(VDDPIX, "VDDPIX with references but regulator disabled");

  // --- enable ---------------------------------------------------------------
  $display("\n-- enable regulator --");
  REGVDDPIX_SEL_GO1              = 4'b0000;
  REGVDDPIX_ENABLE_GO1           = 1'b1;
  REGVDDPIX_DISABLE_PULLDOWN_GO1 = 1'b1;

  #T_SETTLE;
  chk_real(VDDPIX_BASE, VDDPIX, VDDPIX_TOL, "VDDPIX after enable, SEL=4'b0000");

  // --- sweep the trim code --------------------------------------------------
  $display("\n-- sweep REGVDDPIX_SEL_GO1 --");
  for (int i = 0; i < 16; i++) begin
    REGVDDPIX_SEL_GO1 = i[3:0];
    #T_STEP;
    chk_real(VDDPIX_BASE + VDDPIX_STEP*i, VDDPIX, VDDPIX_TOL,
             $sformatf("VDDPIX with REGVDDPIX_SEL_GO1=4'b%04b", i[3:0]));
  end

  REGVDDPIX_SEL_GO1 = 4'b0000;
  #T_STEP;
  chk_real(VDDPIX_BASE, VDDPIX, VDDPIX_TOL, "VDDPIX back at SEL=4'b0000");

  // --- disable with the pull-down active (fast discharge) -------------------
  $display("\n-- disable, pull-down ACTIVE (expect fast discharge) --");
  REGVDDPIX_DISABLE_PULLDOWN_GO1 = 1'b0;
  REGVDDPIX_ENABLE_GO1           = 1'b0;
  #T_SETTLE;
  chk_low(VDDPIX, "VDDPIX after disable with pull-down active");

  // --- re-enable, then disable with the pull-down defeated (slow decay) -----
  $display("\n-- re-enable --");
  REGVDDPIX_ENABLE_GO1           = 1'b1;
  REGVDDPIX_DISABLE_PULLDOWN_GO1 = 1'b1;
  #T_SETTLE;
  chk_real(VDDPIX_BASE, VDDPIX, VDDPIX_TOL, "VDDPIX after re-enable");

  $display("\n-- disable, pull-down DEFEATED (expect slow decay) --");
  REGVDDPIX_ENABLE_GO1 = 1'b0;
  #T_SETTLE;
  chk_real(VDDPIX_BASE, VDDPIX, VDDPIX_TOL, "VDDPIX still up before POR_VDDPIX_RELEASE");
  #T_RELEASE;
  chk_low(VDDPIX, "VDDPIX after POR_VDDPIX_RELEASE");

  // --- a bad supply must hold the output low --------------------------------
  $display("\n-- re-enable with AVDD out of spec (expect VDDPIX held low) --");
  REGVDDPIX_ENABLE_GO1           = 1'b1;
  REGVDDPIX_DISABLE_PULLDOWN_GO1 = 1'b1;
  r_avdd = 1.0;                                  // below AVDD_MIN
  #T_SETTLE;
  chk_low(VDDPIX, "VDDPIX with AVDD below AVDD_MIN");

  r_avdd = vana;                                 // back in spec
  #T_SETTLE;
  chk_real(VDDPIX_BASE, VDDPIX, VDDPIX_TOL, "VDDPIX recovers once AVDD is back in spec");

  // --- summary --------------------------------------------------------------
  $display("\n=============================================================================");
  $display(" RESULT: %0d passed, %0d failed", n_pass, n_fail);
  if (n_fail == 0) $display(" *** TEST PASSED ***");
  else             $display(" *** TEST FAILED ***");
  $display("=============================================================================");
  $finish();
end

endmodule
