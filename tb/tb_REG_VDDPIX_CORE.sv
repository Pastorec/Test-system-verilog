// -------------------------------------------------------------------------------
//  tb_REG_VDDPIX_CORE -- top-level netlist for the REG_VDDPIX_CORE regression.
//
//  Your schematic testbench wires stim_REG_VDDPIX_TOP to REG_VDDPIX_TOP, which
//  was not supplied. This netlist connects the stimulus straight to
//  REG_VDDPIX_CORE, which means it stands in for the wrapper:
//
//    *_GO1  ->  *_AVDD              the wrapper's level shifters
//    VBG_REGVDDPIX_1V1 -> VREF_REG_VDDPIX_1V1
//
//  Note the port-name difference: the stimulus drives VBG_REGVDDPIX_1V1 while
//  the core expects VREF_REG_VDDPIX_1V1. In the real hierarchy the wrapper
//  buffers VBG into VREF; here they are tied together.
// -------------------------------------------------------------------------------

`timescale 1ps/1ps

module tb_REG_VDDPIX_CORE;

  import elec_net_pkg::*;

  // digital
  logic        REGVDDPIX_ENABLE_PULLUP_GO1;
  logic        BG_ENABLE_OK_AVDD;
  logic        REGVDDPIX_DISABLE_PULLDOWN_GO1;
  logic [3:0]  REGVDDPIX_SEL_GO1;
  logic        POR_DVDD1V1_AVDD;
  logic        REGVDDPIX_ENABLE_GO1;
  logic        REGVDDPIX_SEL_ATEST_GO1;
  logic [3:0]  REGVDDPIX_SELDRIVE_GO1;

  // analog
  real_net     VDDPIX;
  real_net     REGVDDPIX_ATEST;
  real_net     VBG_REGVDDPIX_1V1;
  real_net     DVDD1V1;
  real_net     AVSS_REF_REGVDDPIX;
  real_net     AVSS;
  real_net     IBIAS_REGVDDPIX_5U;
  real_net     AVDD;
  real_net     AVSSPIX;
  real_net     AVDD1V1;

  // REG_VDDPIX_CORE has no ATEST output; tie the stimulus input off.
  real r_atest = 0.0;
  assign REGVDDPIX_ATEST = r_atest;

  stim_REG_VDDPIX_TOP stim (
    .REGVDDPIX_ENABLE_PULLUP_GO1    (REGVDDPIX_ENABLE_PULLUP_GO1),
    .VDDPIX                         (VDDPIX),
    .BG_ENABLE_OK_AVDD              (BG_ENABLE_OK_AVDD),
    .VBG_REGVDDPIX_1V1              (VBG_REGVDDPIX_1V1),
    .REGVDDPIX_DISABLE_PULLDOWN_GO1 (REGVDDPIX_DISABLE_PULLDOWN_GO1),
    .DVDD1V1                        (DVDD1V1),
    .REGVDDPIX_SEL_GO1              (REGVDDPIX_SEL_GO1),
    .POR_DVDD1V1_AVDD               (POR_DVDD1V1_AVDD),
    .REGVDDPIX_ATEST                (REGVDDPIX_ATEST),
    .REGVDDPIX_ENABLE_GO1           (REGVDDPIX_ENABLE_GO1),
    .AVSS_REF_REGVDDPIX             (AVSS_REF_REGVDDPIX),
    .AVSS                           (AVSS),
    .REGVDDPIX_SEL_ATEST_GO1        (REGVDDPIX_SEL_ATEST_GO1),
    .REGVDDPIX_SELDRIVE_GO1         (REGVDDPIX_SELDRIVE_GO1),
    .IBIAS_REGVDDPIX_5U             (IBIAS_REGVDDPIX_5U),
    .AVDD                           (AVDD),
    .AVSSPIX                        (AVSSPIX),
    .AVDD1V1                        (AVDD1V1)
  );

  // The time parameters are passed explicitly rather than left to default.
  // Icarus Verilog 12 evaluates a time literal used as an ANSI parameter
  // DEFAULT to 0 (so every delay collapses), but honours the same literal when
  // it arrives as an override. Commercial simulators are fine either way, so
  // passing them keeps one netlist working everywhere. See doc/DEBUG_NOTES.md.
  REG_VDDPIX_CORE #(
    .POR_VDDPIX_ASSERT  (10us),
    .POR_VDDPIX_RELEASE (355us)
  ) dut (
    .VDDPIX                          (VDDPIX),
    .AVDD                            (AVDD),
    .AVDD1V1                         (AVDD1V1),
    .AVSS                            (AVSS),
    .AVSS_REF_REGVDDPIX              (AVSS_REF_REGVDDPIX),
    .BG_ENABLE_OK_AVDD               (BG_ENABLE_OK_AVDD),
    .IBIAS_REGVDDPIX_5U              (IBIAS_REGVDDPIX_5U),
    .POR_DVDD1V1_AVDD                (POR_DVDD1V1_AVDD),
    .REGVDDPIX_DISABLE_PULLDOWN_AVDD (REGVDDPIX_DISABLE_PULLDOWN_GO1),
    .REGVDDPIX_ENABLE_AVDD           (REGVDDPIX_ENABLE_GO1),
    .REGVDDPIX_ENABLE_PULLUP_AVDD    (REGVDDPIX_ENABLE_PULLUP_GO1),
    .REGVDDPIX_SELDRIVE_AVDD         (REGVDDPIX_SELDRIVE_GO1),
    .REGVDDPIX_SEL_AVDD              (REGVDDPIX_SEL_GO1),
    .VREF_REG_VDDPIX_1V1             (VBG_REGVDDPIX_1V1)
  );

  initial begin
    if ($test$plusargs("dump")) begin
      $dumpfile("tb_REG_VDDPIX_CORE.vcd");
      $dumpvars(0, tb_REG_VDDPIX_CORE);
    end
  end

endmodule
