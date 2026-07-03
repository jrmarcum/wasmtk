# mathlib correctly-rounded sweep — status + resume guide

> **✅ SWEEP COMPLETE (2026-07-02).** Every `mathlib` elementary function is now IEEE-754
> correctly-rounded via double-double: `sin cos tan`, `exp`, `log log2 log10`, `cbrt`, `atan`,
> `asin acos atan2`, `sinh cosh tanh expm1`, `asinh acosh atanh log1p`, and **`pow`**. Each was
> validated bit-for-bit vs an independent BigInt oracle through the full pipeline. Suite 375/375.

**Goal (owner, 2026-07-01):** make every `mathlib` (`src/wasm/mathlib.wat`) elementary function
return the **IEEE-754 correctly-rounded** result — the unique, platform/version/language-independent
value every correct libm agrees on. This gives maximum accuracy AND maximum cross-language
compatibility for the universal-loader ecosystem (each faithfully-rounded libm — V8/glibc/MSVC/Go/
Rust — disagrees with the others by ~1 ULP, but they all cluster on the correctly-rounded value).
Chosen over "match V8 bit-for-bit" because modern V8 delegates `Math.sin/cos` to LLVM-libc's
`shared::sin/cos`, which are themselves only *faithfully*-rounded (~99.76% CR) and a moving,
version-pinned target.

## Status (2026-07-02)

**DONE — correctly-rounded + committed** (each validated bit-for-bit vs a BigInt oracle THROUGH the
full pipeline: wat2wasm + wasmmerge + Binaryen `-Oz`):

| Fn(s) | commit | validation |
| --- | --- | --- |
| `sin` `cos` `tan` | `d64a3dfefd5` | 1032 sin/cos + 412 tan, 0 off |
| `exp` | `bd69b201409` | 518/518 (subnormal→`exp(-745)`, overflow→`exp(709)`) |
| `log` `log2` `log10` | `b72afa88f3e` | 1239/1239 (`log2` of powers → exact ints; `1e±300`) |
| `cbrt` | `8f0c5f77a5b` | 515/515 (subnormals, negatives, `1e±300`) |
| `atan` | `e0abf54d5b3` | 1528/1528 e2e (dd vs oracle 0/400k; boundaries 1, tan(pi/8), 1e±300) |
| `asin` `acos` `atan2` | `76cdb889028` | e2e asin 0/915, acos 0/915, atan2 0/908; dd vs oracle 0/300k each |
| `sinh` `cosh` `tanh` `expm1` | `63df7ce26dd` | e2e sinh/cosh/tanh 0/718, expm1 0/711; dd vs oracle 0/300k each |
| `asinh` `acosh` `atanh` `log1p` | `11a9da1d4d7` | e2e asinh 0/510, acosh 0/508, atanh 0/507, log1p 0/508; dd vs oracle 0/300k each |
| `pow` (`**`) | (this commit) | e2e 0/1418 (exact ints 2³=8, 2¹⁰=1024, 4^0.5=2, neg base, ±0/±∞); dd vs oracle 0/400k + subnormal/overflow bands 0/200k |

**SWEEP COMPLETE.** Full numbered suite stays **green** (375/375; regression test `67_TrigCorrectlyRounded`).
The 38_Math* tests use `Math.round`-tolerance so they're robust; only a few tests byte-compare raw trig
and those use CR==V8 args. All CR-swept fns' test sites use `Math.round(...)` tolerance → robust.

## pow — the last one (moved into mathlib + routed from wasic)

Before this, `pow`/`**`/`Math.pow` used an inline `$__math_pow` in `wasic.ts` that only did positive-integer
exponents + `0.5` sqrt (non-integer exps truncated, negative exps returned 1 — buggy). Now:

- **`$pow(x,y)` in mathlib** = `sign · exp(y·log|x|)` all in dd, with the full IEEE-754 special-case ladder
  (`y=0→1` even NaN, `x=1→1`, NaN prop, `y=1→x`, `x=±0`, `y=±∞`, `x=±∞`, `x<0` requires integer `y`).
- **`$__expddx(th,tl) -> (sum_hi, sum_lo, k)`** — exp of a dd argument returning the UNSCALED dd sum + `k`;
  the caller finishes with `$__cr(sum_hi, sum_lo, k)` so overflow→∞ and subnormal results round correctly
  (validated 0/200k across the subnormal/overflow bands — a plain scaled-dd finish would lose the tail there).
