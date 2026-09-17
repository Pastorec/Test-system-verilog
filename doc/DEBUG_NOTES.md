# Why VDDPIX stayed low

## Short answer

The stimulus drove every analog pin as a 1-bit `logic` and powered the block up
with `'b1`. On an analog net `'b1` is **1.0**, so the model saw AVDD = 1.0 V,
both grounds = 1.0 V, IBIAS = 1.0 A and VREF = 1.0 V. Every range check in
`REG_VDDPIX_CORE` failed, `s_enable_global` was never asserted, and the model
correctly held VDDPIX at 0 V for the whole run.

The model was doing its job. The testbench never powered the block up.

Reproduce it:

```
sim/run_iverilog.sh --orig
```

```
  t(us)  AVDD  AVDD1V1  AVSS  AVSSREF   IBIAS      VREF   en_pwr en_ref en_glob  VDDPIX
  ------------------------------------------------------------------------------------
    1.0  0.00   2.50   0.00   0.00   0.00e+00  0.00      0      0      0      0.000
    2.0  1.00   2.50   1.00   1.00   1.00e+00  1.00      0      0      0      0.000
    3.0  1.00   2.50   1.00   1.00   1.00e+00  1.00      0      0      0      0.000
   ...
  419.0  1.00   2.50   1.00   1.00   1.00e+00  1.00      0      0      0      0.000
```

`en_pwr` and `en_ref` are `0` on every single line.

---

## Bug 1 - analog pins declared and driven as bits (root cause)

`REG_VDDPIX_CORE` declares these as `real_net`, i.e. analog nets carrying volts
and amps:

```systemverilog
real_net AVSS, AVSS_REF_REGVDDPIX, AVDD, AVDD1V1;
real_net VREF_REG_VDDPIX_1V1, IBIAS_REGVDDPIX_5U;
```

The stimulus declared the same pins as `logic` and drove them with `'b1`:

| Pin                  | Spec in the model         | Original stimulus | Result |
|----------------------|---------------------------|-------------------|--------|
| `AVDD`               | 2.4 .. 3.7 V              | `'b1` -> 1.0 V    | FAIL   |
| `AVDD1V1`            | 0.8 .. 1.3 V              | `vana` = 2.5 V    | FAIL   |
| `AVSS`               | < 0.1 V                   | `'b1` -> 1.0 V    | FAIL   |
| `AVSS_REF_REGVDDPIX` | < 0.1 V                   | `'b1` -> 1.0 V    | FAIL   |
| `IBIAS_REGVDDPIX_5U` | 4.5 uA .. 5.5 uA          | `'b1` -> 1.0 A    | FAIL   |
| `VREF_REG_VDDPIX_1V1`| 1.078 .. 1.122 V          | `'b1` -> 1.0 V    | FAIL   |

Note the two grounds in particular: the "power up" step raised `AVSS` and
`AVSS_REF_REGVDDPIX` to `'b1`, i.e. it lifted the grounds to 1 V.

### Bug 1b - `vana` and `vdig` swapped

```systemverilog
REGVDDPIX_SELDRIVE_GO1 = vdig;   // 1.2 assigned to a 4-bit bus -> 4'b0001
AVDD1V1                = vana;   // 2.5 V on a 0.8 .. 1.3 V rail
```

`vana` (2.5) belongs on `AVDD`, `vdig` (1.2) on `AVDD1V1` / `DVDD1V1`.
`SELDRIVE` is a 4-bit control bus and should not receive a voltage at all.

### Bug 1c - `VDDPIX` read back as a bit

```systemverilog
input logic VDDPIX;
```

VDDPIX is an analog output. Reading it as `logic` throws the voltage away, which
is why the failure showed up only as "stays low" rather than as a number. The
commented-out `chk_bit(1'b1, VDDPIX, ...)` calls would have been meaningless
against an analog value even once the supplies were right - they are replaced by
`chk_real()` in the fixed stimulus.

### Bug 1d - port name mismatch

The stimulus drives `VBG_REGVDDPIX_1V1`; the core expects
`VREF_REG_VDDPIX_1V1`. In the real hierarchy `REG_VDDPIX_TOP` buffers VBG into
VREF. `REG_VDDPIX_TOP` was not supplied, so `tb/tb_REG_VDDPIX_CORE.sv` ties the
two together and stands in for the wrapper.

---

## Bug 2 - the model's timing process drops events

This one is independent of Bug 1 and survives fixing the stimulus.

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

**2a - dropped transitions.** With `POR_VDDPIX_ASSERT` = 10 us and the original
1 us SEL step, 9 of every 10 SEL changes were discarded. The enable edge itself
is discarded whenever it lands inside a window opened by an earlier event - and
one always opens at t=0, when `s_enable_global` resolves from `x` to `0`.

**2b - the decision is latched, never re-checked.** The block tests
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

The last one is 2b: the enable rises and AVDD goes out of spec in the same time
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
