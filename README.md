# REG_VDDPIX_CORE - model and regression

Behavioural model of the EWOKMZ pixel-supply regulator, plus a self-checking
testbench.

## The problem this started from

`VDDPIX` stayed at 0 V for the whole simulation. The cause was in the
**stimulus**, not the model: every analog pin was declared as a 1-bit `logic`
and powered up with `'b1`, so the model saw AVDD = 1.0 V, both grounds = 1.0 V,
IBIAS = 1.0 A and VREF = 1.0 V. Every range check failed and the model correctly
held the output low.

Full analysis, with the other four bugs found along the way:
**[doc/DEBUG_NOTES.md](doc/DEBUG_NOTES.md)**.

## Layout

```
rtl/REG_VDDPIX_CORE.sv        the model (fixed)
rtl/elec_net_pkg.sv           stand-in for your site package - drop it if you
                              already have elec_net_pkg on the compile path
tb/stim_REG_VDDPIX_TOP.sv     the stimulus (fixed, self-checking)
tb/tb_REG_VDDPIX_CORE.sv      top-level netlist; stands in for REG_VDDPIX_TOP,
                              which was not supplied
orig/                         the original sources, verbatim, kept only so the
                              failure can be reproduced
sim/run_iverilog.sh           regression runner
doc/DEBUG_NOTES.md            what was wrong and why
```

## Running it

```bash
sim/run_iverilog.sh              # fixed model + fixed stimulus  -> 27 passed, 0 failed
sim/run_iverilog.sh --orig       # original + original           -> VDDPIX stuck at 0 V
sim/run_iverilog.sh --orig-core  # original model + fixed stim   -> 23 passed, 4 failed
sim/run_iverilog.sh --dump       # also write a VCD
```

`--orig-core` is the interesting one: it shows that fixing the stimulus alone is
not enough, because the model's `always` block drops events while it is inside a
blocking delay.

On Xcelium / VCS / Questa, compile `rtl/` and `tb/` directly - no substitution
needed. The runner only exists because Icarus has no user-defined nettypes; see
the tool note at the end of `doc/DEBUG_NOTES.md`.

## What changed in the model

- The settling process is now a **re-triggerable one-shot**. The original was a
  plain `always` block with a blocking `#delay`, which silently dropped every
  event arriving during the delay and latched its enable decision before
  waiting.
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