- **`$__oddint(y) -> i32`** — 1 iff `y` is an odd integer (NaN/∞→0), for the negative-base sign + `x=±0` rules.
- **Routing (wasic.ts + console_log.ts):** `Math.pow` / `**` / `**=` / console.log-pow all emit
  `(call $mathlib_pow …)` and set `needsMathLib`; `pow` added to the two console-prescan `needsMathLib`
  regexes; the inline `$__math_pow` deleted. Programs using `**` now merge mathlib (like any `Math.*`).
- dd suffices for CR pow (the classic hardest case): the error budget is `|y·log|x||·2^-106 ≈ 2^-96`
  even near overflow — far below the 2^-53 CR threshold; exact integer powers land exactly.

**⚠️ Constraint surfaced by routing pow → mathlib (important):** a **mergeable capability library**
(a modc lib that `wasmmerge` re-merges into a driver — e.g. `dynrt`, Set/Map/Date/JSON/RegExp) must NOT
use any `Math.*` that routes to mathlib (`pow`, `sin`/`cos`/…, `exp`, `log`, …), because that pulls the
whole mathlib into the library, and **mathlib-nested-inside-a-re-merged-library traps at runtime**
(`memory access out of bounds` — allocator/global relocation on the double merge). `dynrt` was the only
capability lib using such a function: its interpreter's `Math.pow` (`dynrt_lib_modc.ts`). Fixed by making
dynrt's pow **self-contained** (integer-exponent multiply loop + `Math.sqrt`, which is inline `f64.sqrt` and
needs no mathlib) — matching dynrt's historical integer+sqrt pow support (regen `caps_bytes.ts` after).
Inline `Math.*` (`floor`/`ceil`/`round`/`trunc`/`abs`/`sqrt`/`sign`/`min`/`max`, the `F64_UNARY`/i32 set)
are fine in mergeable libs — only the mathlib-routed ones are the hazard. (The general fix — making a
nested mathlib merge idempotent in `wasmmerge` — is deferred; self-containment is the cheap correct path.)

## New dd machinery (added with asinh/acosh/atanh/log1p)

- **`$__logddx(ah,al) -> (hi,lo)`** — ln of a dd argument = `logdd(ah) + al/ah` (the `(al/ah)²/2` term
  ~2^-107 is negligible). The building block for all log-composite functions.
- **asinh** = `log(a+√(a²+1))` in dd; `log(a)+ln2` for `a>1e150` (avoids `a²` overflow). copysign.
- **acosh** = `log(x+√(x²−1))` in dd (x≥1); `log(x)+ln2` for `x>1e150`. x<1→NaN, x=1→0.
- **atanh** = `0.5·log((1+x)/(1−x))` in dd; `x` for `|x|<2^-27`; ±1→±∞, |x|>1→NaN.
- **log1p** = `log` of the **exact** dd `1+x` (`twoSum(1,x)`); `x` for `|x|<2^-54`; x<−1→NaN, x=−1→−∞.

## New dd machinery (added with sinh/cosh/tanh/expm1)

- **`$__expS(x, extra) -> (hi,lo)`** — dd `e^x · 2^extra`; the `extra` post-scale folds a `÷2` into the
  exponent so `e^a/2` never overflows the twoProduct intermediate (dd ops break within factor ~1.3e8 of MAX).
- **`$__expm1dd(x) -> (hi,lo)`** — dd `e^x − 1`; Taylor `Σ xⁿ/n!` for `|x|<0.5` (dodges the E−1 cancellation),
  else `$__expS − 1`.
- **sinh/cosh** = `(E ∓ 1/E)/2` in dd for `|x| ≤ 300`; for `|x| > 300` the `e^-a` term is 0 to CR → just
  `$__expS(a,-1)` = `e^a/2` (overflow-safe up to the true ±inf at ~710.5). copysign for sinh's sign.
- **tanh** = `expm1(2a)/(expm1(2a)+2)` in dd (dodges cancellation); `±1` for `|x| ≥ 22` (`1−tanh < 2^-63`). copysign.
- **expm1** = `crRound($__expm1dd(x))`; `x` for `|x|<2^-54`, `−1` for `x=−∞`, `+∞` for `x≥709.78`.

## New reusable dd machinery (added with asin/acos/atan2)

- **`$__ddsqrt(ah,al) -> (hi,lo)`** — QD one-step Newton sqrt (`x=1/√ah; ax=ah·x; ax + (a−ax²)·x/2`), ~106 bits.
- **`$__atandd(zh,zl) -> (hi,lo)`** — the atan CORE as a dd→dd function (reduction + dd Taylor + pi combine,
  signed). `$atan` = `crRound($__atandd(x,0))`. `asin`/`acos`/`atan2` feed it a dd argument.
