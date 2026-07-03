# Bug report / prompt for the `wabt-ts` team

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
