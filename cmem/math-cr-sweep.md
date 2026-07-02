# mathlib correctly-rounded sweep — status + resume guide

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
| `asin` `acos` `atan2` | (this commit) | e2e asin 0/915, acos 0/915, atan2 0/908; dd vs oracle 0/300k each |

Full numbered suite stays **green** (375/375; regression test `67_TrigCorrectlyRounded`). The 38_Math*
tests use `Math.round`-tolerance so they're robust; only a few tests byte-compare raw trig and those
use CR==V8 args. All `atan`/`atan2`/`asin`/`acos` test sites use `Math.round(...)` tolerance → robust.

**REMAINING (still old ~1e-11 minimax, NOT yet CR):** `expm1`, `log1p`, `pow` (`**`), `sinh`, `cosh`,
`tanh`, `asinh`, `acosh`, `atanh`. (`sinh`/`cosh`/`tanh`/`expm1` dd refs already validated 0/300k — WAT
port pending.)

**Planned next order:** hyperbolics `sinh`/`cosh`/`tanh` + `expm1` (share dd `exp`/`expm1` helpers) →
`asinh`/`acosh`/`atanh` + `log1p` (share dd `log`-of-dd) → `pow` (hardest).

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
