// -------------------------------------------------------------------------------
//  tb_REG_VDDPIX_race -- reproduces the real failure.
//
//  Setup matches the production bench: ALL analog comes from the top testbench
//  and is valid from t=0, the digital _GO1 signals come from
//  stim_REG_VDDPIX_TOP. Every analog check is high at t=0 and s_enable_global
//  rises at 2 us -- and VDDPIX still never comes up.
//
//  Two identical DUTs are instantiated. They differ in ONE thing: what
//  REGVDDPIX_DISABLE_PULLDOWN_AVDD reads at the instant the model's always
//  block is first triggered at t=0.
//
//    dut_a : reads 0  -> the block takes the POR_VDDPIX_ASSERT  (10 us)  branch
//    dut_b : reads x  -> the block takes the POR_VDDPIX_RELEASE (355 us) branch
//
//  `x == 0` is x, which an `if` treats as false, so the model falls into the
//  355 us else-branch. 355 us is longer than all stimulus activity (the last
//  SEL change is at 19 us), so the always block is still inside that blocking
//  delay when the enable rises at 2 us and when every SEL code goes by. It
//  wakes at 355 us, assigns 0.0, re-arms -- and nothing ever changes again.
//
//  Which branch a given simulator takes is a race at t=0 between the model's
//  continuous assignments and the stimulus initial block. That is why this can
//  look simulator- or seed-dependent.
//
//  With the original model: dut_a = 0.870 V, dut_b = 0.000 V.
//  With the fixed model:    both  = 0.870 V.
// -------------------------------------------------------------------------------

