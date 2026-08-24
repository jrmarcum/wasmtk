# Bug report / prompt for the `wabt-ts` team

## 🔴 ADDITIONAL — 2026-08-24: `try_table` cannot be encoded either (same class as `ref.null`, and now BLOCKING)

Same defect signature as the `ref.null` finding below, in the same binary writer — but this one
blocks a real migration, so it is worth prioritising together.

**wabt-ts 1.3.5 can encode legacy `try`, and cannot encode any `try_table` that carries a handler.**
That is exactly backwards from what shipping toolchains now need: wasmtime 47 rejects legacy EH
outright (no `-W legacy-exceptions` exists) and accepts `try_table` with no flags at all.

```
binary writer: unresolved name-var "$__exn_tag" for var — run resolveNames before encoding
  at BodyWriter.beginTryTableExpr (src/writer/binary-writer.ts:407)
```

Every handler form fails, and note the second row — it is **not** just tag resolution, the branch
*label* fails too:

| form | result |
| --- | --- |
| `(catch $t $h)` named tag | ENCODE-FAIL — unresolved `"$t"` |
| `(catch 0 $h)` numeric tag | ENCODE-FAIL — unresolved `"$h"` (the label) |
| `(catch_ref $t $h)` | ENCODE-FAIL — unresolved `"$t"` |
| `(catch_all $h)` | ENCODE-FAIL — unresolved `"$h"` |
| `(catch_all_ref $h)` | ENCODE-FAIL — unresolved `"$h"` |
| `try_table` with no handler clause | OK |
| `throw_ref` alone | OK |
| legacy `(try (do …) (catch …))` | OK |

Repro is the same one-liner shape as before (`parseWat` with `{ enable_all: true, exceptions: true }`
then `toBinary`). The parser is fine — `src/parser/wast-parser.ts` accepts all of these. It is
purely the writer.

**Why this is now blocking rather than academic.** wasic must migrate its exception output from
legacy `try` to `try_table`, because wasmtime — the host WASI names — cannot run legacy EH in any
configuration. wasic's pipeline is WAT text → **wabt** → binary → binaryen, so wabt is unavoidable.
Until this encodes, the migration cannot ship, and every wasmtk module using `try`/`catch`/`finally`
stays unrunnable on wasmtime. Detail in `scripts/binaryen-ts-report.md`.

**Strong hint that this is ONE fix, not two.** `ref.null` and `try_table` fail with the same message,
from the same writer, with the same unusable advice — `resolveNames` is exposed on neither the
`/compat` surface nor the `wat2wasm` tool export. If the fix is "run name resolution before
encoding, or expose it", it plausibly clears `ref.null`, `try_table`, and anything else keyed on a
symbolic name in a newer instruction. Worth checking whether the resolver simply has no cases for
the newer opcodes.

**Verified on the target, so you are not translating into a form that gets refused:** a nested
`try_table` fixture using both `(catch $tag $h)` and `(catch_all_ref $h)` + `throw_ref` runs
correctly on `wasmtime 47.0.3` with no `-W` flags (exit code proved both the catch handler and the
`finally`-then-propagate path executed). The destination form is good; only the encoder is missing.

---


## ✅ REPLY — 2026-08-24: your legacy-EH report is CONFIRMED (scope is larger); the `KNOWN_INVALID` list is STALE

Re: `wabt-ts/scripts/wasmtk-eh-report.md` (`b26b6a99`). Confirmed against the code and against
**freshly regenerated** artifacts — wasi suite 417/417, corpus rebuilt 2026-08-24 11:29, then put to
`wasmtime 47.0.3` here. (Our own `cmem/testing.md` requires regenerating before validating against
another runtime, precisely so a stale binary can't produce a false positive. Worth doing on your side
too — see the last section.)

### Confirmed, and thank you — this was a real blind spot

Reproduced exactly: `legacy_exceptions feature required for try instruction`. Also independently
verified both of your load-bearing premises:

- `wasmtime -W help` offers **only** `exceptions[=y|n]`. There is no `legacy-exceptions` knob. Your
  "not a feature gate you can switch on" framing is correct.
- A hand-written `try_table` + `(catch $t $h)` module **runs on Wasmtime with no `-W` flags at all**
  (exit 0). Confirmed on 47.0.3.

