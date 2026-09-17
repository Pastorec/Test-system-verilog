# Why VDDPIX stayed low

## Short answer

`REG_VDDPIX_CORE` drives its output from a single `always` block that contains a
**blocking delay**:

```systemverilog
always @(s_enable_global, REGVDDPIX_SEL_AVDD, REGVDDPIX_DISABLE_PULLDOWN_AVDD)
  begin
    if (s_enable_global) begin
      #(POR_VDDPIX_ASSERT);
      ...
    else begin
      if (REGVDDPIX_DISABLE_PULLDOWN_AVDD == 0) #(POR_VDDPIX_ASSERT);   //  10 us
      else                                      #(POR_VDDPIX_RELEASE);  // 355 us
      s_vddpix = 0.0;
    end
```

At t=0 the block is triggered while the regulator is still off. If
`REGVDDPIX_DISABLE_PULLDOWN_AVDD` reads anything other than a hard `0` at that
instant - `x` is the usual case, since `x == 0` evaluates to `x` and an `if`
treats that as false - it takes the **355 us** branch.

Verilog does not queue events for an `always` block while that block is
executing. So for the next 355 us the process is deaf:

| time    | event                                | seen? |
|---------|--------------------------------------|-------|
| 2 us    | `s_enable_global` 0 -> 1             | lost  |
| 2 us    | `DISABLE_PULLDOWN` 0 -> 1            | lost  |
| 4-19 us | all 16 `REGVDDPIX_SEL` changes       | lost  |
| 355 us  | wakes up, assigns `s_vddpix = 0.0`   | -     |

It re-arms at 355 us, but the last stimulus change was at **19 us**. Nothing
ever triggers it again, so VDDPIX sits at 0 V for the whole run - with every
analog check high and `s_enable_global` high since 2 us.

That is exactly the waveform: all checks high, all `s_enable_*` high, output
flat at zero.

### It is a race, which is why it looks non-deterministic

Whether the block sees `DISABLE_PULLDOWN` as `0` or as `x` at t=0 is a race
between the model's continuous assignments and the stimulus `initial` block,
both of which run at time 0. Different simulators - and sometimes the same
simulator with a different compile - resolve it differently.

`tb/tb_REG_VDDPIX_race.sv` instantiates the model twice against one bench,
differing only in that one signal's value at t=0:

```
sim/run_iverilog.sh --race-orig      # the original model
```

```
  analog checks at t=0:  en_pwr=1  en_ref=1  en_chk=1  en_glob=0
  s_enable_global 0 -> 1 at 2000000 (= 2 us)

   dut_a  DISABLE_PULLDOWN reads 0 at t=0 -> VDDPIX = 0.870 V
   dut_b  DISABLE_PULLDOWN reads x at t=0 -> VDDPIX = 0.000 V
***FAIL  the two orderings disagree -- the model has a t=0 race.
```

Same stimulus, same checks, same enable - 0.870 V or 0.000 V depending purely on
a time-0 ordering. After the fix:

```
sim/run_iverilog.sh --race           # the fixed model
```

```
   dut_a  DISABLE_PULLDOWN reads 0 at t=0 -> VDDPIX = 0.870 V
   dut_b  DISABLE_PULLDOWN reads x at t=0 -> VDDPIX = 0.870 V
   PASS  both orderings settle at 0.870 V -- no t=0 race
```

### Quick confirmation on your side

Put a `$display` at the top of that `always` block printing `$time`,
`s_enable_global` and `REGVDDPIX_DISABLE_PULLDOWN_AVDD`. If you see a single
entry at t=0 followed by nothing until 355 us, this is it.

