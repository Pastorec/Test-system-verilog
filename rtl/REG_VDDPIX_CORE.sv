// -------------------------------------------------------------------------------
//  Project : EWOKMZ
//
//                             COPYRIGHT (c) 2014
//                  ST Microelectronics - All rights reserved
//
// This file and its contents are the ownership of STMicroelectronics.
// Under International Copyright laws, No part of this document can be
// copied, or reproduced, or translated, or stored on electronic storage
// without the prior written agreement of STM.
//
//                      ID Groups / IBP Division / AMS Design
//                        12, rue Jules Horowitz BP.217
//                       F-38019 GRENOBLE CEDEX - FRANCE
//
// -------------------------------------------------------------------------------
//
//  REVISION NOTE -- behavioural fixes, see doc/DEBUG_NOTES.md
//
//  1. The settling process was a plain `always` block with a blocking `#delay`
//     inside it. Verilog does NOT queue events for an `always` block while that
//     block is executing, so every change arriving during the delay was lost.
//     With SEL stepping every 1us and POR_VDDPIX_ASSERT = 10us, 9 out of 10 SEL
//     changes were dropped, and the enable edge itself was dropped whenever it
//     landed inside the power-up window. It is now a re-triggerable one-shot.
//  2. The individual analog checks are broken out so the model can say *which*
//     supply/reference is out of range instead of silently holding VDDPIX low.
//  3. The dead commented-out clamp had an inverted upper bound
//     (`if (s_vddpix < 1.3) s_vddpix = 1.3;` forces everything UP to 1.3).
//     It is replaced by a correct, parameterised clamp, OFF by default so the
//     transfer function is unchanged until you confirm it against the spec.
//
// -------------------------------------------------------------------------------

