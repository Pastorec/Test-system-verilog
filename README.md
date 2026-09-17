# REG_VDDPIX_CORE - model and regression

Behavioural model of the EWOKMZ pixel-supply regulator, plus a self-checking
testbench.

## The problem this started from

`VDDPIX` stayed at 0 V for the whole simulation even though every analog check
was high at t=0 and `s_enable_global` rose at 2 us.

The cause is in the **model**. Its output is driven from one `always` block with
a blocking delay inside it. At t=0, while the regulator is still off, that block
takes the `#(POR_VDDPIX_RELEASE)` = **355 us** branch - which it does whenever
`REGVDDPIX_DISABLE_PULLDOWN_AVDD` reads anything but a hard `0` at that instant,
`x` included. Verilog does not queue events for a block that is executing, so
the enable at 2 us and all 16 SEL changes are dropped. It wakes at 355 us, long
after the last stimulus change at 19 us, and nothing ever triggers it again.

Which branch gets taken is a **race at time 0** between the model's continuous
assignments and the stimulus `initial` block, which is why it can look
simulator-dependent:

```
sim/run_iverilog.sh --race-orig     # same bench, same model, twice over:
   dut_a  DISABLE_PULLDOWN reads 0 at t=0 -> VDDPIX = 0.870 V
   dut_b  DISABLE_PULLDOWN reads x at t=0 -> VDDPIX = 0.000 V
```

Full analysis, with the other issues found along the way:
**[doc/DEBUG_NOTES.md](doc/DEBUG_NOTES.md)**.

## Layout

```
rtl/REG_VDDPIX_CORE.sv        the model (fixed)
rtl/elec_net_pkg.sv           stand-in for your site package - drop it if you
                              already have elec_net_pkg on the compile path
tb/stim_REG_VDDPIX_TOP.sv     the stimulus (fixed, self-checking)
tb/tb_REG_VDDPIX_CORE.sv      top-level netlist; stands in for REG_VDDPIX_TOP,
                              which was not supplied
tb/tb_REG_VDDPIX_race.sv      reproduces the real failure: analog from the top
                              bench, digital from the _GO1 stimulus, the model
                              instantiated twice across the t=0 race
orig/                         the original sources, verbatim, kept only so the
                              failure can be reproduced
sim/run_iverilog.sh           regression runner
doc/DEBUG_NOTES.md            what was wrong and why
```

## Running it

```bash
sim/run_iverilog.sh --race-orig  # the real failure: 0.870 V vs 0.000 V on a t=0 race
sim/run_iverilog.sh --race       # same bench, fixed model: both settle at 0.870 V

sim/run_iverilog.sh              # fixed model + fixed stimulus  -> 27 passed, 0 failed
sim/run_iverilog.sh --orig-core  # original model + fixed stim   -> 23 passed, 4 failed
sim/run_iverilog.sh --orig       # original + original stimulus
sim/run_iverilog.sh --dump       # also write a VCD
```

`--race-orig` is the one that reproduces your waveform. `--orig-core` shows the
same root cause from another angle: even a perfect stimulus cannot work around
a block that drops events while it is inside a blocking delay.

On Xcelium / VCS / Questa, compile `rtl/` and `tb/` directly - no substitution
needed. The runner only exists because Icarus has no user-defined nettypes; see
the tool note at the end of `doc/DEBUG_NOTES.md`.

## What changed in the model

- The settling process is now a **re-triggerable one-shot**, which is the actual
  fix. The original was a plain `always` block with a blocking `#delay`: it
  silently dropped every event arriving during the delay, latched its enable
  decision before waiting, and could park itself for 355 us at t=0.
- The analog checks are **broken out per signal**, and the model now prints
  which supply or reference is out of range instead of holding the output low in
  silence.
- The broken commented-out clamp (its upper bound was inverted) is replaced by a
  correct parameterised clamp, **off by default** so the transfer function is
  unchanged.

## Open question for the analog owner

`VDDPIX = 0.87 + 0.08 * SEL` reaches **2.07 V** at `SEL = 4'hF`, well outside the
0.8 .. 1.3 V window implied by the model's own commented-out clamp. The
coefficients or the legal SEL range need confirming against the spec. This has
been left as-is and flagged with a runtime warning rather than guessed at - set
`VDDPIX_CLAMP_EN = 1` to clamp once the intent is settled.