The fix is [Bug 1](#bug-1---the-models-timing-process-drops-events) below.

---

## Bug 1 - the model's timing process drops events  (root cause)

This is the cause of the failure above. It is also independent of the
stimulus - it survives any amount of fixing on the testbench side.

```systemverilog
always @(s_enable_global, REGVDDPIX_SEL_AVDD, REGVDDPIX_DISABLE_PULLDOWN_AVDD)
  begin
    if (s_enable_global) begin
      #(POR_VDDPIX_ASSERT);              // <-- blocking delay
      s_vddpix = 0.87 + 0.08 * REGVDDPIX_SEL_AVDD;
    end
    ...
```

Verilog does **not** queue events for an `always` block while that block is
executing. Anything that changes during the `#(POR_VDDPIX_ASSERT)` window is
lost outright. Two distinct symptoms follow:

**1a - dropped transitions.** With `POR_VDDPIX_ASSERT` = 10 us and the original
1 us SEL step, 9 of every 10 SEL changes were discarded. The enable edge itself
is discarded whenever it lands inside a window opened by an earlier event - and
one always opens at t=0, when `s_enable_global` resolves from `x` to `0`.

**1b - the decision is latched, never re-checked.** The block tests
`s_enable_global`, *then* waits, then assigns unconditionally. If the enable is
withdrawn during the wait, the output still goes high.

Run the fixed stimulus against the original model to see both:

```
sim/run_iverilog.sh --orig-core
```

```
***FAIL  [15000000] VDDPIX after enable, SEL=4'b0000                     exp= 0.8700 got= 0.0000
***FAIL  [35000000] VDDPIX with REGVDDPIX_SEL_GO1=4'b0000                exp= 0.8700 got= 0.0000
***FAIL  [367000000] VDDPIX after disable with pull-down active           exp= 0.0000 got= 0.8700
***FAIL  [763000000] VDDPIX with AVDD below AVDD_MIN                      exp= 0.0000 got= 0.8700
 RESULT: 23 passed, 4 failed
```

The last one is 1b: the enable rises and AVDD goes out of spec in the same time
step, the block commits to the turn-on during the delta where the enable is
briefly valid, and 10 us later it drives 0.87 V even though the regulator is not
enabled any more.

### Fix

A re-triggerable one-shot. Any change to the requested level or to the
applicable delay cancels the pending transition and restarts it:

```systemverilog
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
```

`s_vddpix_target` and `s_settle_delay` are plain combinational functions of the
inputs, so the decision is re-evaluated continuously instead of being latched.

---

## Bug 2 - latent: the stimulus' analog outputs are 1-bit `logic`

**Not the cause of this failure** - in the production bench all analog comes
from the top testbench and is correct, which is why every check reads high at
t=0. This is a trap waiting for whoever wires that stimulus up differently.

`stim_REG_VDDPIX_TOP` declares its analog pins as `logic` and powers up with
`'b1`:

```systemverilog
output logic AVDD;              // and AVSS, AVSS_REF_REGVDDPIX,
output logic IBIAS_REGVDDPIX_5U;// VBG_REGVDDPIX_1V1, AVSSPIX, DVDD1V1
...
AVSS = 'b1;                     // lifts the ground to 1 V
IBIAS_REGVDDPIX_5U = 'b1;       // 1.0 A on a 5 uA bias
```

On an analog net `'b1` is **1.0**. If those outputs ever reach the model, every
range check fails at once:

| Pin                  | Spec                | `'b1` gives | |
|----------------------|---------------------|-------------|--------|
| `AVDD`               | 2.4 .. 3.7 V        | 1.0 V       | fail   |
| `AVSS`               | < 0.1 V             | 1.0 V       | fail   |
| `AVSS_REF_REGVDDPIX` | < 0.1 V             | 1.0 V       | fail   |
| `IBIAS_REGVDDPIX_5U` | 4.5 .. 5.5 uA       | 1.0 A       | fail   |
| `VREF_REG_VDDPIX_1V1`| 1.078 .. 1.122 V    | 1.0 V       | fail   |

Two more in the same module:

- `AVDD1V1 = vana` (2.5 V) on a 0.8 .. 1.3 V rail, and
  `REGVDDPIX_SELDRIVE_GO1 = vdig` puts a real on a 4-bit bus. The two constants
  are swapped: `vana` belongs on `AVDD`, `vdig` on `AVDD1V1` / `DVDD1V1`.
- `input logic VDDPIX` reads an analog output as a bit, so the commented-out
  `chk_bit(1'b1, VDDPIX, ...)` calls could never have worked. `chk_real()` in
  `tb/stim_REG_VDDPIX_TOP.sv` replaces them.

`tb/stim_REG_VDDPIX_TOP.sv` is a cleaned-up version with the same module name
and port list, so it drops into the same schematic. Use it or don't - it is not
what was breaking the run.

### Port name mismatch

The stimulus drives `VBG_REGVDDPIX_1V1`; the core expects
`VREF_REG_VDDPIX_1V1`. In the real hierarchy `REG_VDDPIX_TOP` buffers VBG into
VREF. `REG_VDDPIX_TOP` was not supplied, so the benches here tie the two
together and stand in for the wrapper.

---

## Bug 3 - the stimulus sampled faster than the model settles

The original stepped SEL every 1 us while `POR_VDDPIX_ASSERT` is 10 us, so every
code was sampled mid-transition. The fixed stimulus uses `T_STEP = 20 us`
(`> POR_VDDPIX_ASSERT`) and a `T_RELEASE = 360 us` tail for the
`POR_VDDPIX_RELEASE` = 355 us path.

Related: the original run was 420 us total, which is not long enough to observe
the 355 us pull-down-defeated decay after a late disable.

---

## Bug 4 - broken clamp, and a transfer function that leaves the legal window

The dead code in the original:

```systemverilog
/*  if (s_vddpix < 0.8) begin s_vddpix=0.8; end
    if (s_vddpix < 1.3) begin s_vddpix=1.3; end   */
```

The second test is inverted - as written it forces *everything* below 1.3 up to
1.3, which is not an upper clamp. It is replaced by a correct, parameterised
clamp (`VDDPIX_MIN` / `VDDPIX_MAX` / `VDDPIX_CLAMP_EN`).

`VDDPIX_CLAMP_EN` defaults to **0**, so the transfer function is unchanged until
you confirm the intent. This matters because:

```
VDDPIX = 0.87 + 0.08 * SEL    ->   SEL = 4'hF gives 2.07 V
```

2.07 V on a pixel supply whose own commented-out clamp says 0.8 .. 1.3 V is
almost certainly wrong. The model now warns instead of failing silently:

```
[135000000] tb_REG_VDDPIX_CORE.dut: WARNING VDDPIX target 1.350 V (SEL=6) is outside the legal window 0.80 .. 1.30 V
```

**Open question for the analog owner:** confirm `VDDPIX_BASE`, `VDDPIX_STEP` and
the legal SEL range against the spec. Either the step is smaller, the base is
lower, or SEL does not use all 16 codes. This has been left alone rather than
guessed at.

---

## Bug 5 - diagnostics

Nothing in the original said *why* the output was held low - that is the whole
reason this took debugging. The checks are now broken out per signal and the
model names the offender:

```
[751000000] tb_REG_VDDPIX_CORE.dut: VDDPIX HELD LOW -- REGVDDPIX_ENABLE/BG_ENABLE_OK are high but the analog checks fail:
      AVDD               = 1.0000 V   (need 2.40 .. 3.70)
```

Controlled by `DIAG_ON` (default 1), or compile with `REG_VDDPIX_NO_DIAG` to
remove the block entirely.

---

## Unused inputs - modelling gaps, left as they were

Three inputs are declared and never used. None of them is the cause of the
failure, and wiring them up would change behaviour, so they are flagged rather
than changed:

- **`POR_DVDD1V1_AVDD`** - the power-on reset does not gate the output. The
  parameters are called `POR_VDDPIX_ASSERT` / `POR_VDDPIX_RELEASE`, which
  suggests POR was meant to take part.
- **`REGVDDPIX_ENABLE_PULLUP_AVDD`** - the pull-up is not modelled. With the
  regulator disabled and the pull-up enabled, the real block presumably pulls
  VDDPIX towards AVDD1V1; the model drives 0 V.
- **`REGVDDPIX_SELDRIVE_AVDD`** - drive strength has no behavioural effect.

---

## A note on `POR_VDDPIX_ASSERT` / `POR_VDDPIX_RELEASE` naming

The long delay (355 us) is used when the pull-down is *defeated* and the short
one (10 us) when it is active. That is physically right - no pull-down means a
slow passive decay - but the names read backwards against that usage. Worth
renaming to something like `T_VDDPIX_DECAY_SLOW` / `T_VDDPIX_DECAY_FAST` if you
touch this again.

---

## Tool note: Icarus Verilog

The regression here runs under Icarus 12 as a convenience. Two limitations were
worked around, neither of which affects Xcelium / VCS / Questa:

1. **No user-defined nettypes.** Icarus cannot compile `nettype real real_net`.
   `sim/run_iverilog.sh` builds a throw-away copy with `real_net` rewritten to
   `real`. Faithful here because every analog net in this testbench has exactly
   one driver, so the resolution function is never exercised. Nothing in `rtl/`
   or `tb/` is modified.

2. **Time literals as ANSI parameter defaults evaluate to 0.** In Icarus,
   `#(parameter time T = 10us)` yields `T = 0`, silently collapsing every delay.
   The same literal works correctly when passed as an *override*, so
   `tb_REG_VDDPIX_CORE.sv` passes `POR_VDDPIX_ASSERT` and `POR_VDDPIX_RELEASE`
   explicitly. Harmless on commercial simulators.

   Confirmed with:

   ```systemverilog
   module d #(parameter time T = 10us)(input logic t);
     always @(t) begin #(T); $display("T=%0d at %0.1fus", T, $realtime/1e6); end
   endmodule
   // default          -> T=0        , fires immediately
   // #(.T(10us))      -> T=10000000 , fires at 10us
   // #(.T(10_000_000))-> T=10000000 , fires at 10us
   ```

   If you ever see every delay in a model collapse to zero under Icarus, this is
   why.
