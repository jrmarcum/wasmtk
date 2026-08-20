# Bug report / prompt for the `wabt-ts` team

## 🔴 NEW — 2026-08-20 (wabt-ts 1.3.5): `ref.null` cannot be encoded for ANY heap type

**TL;DR.** `ref.null <heaptype>` parses for most heap types but then dies in wabt-ts's **own binary
writer** with an internal invariant error. For six of the eleven heap types the error names the
**wrong type** (`funcref`) regardless of what was written, which suggests the heap type is being
discarded at parse time and replaced with a default. `ref.func $g` encodes fine, so this is specific
to `ref.null`. We could not find any spelling of `ref.null` that produces bytes.

### Minimal repro

```ts
import wabt from "jsr:@jrmarcum/wabt-ts@^1.3.5/compat";
const w = await wabt();
const p = w.parseWat("t.wat", `(module (func (drop (ref.null func))))`, { enable_all: true });
p.toBinary({});   // throws
// binary writer: unresolved name-var "funcref" for var — run resolveNames before encoding
```

### Full matrix — `(module (func (drop (ref.null <H>))))`, `enable_all: true`

| `<H>` | Result | Message |
| --- | --- | --- |
| `func` | ENCODE-FAIL | unresolved name-var **`"funcref"`** |
| `extern` | ENCODE-FAIL | unresolved name-var **`"externref"`** |
| `any` | ENCODE-FAIL | unresolved name-var **`"funcref"`** ← wrong name |
| `eq` | ENCODE-FAIL | unresolved name-var **`"funcref"`** ← wrong name |
| `i31` | ENCODE-FAIL | unresolved name-var **`"funcref"`** ← wrong name |
| `none` | ENCODE-FAIL | unresolved name-var **`"funcref"`** ← wrong name |
| `noextern` | ENCODE-FAIL | unresolved name-var **`"funcref"`** ← wrong name |
| `nofunc` | ENCODE-FAIL | unresolved name-var **`"funcref"`** ← wrong name |
| `exn` | PARSE-FAIL | `expected value type, got <token:163>` |
| `struct` | PARSE-FAIL | `expected value type, got <token:48>` |
| `array` | PARSE-FAIL | `expected value type, got <token:2>` |

The six "wrong name" rows are the useful signal: `ref.null any` should never mention `funcref`.

### Two things that make this hard to work around

1. **The error tells the caller to `resolveNames`, but the compat surface does not expose it.**
   `Object.getOwnPropertyNames` on the `parseWat` result shows no `resolveNames` (and no `validate`).
   Upstream `wat2wasm` resolves names as part of its pipeline; the compat `parseWat` → `toBinary`
   path appears to skip that step with no way for the caller to supply it. Either `parseWat` should
   run it internally, or it needs to be exposed.
2. **Position does not matter** — function body, `global` initialiser, and result-type contexts all
   fail identically. `(ref null $t)` as a *type* (param/result) is fine; only the **instruction**
   is affected.

### Blast radius we can see

`ref.null func`/`extern` appears in **27** files of the official spec testsuite. Concretely,
`ref_null.wast` runs **0 passed / 0 failed / 34 skipped** through our runner — every module in it is
rejected, so the whole file is dead weight rather than coverage. Because our runner counts an
unassemblable module as a *skip*, this costs silent coverage, not failures.

### What we are explicitly NOT reporting as wabt-ts bugs

We checked upstream wabt's `src/wast-parser.cc` before writing this, and these two look like
**faithful parity with upstream**, not wabt-ts regressions. Feature requests at most — please push
back if you disagree:

- **`ref.null $t` with a concrete type index** (function-references proposal). wabt-ts gives
  `expected value type`; upstream `ParseRefKind` errors with `ErrorExpected({"func","extern","exn"})`,
  i.e. it also accepts only abstract heap types.
- **`(module definition …)`** — the newer wast script form. Upstream's parser has no `definition`
  handling either.

`ref.null exn` is the ambiguous one: upstream's `ErrorExpected` list **includes `exn`**, so wabt-ts
rejecting it may be a genuine divergence. We have not confirmed that against a built upstream binary.

### Limits of our evidence — please sanity-check before acting

- Everything above is from `jsr:@jrmarcum/wabt-ts@1.3.5` via the **`/compat`** entry point. We have
  not tried the native API, and it is possible the native surface exposes a resolve step that makes
  all of this a usage error on our side. **If so, tell us and we will fix our caller** — the compat
  path is what `wasmtk wast` uses today.
- Our reading of upstream wabt is from the **source on GitHub, not a local build or a `wat2wasm`
  run**. Treat the parity claims as "please confirm", not as established.
- We have not bisected which wabt-ts version introduced this. It may never have worked; our corpus
  only started exercising `ref.null` broadly after a 2026-08-20 testsuite refresh.

### What would help

If you fix any of these, **please say which constructs moved**. We gate per file on "no file lost a
pass", so a toolchain change that alters the denominator is indistinguishable from a regression
unless we know what to re-measure. We measure after your change rather than predicting — a fix that
also *adds* newly-reachable assertions is welcome and expected.

---


