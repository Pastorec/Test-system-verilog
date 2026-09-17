// -------------------------------------------------------------------------------
//  ORIGINAL, UNMODIFIED -- kept only to reproduce the failure.
//  Do not use in the design. The maintained version is rtl/REG_VDDPIX_CORE.sv.
// -------------------------------------------------------------------------------
//
//                             COPYRIGHT (c) 2014
//                  ST Microelectronics - All rights reserved
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
   parameter real VREF_1V0_MIN 	  = 1.0*0.98
  
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
  real s_vddpix;

  logic s_enable_global, s_enable_power, s_enable_ref, s_enable_checks;

  logic disable_analog_checks = 1'b0;

//------------------------------------------------------------------------------
// Output definition 
//------------------------------------------------------------------------------
  assign VDDPIX = s_vddpix;

//------------------------------------------------------------------------------
// CHECKS
//------------------------------------------------------------------------------
  assign s_enable_power = (AVSS_REF_REGVDDPIX < VSS_MAX && AVSS < VSS_MAX 
                        && AVDD1V1_MIN < AVDD1V1 && AVDD1V1 < AVDD1V1_MAX 
                        && AVDD_MIN < AVDD && AVDD < AVDD_MAX 
			)? 1'b1: 1'b0;

  assign s_enable_ref = (5.0*IBIAS_1U_MIN < IBIAS_REGVDDPIX_5U && IBIAS_REGVDDPIX_5U < 5.0*IBIAS_1U_MAX  
  			&& 1.1*VREF_1V0_MIN < VREF_REG_VDDPIX_1V1 && VREF_REG_VDDPIX_1V1 < 1.1*VREF_1V0_MAX
			)? 1'b1: 1'b0;

  assign s_enable_checks = (disable_analog_checks)? 1'b1: s_enable_power && s_enable_ref; 

  assign s_enable_global = (s_enable_checks && BG_ENABLE_OK_AVDD && REGVDDPIX_ENABLE_AVDD
			  	)? 1'b1: 1'b0;

//------------------------------------------------------------------------------
// Main Code
//------------------------------------------------------------------------------
  initial begin
    s_vddpix = 0.0;
  end

  always @(s_enable_global, REGVDDPIX_SEL_AVDD, REGVDDPIX_DISABLE_PULLDOWN_AVDD) 
    begin 
      if (s_enable_global) begin
	#(POR_VDDPIX_ASSERT);
        s_vddpix = 0.87 + 0.08 * REGVDDPIX_SEL_AVDD;
/*        if (s_vddpix < 0.8) begin
          s_vddpix=0.8;
        end
        if (s_vddpix < 1.3) begin
          s_vddpix=1.3;
        end*/
      end
      else begin
        if (REGVDDPIX_DISABLE_PULLDOWN_AVDD == 0) begin
	  #(POR_VDDPIX_ASSERT);
        end
        else begin        
	  #(POR_VDDPIX_RELEASE);
        end
        s_vddpix = 0.0;
      end
    end  

endmodule