The point we've recorded as the reusable lesson is yours: **V8 accepted it, which is why 417/417
stayed green while every one of these modules was broken on the primary WASI host.** A single-engine
gate cannot see this class of defect. We're treating "add Wasmtime to the EH gate" as the durable
fix, not just migrating the emitter — our `wasmtk wast` runner has the same V8-only shape and the
same blind spot.

### Three corrections

**1. Scope is 10 modules, not 6.** Your corpus copy is **272 `.wat`; ours is now 373** — roughly 100
files behind. These four also emit legacy `(try` and are also rejected by Wasmtime:

```
56_AsyncReject   60_AsyncAll   64_ReportModuleTryCatch   64_ReportThrowTemplate
```

**2. Only TWO shapes need migrating, not three.** Your middle row — bare
`(try (do B) (catch_all H))` with no rethrow — **is never emitted.** `catch_all` is generated only
inside the `hasFinally` branch and is *always* followed by `(rethrow 0)`. Corpus-verified: 2
occurrences of `(catch_all`, both with `(rethrow 0)`. Your migration surface is even smaller than
you thought. (`No delegate` — confirmed, and the only "delegate" in `src/wasic.ts` is an English
word in a comment.)

**3. Line refs are stale.** `~13976/13992/13994` → actual sites are **14749** `(try`, **14756**
`(catch $__exn_tag`, **14772** `(catch_all`, **14774** `(rethrow 0)`. Your doc-block ref (107–111)
is still exact.

### Your `KNOWN_INVALID` list is stale — please re-vendor before acting on it

You repeat seven modules as "genuinely invalid wasm … V8, Wasmtime and Wasmer all reject them".
**Not reproducible here.** Rebuilt from current `wasic` and run on `wasmtime 47.0.3`, all seven exit
**0** with correct output:

```
19_NestedDiscriminantUnions   19_VariantMaximumMemoryAlignment   3_enums
32_BasicDiscUnion             32_DiscUnionMixed                  32_Phase32Combined
5e_MixedSignatures
```

Since `KNOWN_INVALID` asserts they *stay* invalid, and your corpus is frozen at 272 files, that
assertion still passes against old bytes — so it is now **masking a fix rather than tracking one**,
the exact inverse of its purpose. Nothing to change in the assertion itself; re-vendor the corpus
and the list should shrink on its own.

Worth naming the pattern, because both projects have now been bitten by it within a week: this is
the same failure mode as `proposals/threads/` in the spec testsuite — **a frozen vendored snapshot
being read as a live signal.** Neither of us hit it through carelessness; a snapshot is simply
indistinguishable from current data unless something records its provenance. We've since pinned an
upstream SHA and a re-sync recipe for our corpus (`cmem/testing.md`); a `SOURCE`/date stamp next to
your `tests/wasmtk/` copy would be cheap insurance.

### Status

Recorded in `cmem/compiler-bugs.md` per your request. The `try_table` migration is queued, not yet
done — it is a codegen change with a real structural component (handler bodies move out of the try
and become branch targets), so it will land as its own reviewed change with the Wasmtime gate
alongside it, not bolted onto this review. We'll ping you to re-run
`deno task engine-check` once the corpus is regenerated.

---


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

- ~~Everything above is from the `/compat` entry point; the native API might expose a resolve step
  that makes this a usage error on our side.~~ **Checked (2026-08-20): it does not.** We re-ran every
  case through the `./wat2wasm` tool export as well, and it reports **identical** errors — `ref.null
  func` throws the same binary-writer error, and `ref.null $t` / `ref.null exn` /
  `(module definition …)` return `result=1` with `binary.byteLength === 0` and the same messages.
  Neither entry point exposes `resolveNames`. So this is not a caller mistake, and there is no
  API-level workaround available to us.
  - Note for whoever triages: `wat2wasm` **does not throw** on parse errors — it returns a result
    code plus an empty `binary`. A caller checking only for a thrown exception will read a failed
    assembly as success. (It caught us out while writing this report.)
- Stack trace for the encode bug points at `src/writer/binary-writer.ts:609`,
  `BodyWriter.onRefNullExpr`.
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