- **asin** = `atan(a/√(1−a²))` all in dd (a=|x|, 1−a² in dd, `$__ddsqrt`, `$__dddiv`, `$__atandd`), crRound + sign.
- **acos** = `2·atan(√((1−x)/(1+x)))` — one dd formula accurate across the whole (−1,1) (x=1→0, x=−1→π).
- **atan2** = `atan(y/x)` with y/x in dd, then ± dd π quadrant shift; full IEEE ±0/±∞ special cases via `copysign`.
- Oracles (`asinOracle`/`acosOracle`/`atan2Oracle`) added to `scripts/math_cr_oracle.ts` (fixed-point
  `isqrtBig`/`sqrtFx` + `atanFxSigned`).
(need an internal dd `exp` returning `(hi,lo)` BEFORE the final scale) → `asinh`/`acosh`/`atanh`
(via `log`) → `expm1`/`log1p` (range-split near 0) → `pow` (hardest: high-precision `y·log x` +
many special cases; may need triple-double or accept ≤1 ULP with documented note).

## Reusable framework already in `mathlib.wat` (the hard part — DONE)

- **dd (double-double) ops**, each returns `(hi,lo)` via WASM multi-value (verified to survive
  wabt-ts + Binaryen `-Oz`): `$__ts` (twoSum), `$__tp` (Veltkamp twoProduct — **no FMA in baseline
  WASM**, so Veltkamp split with `2^27+1=134217729`), `$__dda`, `$__ddm`, `$__ddmd` (dd×scalar),
  `$__ddri` (1/int as dd), `$__dddiv` (3-step dd quotient).
- **`$__scalbn(x, n)`** — musl-style `x·2^n`, subnormal/overflow-safe (chunked by `2^±1023`,
  subnormal via the `2^-1022·2^53` trick, final scale via exponent-bit build).
- **`$__cr(hi, lo, k)`** — correctly-round `(hi+lo)·2^k`. **NORMAL** path = `scalbn(hi+lo, k)`
  (round the dd to a double FIRST at O(1) scale, THEN scale once). **SUBNORMAL** path = round
  `(hi+lo)·2^(k+1074)` to nearest EVEN INTEGER then `·2^-1074`. Discriminator: `scalbn(hi,k) >=
  MIN_NORMAL (0x1p-1022)`. **Critical gotcha it fixes:** the naive `scalbn(hi,k)+scalbn(lo,k)`
  double-rounds — `scalbn(lo,k)` can round the tail up to exactly half-ulp (MIN_VALUE), turning a
  round-down into a tie→even round-up (off-by-1-ULP in the subnormal region).
- Trig also has `$__hiw`, `$__ddsin`, `$__ddcos`, `$__trig_reduce` (Veltkamp n-split, dd remainder
  in globals `$__tr`/`$__trt`); `log` has `$__logdd`. These globals + multi-value returns survive
  the merge.

## The RECIPE for each remaining function (proven 4×)

1. **JS reference + BigInt oracle** — build a dd implementation and an authoritative correctly-rounded
   oracle, prove the dd is 100% CR vs the oracle over 300k–500k values across the full domain.
   Dev scripts live in `scripts/math_cr_oracle.ts` (the reusable oracle harness: `toBig`,
   `roundScaled`, `crRound`, dd ops, and the done-function oracles).
   - **Oracle = fixed-point BigInt** (`P≈384–400` fractional bits) + a general
     **`roundScaled(a, e)`** = correctly round `a·2^e` to a double (handles subnormal/overflow).
   - **GOTCHA:** for functions with extreme-magnitude in/out (`exp`, `log`, `cbrt`, hyperbolics),
     the oracle MUST reduce the argument to a well-conditioned range FIRST (e.g. `cbrt`: reduce
     `a=m·2^e`, `e=3q+s`, do `cbrt(m·2^s)` in [1,8) then scale by `2^q`), else the fixed-point
     underflows/overflows and the *oracle* is wrong (the wasm was right — happened twice).
2. **Port to WAT** reusing the dd helpers + `$__scalbn`/`$__cr`. Bit-decompose via
   `i64.reinterpret_f64`; set mantissa exponent to `0x3ff` for `m∈[1,2)`; handle subnormal by
   scaling up `×2^54` and adjusting `e-=54`.
