# Bug report / prompt for the `wabt-ts` team

**Context.** wasmtk added a `.wast` spec-script runner (`wasmtk wast`) that assembles each `(module …)`
with the pluggable WABT backend (currently `jsr:@jrmarcum/wabt-ts@^1.3.1/compat`) and executes the
official WebAssembly spec testsuite's assertions on the host V8 engine. Across ~14,400 core-suite
assertions the result is ~13,200 pass / 34 fail. **Every one of the 34 failures was isolated to a
`wabt-ts` assembly bug** (V8 is spec-compliant; feeding it `wabt-ts`'s bytes yields the wrong result).
Two distinct root causes. Both reproduce in tiny standalone modules.

Reproduce with Deno (uses the same backend wasmtk resolves):

```ts
import wabt from "jsr:@jrmarcum/wabt-ts@^1.3.1/compat"; // or the version under test
const w = await wabt();
const dv = new DataView(new ArrayBuffer(8));
const f32bits = (x: number) => (dv.setFloat32(0, x), dv.getUint32(0).toString(16).padStart(8, "0"));
async function run(wat: string, arg?: number) {
  const p = w.parseWat("x", wat, { enable_all: true });
  const { instance } = await WebAssembly.instantiate(new Uint8Array(p.toBinary({}).buffer), {});
  return (instance.exports as any).f(arg);
}
```

---

## Bug A — `br_if` / `br_table` with a branch VALUE are mis-encoded

When a block has a result type and a **conditional** branch (`br_if` / `br_table`) carries a value to
that label, wabt-ts emits wrong bytecode. Plain unconditional `br` with a value is fine — only the
conditional branches are affected. Two visible symptoms depending on whether code follows the branch:

**A1 — no code after the branch → returns the CONDITION instead of the branched VALUE.**

```wat
(module (func (export "f") (param i32) (result i32)
  (block $l (result i32) (br_if $l (local.get 0) (i32.const 1)))))
```
`f(9)` → **1** (the `i32.const 1` condition).  Spec/V8-correct: **9** (`local.get 0`).
Reproduces identically in unfolded form (`local.get 0; i32.const 1; br_if $l`), so it is an **encoder**
bug, not a folded-expression parsing bug — the branch's value operand is dropped and the condition is
left as the block result.

**A2 — code after the branch → V8 REJECTS the module (invalid stack).**

```wat
(module (func (export "f") (param i32) (result i32)
  (block $l (result i32) (br_if $l (local.get 0) (i32.const 1)) (i32.const -1))))
```
→ `WebAssembly.instantiate(): Compiling function #0 failed: expected 1 elements on the stack for
branch, found 0`. Same for `br_table $l $l (local.get 0) (i32.const 0)` in that position.

**Expected:** for `br_if`/`br_table` targeting a block/loop with an N-result label, the N value operands
must be emitted *below* the index/condition operand and left on the stack for the branch (exactly as for
unconditional `br`). **Likely fix site:** the operand-ordering / stack-typing for `br_if` and `br_table`
in the encoder (compare against the working `br` path).

**Spec-suite files that surface this:** `local_get.wast`, `labels.wast`, `func.wast`, `conversions.wast`,
plus many "module failed to compile" skips (`nop.wast` #32, etc. — the A2 form).

---

## Bug B — over-precise hex-float literals are TRUNCATED, not round-to-nearest-even

A float const whose hex mantissa has more bits than the target type must be rounded to nearest, ties to
even (with a sticky bit over the discarded low bits). wabt-ts appears to truncate.

```wat
(module (func (export "f") (result f32) (f32.const +0x1.00000100000000001p-50)))
```
The literal = `(1 + 2^-24 + 2^-68) · 2^-50`. `2^-24` is exactly half an f32 ULP at this exponent, and the
extra `2^-68` pushes it just **above** the midpoint, so it must round **up**.

- wabt-ts assembles f32 bits **`0x26800000`** (= `0x1.000000p-50`, rounded down / truncated).
- Spec/V8-correct: **`0x26800001`** (= `0x1.000002p-50`).

**Expected:** round-to-nearest-even using a sticky bit across all mantissa bits beyond the target
precision (23 bits for f32, 52 for f64). **Likely fix site:** the hex-float literal parser
(`parseHexFloat…`) — it drops bits past the target width instead of accumulating a round/sticky decision.
(This is adjacent to the earlier "hex-float parsed as 0" bug fixed in 1.3.1, but a distinct rounding
issue.) **22 failures** in `const.wast` across f32 and f64, including values near `FLT_MAX`/`DBL_MAX`.

---

## Not bugs (for completeness)

`assert_invalid` / `assert_malformed` cases where wabt-ts accepts a spec-invalid/malformed module (e.g.
`i32.const 4294967296` out of range, `1__000` double-underscore) are validator-strictness gaps, not
execution bugs; the wasmtk runner counts them as *skips*, not failures. They're lower priority but are
also real conformance gaps if you want `wabt-ts` to be a strict validator.

## How to see the full picture

From the wasmtk repo: `wasmtk wast tests/module/wasm_wast/testsuite-main` (add `--verbose` for detail),
or the curated clean regression gate `deno run --allow-read --allow-net tests/wast_tests.ts`.
