// -------------------------------------------------------------------------------
//  elec_net_pkg -- REFERENCE / STAND-IN VERSION
//
//  Your environment already provides elec_net_pkg. This copy exists only so the
//  repository elaborates stand-alone. If your site package is on the compile
//  path, drop this file from the file list.
//
//  real_net is a user-defined nettype: an analog net carrying a voltage (V) or
//  a current (A) as a SystemVerilog `real`. Declaring it as a nettype (rather
//  than `real`) is what allows several drivers to be resolved onto one net.
// -------------------------------------------------------------------------------

`timescale 1ps / 1ps

package elec_net_pkg;

  // Resolution: last non-zero driver wins. A real site package will implement
  // a proper electrical resolution here; this is only a placeholder so that
  // single-driver nets behave correctly.
  function automatic real real_net_res(input real drivers[]);
    real r;
    r = 0.0;
    foreach (drivers[i]) begin
      if (drivers[i] != 0.0) r = drivers[i];
    end
    return r;
  endfunction

  nettype real real_net with real_net_res;

endpackage : elec_net_pkg