`timescale 1ps / 1ps

module REG_VDDPIX_CORE
#( // Parameters
   parameter time POR_VDDPIX_RELEASE    = 355us,  // From ANA sims - worst case
   parameter time POR_VDDPIX_ASSERT     = 10us,    // From ANA sims

   parameter real AVDD_MAX	  = 3.7,
   parameter real AVDD_MIN	  = 2.4,

   parameter real AVDD1V1_MAX	  = 1.3,
   parameter real AVDD1V1_MIN	  = 0.8,

   parameter real VSS_MAX 	  = 0.1,

   parameter real IBIAS_1U_MAX 	  = 1.0e-6*1.1,
   parameter real IBIAS_1U_MIN 	  = 1.0e-6*0.9,

   parameter real VREF_1V0_MAX 	  = 1.0*1.02,
   parameter real VREF_1V0_MIN 	  = 1.0*0.98,

   // ---------------------------------------------------------------------------
   // Output transfer function: VDDPIX = VDDPIX_BASE + VDDPIX_STEP * SEL
   // ---------------------------------------------------------------------------
   parameter real VDDPIX_BASE	  = 0.87,
   parameter real VDDPIX_STEP	  = 0.08,

   // Legal output window. Always used for the range warning; only used to clamp
   // the output when VDDPIX_CLAMP_EN = 1.
   //
   // NOTE: with BASE/STEP above, SEL = 4'hF gives 0.87 + 15*0.08 = 2.07 V, which
   // is well outside this window. Either the coefficients or the SEL range need
   // confirming against the analog spec -- see doc/DEBUG_NOTES.md.
   parameter real VDDPIX_MIN	  = 0.8,
   parameter real VDDPIX_MAX	  = 1.3,
   parameter bit  VDDPIX_CLAMP_EN = 1'b0,   // 0 = original (unclamped) behaviour

   // Print a message naming the failing check when the regulator is asked to
   // turn on but the analog conditions are not met.
   parameter bit  DIAG_ON         = 1'b1
)

 ( VDDPIX, AVDD, AVDD1V1, AVSS, AVSS_REF_REGVDDPIX, BG_ENABLE_OK_AVDD,
IBIAS_REGVDDPIX_5U, POR_DVDD1V1_AVDD, REGVDDPIX_DISABLE_PULLDOWN_AVDD, REGVDDPIX_ENABLE_AVDD,
REGVDDPIX_ENABLE_PULLUP_AVDD, REGVDDPIX_SELDRIVE_AVDD, REGVDDPIX_SEL_AVDD, VREF_REG_VDDPIX_1V1
);

  input REGVDDPIX_ENABLE_AVDD;
  input BG_ENABLE_OK_AVDD;
  input AVDD1V1;
  input  [3:0] REGVDDPIX_SELDRIVE_AVDD;
  output VDDPIX;
  input IBIAS_REGVDDPIX_5U;
  input POR_DVDD1V1_AVDD;
  input VREF_REG_VDDPIX_1V1;
  input  [3:0] REGVDDPIX_SEL_AVDD;
  input REGVDDPIX_ENABLE_PULLUP_AVDD;
  input AVSS;
  input REGVDDPIX_DISABLE_PULLDOWN_AVDD;
  input AVSS_REF_REGVDDPIX;
  input AVDD;

//------------------------------------------------------------------------------
// Signals definition
//------------------------------------------------------------------------------
  import elec_net_pkg::*;

  real_net AVSS, AVSS_REF_REGVDDPIX, AVDD, AVDD1V1;
  real_net VREF_REG_VDDPIX_1V1, IBIAS_REGVDDPIX_5U;
  real_net VDDPIX;

  logic REGVDDPIX_ENABLE_AVDD, REGVDDPIX_DISABLE_PULLDOWN_AVDD, REGVDDPIX_ENABLE_PULLUP_AVDD;

//------------------------------------------------------------------------------
// Internal signals
//------------------------------------------------------------------------------
  real  s_vddpix;             // driven value of VDDPIX
  real  s_vddpix_target;      // level VDDPIX is heading towards
  time  s_settle_delay;       // delay to apply before reaching the target
  event e_retrigger;          // fires whenever the request changes

  logic s_enable_global, s_enable_power, s_enable_ref, s_enable_checks;
  logic s_enable_req;         // enable asked for, regardless of the analog checks

  // Individual checks, kept separate so diagnostics can name the offender.
  logic s_chk_avss, s_chk_avss_ref, s_chk_avdd, s_chk_avdd1v1;
  logic s_chk_ibias, s_chk_vref;

  logic disable_analog_checks = 1'b0;

//------------------------------------------------------------------------------
// Output definition
//------------------------------------------------------------------------------
  assign VDDPIX = s_vddpix;

//------------------------------------------------------------------------------
// CHECKS
//------------------------------------------------------------------------------
  assign s_chk_avss_ref = (AVSS_REF_REGVDDPIX < VSS_MAX);
  assign s_chk_avss     = (AVSS < VSS_MAX);
  assign s_chk_avdd1v1  = (AVDD1V1_MIN < AVDD1V1 && AVDD1V1 < AVDD1V1_MAX);
  assign s_chk_avdd     = (AVDD_MIN < AVDD && AVDD < AVDD_MAX);

  assign s_chk_ibias    = (5.0*IBIAS_1U_MIN < IBIAS_REGVDDPIX_5U
                        && IBIAS_REGVDDPIX_5U < 5.0*IBIAS_1U_MAX);
  assign s_chk_vref     = (1.1*VREF_1V0_MIN < VREF_REG_VDDPIX_1V1
                        && VREF_REG_VDDPIX_1V1 < 1.1*VREF_1V0_MAX);

  assign s_enable_power = (s_chk_avss_ref && s_chk_avss
                        && s_chk_avdd1v1 && s_chk_avdd  )? 1'b1: 1'b0;

  assign s_enable_ref   = (s_chk_ibias && s_chk_vref     )? 1'b1: 1'b0;

  assign s_enable_checks = (disable_analog_checks)? 1'b1: s_enable_power && s_enable_ref;

  // Enable as requested by the digital side, before the analog checks are applied.
  assign s_enable_req    = (BG_ENABLE_OK_AVDD === 1'b1
                        &&  REGVDDPIX_ENABLE_AVDD === 1'b1)? 1'b1: 1'b0;

  assign s_enable_global = (s_enable_checks && s_enable_req)? 1'b1: 1'b0;

//------------------------------------------------------------------------------
// Target level
//------------------------------------------------------------------------------
  function automatic real f_vddpix_level (input logic [3:0] sel);
    real lvl;
    if (^sel === 1'bx) begin        // unknown trim code -> hold at 0
      f_vddpix_level = 0.0;
    end
    else begin
      lvl = VDDPIX_BASE + VDDPIX_STEP * sel;
      if (VDDPIX_CLAMP_EN) begin
        if (lvl < VDDPIX_MIN) lvl = VDDPIX_MIN;
        if (lvl > VDDPIX_MAX) lvl = VDDPIX_MAX;
      end
      f_vddpix_level = lvl;
    end
  endfunction

  always @(*) begin
    if (s_enable_global) s_vddpix_target = f_vddpix_level(REGVDDPIX_SEL_AVDD);
    else                 s_vddpix_target = 0.0;
  end

  // Delay that applies to the pending transition.
  //  - turning on              -> POR_VDDPIX_ASSERT  (regulator start-up)
  //  - turning off, pulled down -> POR_VDDPIX_ASSERT  (active discharge)
  //  - turning off, no pull-down -> POR_VDDPIX_RELEASE (slow passive decay)
  always @(*) begin
    if (s_enable_global)
      s_settle_delay = POR_VDDPIX_ASSERT;
    else if (REGVDDPIX_DISABLE_PULLDOWN_AVDD == 1'b0)
      s_settle_delay = POR_VDDPIX_ASSERT;
    else
      s_settle_delay = POR_VDDPIX_RELEASE;
  end

//------------------------------------------------------------------------------
// Main Code -- re-triggerable one-shot
//
// Any change of the requested level or of the applicable delay restarts the
// settling window. Unlike a plain `always` block with a blocking delay, nothing
// is dropped while a transition is in flight.
//------------------------------------------------------------------------------
  initial begin
    s_vddpix = 0.0;
  end

  always @(s_vddpix_target, s_settle_delay) -> e_retrigger;

  always begin : SETTLE_PROC
    fork
      begin : timer
        #(s_settle_delay);
        s_vddpix = s_vddpix_target;
        @(e_retrigger);         // settled; wait here for the next request
      end
      begin : abort
        @(e_retrigger);         // a new request cancels the pending transition
      end
    join_any
    disable fork;
  end

//------------------------------------------------------------------------------
// DIAGNOSTICS
//
// Without this, a single out-of-range supply silently pins VDDPIX at 0 V and
// there is nothing in the log to say why.
//------------------------------------------------------------------------------
`ifndef REG_VDDPIX_NO_DIAG
  string s_reason;
  string s_reason_prev = "";

  // Built at report time so the value printed is the settled one.
  function automatic string f_fail_reason ();
    string r;
    r = "";
    if (s_chk_avdd !== 1'b1)
      r = {r, $sformatf("      AVDD               = %0.4f V   (need %0.2f .. %0.2f)\n",
                        AVDD, AVDD_MIN, AVDD_MAX)};
    if (s_chk_avdd1v1 !== 1'b1)
      r = {r, $sformatf("      AVDD1V1            = %0.4f V   (need %0.2f .. %0.2f)\n",
                        AVDD1V1, AVDD1V1_MIN, AVDD1V1_MAX)};
    if (s_chk_avss !== 1'b1)
      r = {r, $sformatf("      AVSS               = %0.4f V   (need < %0.2f)\n",
                        AVSS, VSS_MAX)};
    if (s_chk_avss_ref !== 1'b1)
      r = {r, $sformatf("      AVSS_REF_REGVDDPIX = %0.4f V   (need < %0.2f)\n",
                        AVSS_REF_REGVDDPIX, VSS_MAX)};
    if (s_chk_ibias !== 1'b1)
      r = {r, $sformatf("      IBIAS_REGVDDPIX_5U = %0.4e A   (need %0.3e .. %0.3e)\n",
                        IBIAS_REGVDDPIX_5U, 5.0*IBIAS_1U_MIN, 5.0*IBIAS_1U_MAX)};
    if (s_chk_vref !== 1'b1)
      r = {r, $sformatf("      VREF_REG_VDDPIX_1V1= %0.4f V   (need %0.4f .. %0.4f)\n",
                        VREF_REG_VDDPIX_1V1, 1.1*VREF_1V0_MIN, 1.1*VREF_1V0_MAX)};
    f_fail_reason = r;
  endfunction

  always @(s_enable_req, s_enable_checks,
           s_chk_avdd, s_chk_avdd1v1, s_chk_avss, s_chk_avss_ref,
           s_chk_ibias, s_chk_vref) begin
    #0;   // let the continuous assignments settle before reading them back
    if (s_enable_checks === 1'b1) begin
      s_reason_prev = "";
    end
    else if (DIAG_ON && s_enable_req === 1'b1) begin
      s_reason = f_fail_reason();
      if (s_reason != "" && s_reason != s_reason_prev) begin
        s_reason_prev = s_reason;
        $display("[%0t] %m: VDDPIX HELD LOW -- REGVDDPIX_ENABLE/BG_ENABLE_OK are high but the analog checks fail:\n%s",
                 $time, s_reason);
      end
    end
  end

  // Flag a trim code that asks for a level outside the legal window.
  always @(s_vddpix_target) begin
    if (DIAG_ON && s_enable_global === 1'b1
        && (s_vddpix_target > VDDPIX_MAX || s_vddpix_target < VDDPIX_MIN))
      $display("[%0t] %m: WARNING VDDPIX target %0.3f V (SEL=%0d) is outside the legal window %0.2f .. %0.2f V",
               $time, s_vddpix_target, REGVDDPIX_SEL_AVDD, VDDPIX_MIN, VDDPIX_MAX);
  end
`endif

//------------------------------------------------------------------------------
// Unused inputs -- documented gaps, see doc/DEBUG_NOTES.md
//   POR_DVDD1V1_AVDD               : POR does not gate the output in this model
//   REGVDDPIX_ENABLE_PULLUP_AVDD   : pull-up to AVDD1V1 is not modelled
//   REGVDDPIX_SELDRIVE_AVDD        : drive strength has no behavioural effect
//------------------------------------------------------------------------------

endmodule