`timescale 1ps/1ps

module tb_REG_VDDPIX_race;

  import elec_net_pkg::*;

  // ---- analog from the top testbench, valid from t=0 ----------------------
  real_net AVDD, AVDD1V1, AVSS, AVSS_REF, IBIAS_5U, VREF_1V1;
  real r_avdd = 2.5, r_avdd1v1 = 1.2, r_avss = 0.0;
  real r_avssref = 0.0, r_ibias = 5.0e-6, r_vref = 1.1;
  assign AVDD     = r_avdd;
  assign AVDD1V1  = r_avdd1v1;
  assign AVSS     = r_avss;
  assign AVSS_REF = r_avssref;
  assign IBIAS_5U = r_ibias;
  assign VREF_1V1 = r_vref;

  // ---- digital from the _GO1 stimulus -------------------------------------
  logic       REGVDDPIX_ENABLE_PULLUP_GO1, BG_ENABLE_OK_AVDD, VBG_REGVDDPIX_1V1;
  logic       REGVDDPIX_DISABLE_PULLDOWN_GO1, DVDD1V1, POR_DVDD1V1_AVDD;
  logic       REGVDDPIX_ENABLE_GO1, REGVDDPIX_SEL_ATEST_GO1;
  logic [3:0] REGVDDPIX_SEL_GO1, REGVDDPIX_SELDRIVE_GO1;

  // the stimulus' own analog outputs are unused here -- the top bench drives analog
  logic  stim_avss_ref, stim_avss, stim_ibias, stim_avdd, stim_avsspix;
  real   stim_avdd1v1;
  logic  VDDPIX_bit = 1'b0, REGVDDPIX_ATEST = 1'b0;

  stim_REG_VDDPIX_TOP stim (
    .REGVDDPIX_ENABLE_PULLUP_GO1   (REGVDDPIX_ENABLE_PULLUP_GO1),
    .VDDPIX                        (VDDPIX_bit),
    .BG_ENABLE_OK_AVDD             (BG_ENABLE_OK_AVDD),
    .VBG_REGVDDPIX_1V1             (VBG_REGVDDPIX_1V1),
    .REGVDDPIX_DISABLE_PULLDOWN_GO1(REGVDDPIX_DISABLE_PULLDOWN_GO1),
    .DVDD1V1                       (DVDD1V1),
    .REGVDDPIX_SEL_GO1             (REGVDDPIX_SEL_GO1),
    .POR_DVDD1V1_AVDD              (POR_DVDD1V1_AVDD),
    .REGVDDPIX_ATEST               (REGVDDPIX_ATEST),
    .REGVDDPIX_ENABLE_GO1          (REGVDDPIX_ENABLE_GO1),
    .AVSS_REF_REGVDDPIX            (stim_avss_ref),
    .AVSS                          (stim_avss),
    .REGVDDPIX_SEL_ATEST_GO1       (REGVDDPIX_SEL_ATEST_GO1),
    .REGVDDPIX_SELDRIVE_GO1        (REGVDDPIX_SELDRIVE_GO1),
    .IBIAS_REGVDDPIX_5U            (stim_ibias),
    .AVDD                          (stim_avdd),
    .AVSSPIX                       (stim_avsspix),
    .AVDD1V1                       (stim_avdd1v1)
  );

  // dut_b's pull-down control goes through a wrapper level shifter whose output
  // is x until its own supply is valid -- the only difference between the DUTs.
  logic ls_valid = 1'b0;
  wire  dpd_b = ls_valid ? REGVDDPIX_DISABLE_PULLDOWN_GO1 : 1'bx;
  initial begin #500; ls_valid = 1'b1; end

  real_net VDDPIX_a, VDDPIX_b;

  REG_VDDPIX_CORE #(.POR_VDDPIX_ASSERT(10us), .POR_VDDPIX_RELEASE(355us)) dut_a (
    .VDDPIX(VDDPIX_a), .AVDD(AVDD), .AVDD1V1(AVDD1V1), .AVSS(AVSS),
    .AVSS_REF_REGVDDPIX(AVSS_REF), .BG_ENABLE_OK_AVDD(BG_ENABLE_OK_AVDD),
    .IBIAS_REGVDDPIX_5U(IBIAS_5U), .POR_DVDD1V1_AVDD(POR_DVDD1V1_AVDD),
    .REGVDDPIX_DISABLE_PULLDOWN_AVDD(REGVDDPIX_DISABLE_PULLDOWN_GO1),
    .REGVDDPIX_ENABLE_AVDD(REGVDDPIX_ENABLE_GO1),
    .REGVDDPIX_ENABLE_PULLUP_AVDD(REGVDDPIX_ENABLE_PULLUP_GO1),
    .REGVDDPIX_SELDRIVE_AVDD(REGVDDPIX_SELDRIVE_GO1),
    .REGVDDPIX_SEL_AVDD(REGVDDPIX_SEL_GO1), .VREF_REG_VDDPIX_1V1(VREF_1V1));

  REG_VDDPIX_CORE #(.POR_VDDPIX_ASSERT(10us), .POR_VDDPIX_RELEASE(355us)) dut_b (
    .VDDPIX(VDDPIX_b), .AVDD(AVDD), .AVDD1V1(AVDD1V1), .AVSS(AVSS),
    .AVSS_REF_REGVDDPIX(AVSS_REF), .BG_ENABLE_OK_AVDD(BG_ENABLE_OK_AVDD),
    .IBIAS_REGVDDPIX_5U(IBIAS_5U), .POR_DVDD1V1_AVDD(POR_DVDD1V1_AVDD),
    .REGVDDPIX_DISABLE_PULLDOWN_AVDD(dpd_b),
    .REGVDDPIX_ENABLE_AVDD(REGVDDPIX_ENABLE_GO1),
    .REGVDDPIX_ENABLE_PULLUP_AVDD(REGVDDPIX_ENABLE_PULLUP_GO1),
    .REGVDDPIX_SELDRIVE_AVDD(REGVDDPIX_SELDRIVE_GO1),
    .REGVDDPIX_SEL_AVDD(REGVDDPIX_SEL_GO1), .VREF_REG_VDDPIX_1V1(VREF_1V1));

  initial begin
    #1;
    $display("");
    $display("  analog checks at t=0:  en_pwr=%b  en_ref=%b  en_chk=%b  en_glob=%b",
             dut_a.s_enable_power, dut_a.s_enable_ref,
             dut_a.s_enable_checks, dut_a.s_enable_global);
  end

  initial begin
    @(posedge dut_a.s_enable_global)
      $display("  s_enable_global 0 -> 1 at %0t (= 2 us)", $time);
  end

  final begin
    $display("");
    $display("  ================================================================");
    $display("   dut_a  DISABLE_PULLDOWN reads 0 at t=0 -> VDDPIX = %0.3f V", VDDPIX_a);
    $display("   dut_b  DISABLE_PULLDOWN reads x at t=0 -> VDDPIX = %0.3f V", VDDPIX_b);
    $display("  ----------------------------------------------------------------");
    if (VDDPIX_a > 0.869 && VDDPIX_a < 0.871 && VDDPIX_b > 0.869 && VDDPIX_b < 0.871)
      $display("   PASS  both orderings settle at 0.870 V -- no t=0 race");
    else begin
      $display("***FAIL  the two orderings disagree -- the model has a t=0 race.");
      $display("         dut_b was parked inside #(POR_VDDPIX_RELEASE) from t=0,");
      $display("         so the enable at 2 us and every SEL change were dropped.");
    end
    $display("  ================================================================");
  end

endmodule
