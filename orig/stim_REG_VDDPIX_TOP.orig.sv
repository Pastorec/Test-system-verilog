//systemVerilog HDL for "MZNOVA_design", "stim_REG_VDDPIX_TOP" "systemVerilog"
//
// ORIGINAL, UNMODIFIED -- kept only to reproduce the failure.
// The maintained version is tb/stim_REG_VDDPIX_TOP.sv.

`timescale 1ps/1ps

module stim_REG_VDDPIX_TOP ( REGVDDPIX_ENABLE_PULLUP_GO1,
 VDDPIX, BG_ENABLE_OK_AVDD, VBG_REGVDDPIX_1V1, REGVDDPIX_DISABLE_PULLDOWN_GO1,
 DVDD1V1, REGVDDPIX_SEL_GO1, POR_DVDD1V1_AVDD, REGVDDPIX_ATEST,
 REGVDDPIX_ENABLE_GO1, AVSS_REF_REGVDDPIX, AVSS, REGVDDPIX_SEL_ATEST_GO1,
 REGVDDPIX_SELDRIVE_GO1, IBIAS_REGVDDPIX_5U, AVDD, AVSSPIX,
 AVDD1V1 );

   //import st_img_ams_nonreg_pkg::*;
   output logic    REGVDDPIX_ENABLE_PULLUP_GO1;
   input logic    VDDPIX;
   output logic    BG_ENABLE_OK_AVDD;
   output logic    VBG_REGVDDPIX_1V1;
   output logic    REGVDDPIX_DISABLE_PULLDOWN_GO1;
   output logic    DVDD1V1;
   output logic    [3:0] REGVDDPIX_SEL_GO1;
   output logic    POR_DVDD1V1_AVDD;
   input logic    REGVDDPIX_ATEST;
   output logic    REGVDDPIX_ENABLE_GO1;
   output logic    AVSS_REF_REGVDDPIX;
   output logic    AVSS;
   output logic    REGVDDPIX_SEL_ATEST_GO1;
   output logic     [3:0] REGVDDPIX_SELDRIVE_GO1;
   output logic    IBIAS_REGVDDPIX_5U;
   output logic    AVDD;
   output logic    AVSSPIX;
   output real     AVDD1V1;

parameter real vana = 2.5;
parameter real vdig = 1.2;

logic check_VDDPIX;
logic check_REGVDDPIX_ATEST;

initial begin // All outputs set to 0
$display("   All outputs set to 0");
REGVDDPIX_ENABLE_PULLUP_GO1 = 'b0;
BG_ENABLE_OK_AVDD = 'b0;
VBG_REGVDDPIX_1V1 = 'b0;
REGVDDPIX_DISABLE_PULLDOWN_GO1 = 'b0;
DVDD1V1 = 'b0;
REGVDDPIX_SEL_GO1 = 4'b0000;
POR_DVDD1V1_AVDD = 'b0;
REGVDDPIX_ENABLE_GO1 = 'b0;
AVSS_REF_REGVDDPIX = 'b0;
AVSS = 'b0;
REGVDDPIX_SEL_ATEST_GO1 = 'b0;
REGVDDPIX_SELDRIVE_GO1 = 0.0;
IBIAS_REGVDDPIX_5U = 'b0;
AVDD = 'b0;
AVSSPIX = 'b0;
AVDD1V1 = 0.0;

#1us; // At time = 1us
$display("   no_supplies");

REGVDDPIX_SELDRIVE_GO1 = vdig;
AVDD1V1 = vana;

#1us; // At time = 2us
$display("   with_supplies");

REGVDDPIX_ENABLE_PULLUP_GO1 = 'b1;
BG_ENABLE_OK_AVDD = 'b1;
VBG_REGVDDPIX_1V1 = 'b1;
REGVDDPIX_DISABLE_PULLDOWN_GO1 = 'b1;
DVDD1V1 = 'b1;
POR_DVDD1V1_AVDD = 'b1;
REGVDDPIX_ENABLE_GO1 = 'b1;
AVSS_REF_REGVDDPIX = 'b1;
AVSS = 'b1;
REGVDDPIX_SEL_ATEST_GO1 = 'b1;
IBIAS_REGVDDPIX_5U = 'b1;
AVDD = 'b1;
AVSSPIX = 'b1;

#1us; // At time = 3us
$display("   enable");

for (int i = 0; i < 16; i++) begin
  REGVDDPIX_SEL_GO1 = i[3:0];
  #1us;
  $display("    REGVDDPIX_SEL_GO1=4'b%04b", i[3:0]);
end

REGVDDPIX_SEL_GO1 = 4'b0000;
#1us; // At time = 20us
$display("    REGVDDPIX_SEL_GO1=4'b0000");

#400us;
$finish();
end

endmodule