3. **Regenerate:** `wasmtk convert src/wasm/mathlib.wat` then
   `deno run --allow-read --allow-write scripts/gen_mathlib_bytes.ts`. (Installed `wasmtk` runs
   `main.ts` LIVE, so it picks up the regenerated `mathlib_bytes.ts` with no reinstall.)
4. **Validate END-TO-END:** emit a wasic program `console.log(Math.fn(id(v)))` for a battery of `v`
   (use `function id(x: f64): f64 { return x + 0.0; }` to force the runtime path, NOT compile-time
   literal folding), `wasmtk run` the `.wasm`, compare every line to the oracle. Require 100%.
5. **Verify suite** (the relevant `38_Math*` / other tests) then **commit** (feat(mathlib): …).

## Gotchas / invariants (do not relearn these)

- **Binaryen `-Oz` preserves the dd arithmetic** (it does NOT reassociate fp by default). **Never
  enable `--fast-math`** — it would collapse the twoSum/twoProduct and destroy correctness.
- **Multi-value `(result f64 f64)` returns work** through wabt-ts 1.3.x + Binaryen (the old
  multi-value encoder bug was fixed long ago). The dd helpers rely on this.
- **CR results DIFFER from Deno's V8 `Math.*`** on the small % where V8 isn't correctly-rounded
  (~0.24% for sin). This is INTENDED (wasic is the more-correct one). Tests that byte-compare raw
  trig/exp/log output must use CR==V8 args or `Math.round`/tolerance; otherwise they'd fail
  wasm-vs-ts. When adding a raw-print regression test, first check `Math.fn(arg) === <CR value>`
  in Deno for every arg.
- **`id()` forces the runtime helper.** Passing a bare literal to `Math.fn(...)` is formatted at
  compile time and does NOT exercise mathlib.
- The trig/`$__tr`/`$__trt` globals + `$__rng_state` coexist through the merge (verified).

## Per-function algorithm notes (for the DONE ones, as reference for the pattern)

- **exp:** `k=round(x/ln2)`; `r=x−k·ln2` in dd (dd `ln2` = `[0.6931471805599453, 2.3190468138462996e-17]`,
  Veltkamp-safe via `$__ddmd`); dd Taylor `Σ rⁿ/n!` (22 terms); `$__cr(sum, k)`.
- **log:** decompose `x=m·2^e` (`m∈[1,2)`; if `m≥√2` then `m/=2,e++` → `m∈[√2/2,√2)`);
  `s=(m−1)/(m+1)` in dd; `log(m)=2·atanh(s)=2s·(1+s²/3+s⁴/5+…)` (18 terms); `result=e·ln2+log(m)`,
  round `hi+lo` (result always normal). `log2`/`log10` = `round(logdd · (1/ln2 | 1/ln10) dd)` —
  dd consts `[1.4426950408889634, 2.0355273740931033e-17]`, `[0.4342944819032518, 1.098319650216765e-17]`.
- **cbrt:** decompose `|x|=m·2^e`, `e=3q+s` (`s∈{0,1,2}`), `v=m·2^s∈[1,8)`; 7 double-Newton
  `y=(2y+v/y²)/3` from `y=1.5`; ONE dd Newton `y−(y³−v)/(3y²)`; `$__cr(y_dd, q)`; reapply sign.
- **atan:** `z=|x|`; **all in dd**: comp `z>1 → z=1/z` (`$__dddiv`, atan=π/2−·); mid
  `z>tan(π/8)=0.4142135623730951 → z=(z−1)/(z+1)` (atan=π/4+·) → `|z|≤tan(π/8)`. dd Taylor
  `Σ(−1)ᵏ z^(2k+1)/(2k+1)` with the odd divisor via `$__ddri` (NOT `ddMulD(t,1/n)` — the rounded
  `1/3,1/5,…` cost ~0.2% CR); fixed 50 iters (worst-case |z|≈0.414 needs ~45). Combine with dd
  π/4=`[0.7853981633974483, 3.061616997868383e-17]` / π/2=`[1.5707963267948966, 6.123233995736766e-17]`,
  then `$__cr(sum, 0)`, reapply sign. Special: NaN→x, ±∞→±π/2, ±0→x. Oracle: `atan(x)===x` for
  `|x|<2^-27` (else `toBig` underflows). Oracle differs from V8 `Math.atan` ~2.5% (V8 atan less
  accurately rounded than its sin) — INTENDED.

## Regen + test commands

```
wasmtk convert src/wasm/mathlib.wat
deno run --allow-read --allow-write scripts/gen_mathlib_bytes.ts
deno run -A tests/wasi_tests.ts            # full numbered suite (must stay green)
```
