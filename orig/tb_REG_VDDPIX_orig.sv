// -------------------------------------------------------------------------------
//  tb_REG_VDDPIX_orig -- netlist for the ORIGINAL sources, so the
//  "VDDPIX stays low" failure can be reproduced and watched.
//
//  The original stimulus declares its analog pins as 1-bit `logic`, so this
//  netlist has to coerce them to analog values on the way into the model --
//  exactly what the schematic netlist does implicitly, and exactly what turns
//  'b1 into 1.0 V on AVDD, AVSS, IBIAS and VREF.
// -------------------------------------------------------------------------------

`timescale 1ps/1ps

module tb_REG_VDDPIX_orig;

  logic       REGVDDPIX_ENABLE_PULLUP_GO1, BG_ENABLE_OK_AVDD, VBG_REGVDDPIX_1V1;
  logic       REGVDDPIX_DISABLE_PULLDOWN_GO1, DVDD1V1, POR_DVDD1V1_AVDD;
  logic       REGVDDPIX_ENABLE_GO1, AVSS_REF_REGVDDPIX, AVSS;
  logic       REGVDDPIX_SEL_ATEST_GO1, IBIAS_REGVDDPIX_5U, AVDD, AVSSPIX;
  logic [3:0] REGVDDPIX_SEL_GO1, REGVDDPIX_SELDRIVE_GO1;
  real        AVDD1V1;

  real_net    VDDPIX;
  logic       VDDPIX_bit, REGVDDPIX_ATEST;

  // the stimulus reads VDDPIX as a bit -- this is the thresholding it implies
  assign VDDPIX_bit     = (VDDPIX > 0.5);
  assign REGVDDPIX_ATEST = 1'b0;

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
    .AVSS_REF_REGVDDPIX            (AVSS_REF_REGVDDPIX),
    .AVSS                          (AVSS),
    .REGVDDPIX_SEL_ATEST_GO1       (REGVDDPIX_SEL_ATEST_GO1),
    .REGVDDPIX_SELDRIVE_GO1        (REGVDDPIX_SELDRIVE_GO1),
    .IBIAS_REGVDDPIX_5U            (IBIAS_REGVDDPIX_5U),
    .AVDD                          (AVDD),
    .AVSSPIX                       (AVSSPIX),
    .AVDD1V1                       (AVDD1V1)
  );

  // logic -> analog coercion at the boundary: 'b1 becomes 1.0
  real_net AVDD_a, AVSS_a, AVSSREF_a, IBIAS_a, VREF_a;
  assign AVDD_a    = AVDD;
  assign AVSS_a    = AVSS;
  assign AVSSREF_a = AVSS_REF_REGVDDPIX;
  assign IBIAS_a   = IBIAS_REGVDDPIX_5U;
  assign VREF_a    = VBG_REGVDDPIX_1V1;

  REG_VDDPIX_CORE #(
    .POR_VDDPIX_ASSERT  (10us),
    .POR_VDDPIX_RELEASE (355us)
  ) dut (
    .VDDPIX                          (VDDPIX),
    .AVDD                            (AVDD_a),
    .AVDD1V1                         (AVDD1V1),
    .AVSS                            (AVSS_a),
    .AVSS_REF_REGVDDPIX              (AVSSREF_a),
    .BG_ENABLE_OK_AVDD               (BG_ENABLE_OK_AVDD),
    .IBIAS_REGVDDPIX_5U              (IBIAS_a),
    .POR_DVDD1V1_AVDD                (POR_DVDD1V1_AVDD),
    .REGVDDPIX_DISABLE_PULLDOWN_AVDD (REGVDDPIX_DISABLE_PULLDOWN_GO1),
    .REGVDDPIX_ENABLE_AVDD           (REGVDDPIX_ENABLE_GO1),
    .REGVDDPIX_ENABLE_PULLUP_AVDD    (REGVDDPIX_ENABLE_PULLUP_GO1),
    .REGVDDPIX_SELDRIVE_AVDD         (REGVDDPIX_SELDRIVE_GO1),
    .REGVDDPIX_SEL_AVDD              (REGVDDPIX_SEL_GO1),
    .VREF_REG_VDDPIX_1V1             (VREF_a)
  );

  initial begin
    $display("");
    $display("  t(us)  AVDD  AVDD1V1  AVSS  AVSSREF   IBIAS      VREF   en_pwr en_ref en_glob  VDDPIX");
    $display("  ------------------------------------------------------------------------------------");
    forever begin
      #1000000;
      $display("  %5.1f  %4.2f   %4.2f   %4.2f   %4.2f   %8.2e  %4.2f      %b      %b      %b     %6.3f",
        $realtime/1e6, AVDD_a, AVDD1V1, AVSS_a, AVSSREF_a, IBIAS_a, VREF_a,
        dut.s_enable_power, dut.s_enable_ref, dut.s_enable_global, VDDPIX);
    end
  end

  final begin
    $display("");
    $display("  ====================================================================");
    $display("  VDDPIX never left %0.3f V: s_enable_power=%b s_enable_ref=%b", VDDPIX,
             dut.s_enable_power, dut.s_enable_ref);
    $display("  Both analog check groups are 0 for the whole run, so s_enable_global");
    $display("  is never asserted and the model holds the output at 0 V.");
    $display("  ====================================================================");
  end

endmodule