## ✅ ALL THREE FINDINGS RESOLVED (wabt-ts 1.3.4 + 1.3.5, 2026-07-02) — thank you

Running the full official WASM spec `.wast` testsuite through `wasmtk wast` on **1.3.5**, every core
execution assertion passes (gate: 41 files, 12444 assertions, 0 fail). The three distinct wabt-ts bugs
this exercise surfaced are all fixed:

- **A (1.3.4)** — `br_if` / `br_table` with a branch value.
- **B (1.3.4)** — over-precise HEX float consts rounded to nearest-even.
- **C (1.3.5)** — decimal `f32.const` single-rounded (was double-rounded decimal→f64→f32).

The historical detail below is kept for the record. Remaining non-wabt-ts items (JS-boundary NaN payload
args; `assert_invalid`/`assert_malformed` validator leniency) are the runner's skips, not bugs.

---

**History (updated 2026-07-02, wabt-ts 1.3.4):** the two bugs first reported below were fixed in 1.3.4;
one remained (**Bug C**, decimal→f32 double-rounding) — now fixed in 1.3.5.

**Context.** wasmtk's `wasmtk wast` runner assembles each `(module …)` with `jsr:@jrmarcum/wabt-ts/compat`
and runs the official WebAssembly spec testsuite's assertions on host V8. Every isolated execution
failure is a wabt-ts assembly bug (V8 is spec-compliant; fed wabt-ts's bytes it yields the wrong result).

```ts
import wabt from "jsr:@jrmarcum/wabt-ts@^1.3.4/compat";
const w = await wabt();
const dv = new DataView(new ArrayBuffer(8));
const f32bits = (x: number) => "0x" + (dv.setFloat32(0, x), dv.getUint32(0)).toString(16).padStart(8, "0");
async function f32const(lit: string) {
  const p = w.parseWat("x", `(module (func (export "f") (result f32) (f32.const ${lit})))`, { enable_all: true });
  const { instance } = await WebAssembly.instantiate(new Uint8Array(p.toBinary({}).buffer), {});
  return f32bits((instance.exports as any).f());
}
```

---

## Bug C — decimal `f32.const` is DOUBLE-ROUNDED (decimal→f64→f32) instead of single-rounded

A decimal float literal in an `f32.const` must be rounded **once**, directly from the decimal value to the
nearest f32 (round-to-nearest-even). wabt-ts appears to round decimal→f64 first and then f64→f32, which
gives a different result for values crafted to sit at an f32 rounding boundary (the spec testsuite's
`const.wast` has these on purpose):

```
f32const("+8.8817847263968443574e-16")  →  0x26800000   (spec-correct: 0x26800001)
f32const("+8.8817857851880284252e-16")  →  0x26800002   (spec-correct: 0x26800001)
```

Both spec-correct answers are `0x1.000002p-50` = `0x26800001`. The first input is exactly at the midpoint
between `0x1.000000p-50` and `0x1.000001p-50` at f64 precision but rounds **up** to `0x1.000002p-50` under
correct single decimal→f32 rounding; wabt-ts truncates to `0x1.000000`. (Note V8's `Math.fround(Number(s))`
reproduces the *same wrong* answers — because that JS idiom also double-rounds — so V8 can't be used as the
oracle here; the spec `.wast` expected value is the oracle.)

**Fix site:** the decimal float-literal parser for f32 consts — it needs to round decimal→f32 directly
(single rounding with a sticky bit over the full decimal expansion), not via an intermediate f64.
**4 failures** in `const.wast` (the `f32` decimal-boundary cases). (The analogous f64 decimal consts are
correct — only the narrower f32 target exposes the double-round.)

---

## Not wabt-ts bugs (for the record)

- **NaN-payload arguments.** Spec tests like `(assert_return (invoke "i32.reinterpret_f32" (f32.const
  nan:0x200000)) …)` pass a NaN with a *specific* payload as an argument. Through the JS API a NaN can't
  carry a non-canonical payload (V8 canonicalizes it crossing the number boundary), so these are untestable
  via a JS host — the wasmtk runner **skips** them. Not a wabt-ts issue.
- **`assert_invalid` / `assert_malformed` leniency** (e.g. `i32.const 4294967296` out of range, `1__000`
  double underscore) — validator-strictness gaps, counted as skips. Lower priority; only relevant if you
  want `wabt-ts` to be a strict validator.

## Already FIXED in 1.3.4 (were the original two bugs in this report)

- **`br_if` / `br_table` with a branch value** — previously dropped the value / yielded the condition, or
  produced bytes V8 rejected ("expected 1 elements on the stack for branch"). ✅ Fixed — `labels.wast`,
  `block.wast`, `nop.wast`, `local_get.wast`, `func.wast` now run clean.
- **Over-precise HEX float consts** (`0x1.00000100000000001p-50`) truncated instead of round-to-nearest-even.
  ✅ Fixed — the hex-float path now rounds correctly.

## How to see the full picture

From the wasmtk repo: `wasmtk wast tests/module/wasm_wast/testsuite-main` (add `--verbose`), or the curated
gate `deno run --allow-read --allow-net tests/wast_tests.ts` (40 core files, 12134 execution assertions,
0 fail — `const.wast` excluded pending Bug C).
