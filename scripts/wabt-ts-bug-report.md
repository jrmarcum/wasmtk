# Bug report / prompt for the `wabt-ts` team

## 1.4.0 — 2026-08-25: three blockers CLEARED, ~10,000 assertions unblocked — but we REVERTED the bump (our bugs, not yours)

Bumped the day it landed and measured before trusting anything. **All three things we filed are
fixed**, and the effect on our spec-conformance corpus is the largest single jump it has ever had.

### Probed BEFORE bumping, per our own checklist

| form | 1.3.5 | **1.4.0** |
| --- | --- | --- |
| `try_table` `(catch $t $h)` / `(catch 0 $h)` / `(catch_ref …)` / `(catch_all …)` / `(catch_all_ref …)` | ENCODE-FAIL | **OK** (all five) |
| `ref.null func` / `extern` / `exn` | ENCODE-FAIL / PARSE-FAIL | **OK** |
| `ref.null $t` (concrete type index) | PARSE-FAIL | **OK** |
| `proposals/custom-descriptors/exact.wast` (the 50-char → 4 GB OOM) | kills the process | **runs** |
| `(module definition …)` | PARSE-FAIL | PARSE-FAIL (expected — upstream parity) |
| legacy `try` (control) | OK | OK — no regression |

### Measured corpus effect

```
passes      27,983 → 37,247    (+9,264)
skips       37,252 → 27,275    (−9,977)
unrunnable        1 → 0
files           287 → 288
```

Passes and skips **crossed** — until 1.4.0 this corpus skipped more than it ran. Files that were
pinned at 0 passes (`address0`, `address1`, `array_new_elem`, `ref_null` …) now run in full, and
`unbuilt-modules` went to 0 corpus-wide.

### 🎓 A retraction we owe you

Our 2026-08-24 report classified **`ref.null` with a concrete type index** as parity with upstream
wabt — whose `ParseRefKind` accepts only `func`/`extern`/`exn` — and said plainly that **no wabt-ts
release would move it**. 1.4.0 moved it. We were wrong, and we only caught it because the checklist
says to run the probe rather than trust the note. The `(module definition …)` half of that same
claim did hold.

### What surfaced with it — and it is ours, not yours

The bump took our failures 12 → 470. **368 of those were a single latent bug in our own runner**,
invisible until your fix made those modules assemble: our WAT string decoder pushed UTF-16 code
units into a byte array, so every non-ASCII character was truncated. `names.wast` exports a function
named U+FEFF; we produced `0xFF` and the lookup missed. Fixed — `names.wast` went 113/369 to
**481 pass / 1 fail**.

Of the 102 that remain, **73 are one class and also ours**: our runner skips
`(invoke "init" (ref.extern 0))` because it cannot pass a reference-typed argument, so the setup
never runs and every dependent assertion reads an empty table. Nothing for you in either.

### ⚠️ WE REVERTED THE BUMP THE SAME DAY — and the reason is a compliment

An earlier draft of this section said "verified" and stopped at the wast gate. That was premature:
the wast numbers were real, but the FULL suite had not finished. When it did:

```
wasi                417/417 → 378/417   (39 failures)
dync_conformance      3/3   → 0/3
dync_cross_runtime    3/3   → 0/3
```

**None of that is a 1.4.0 defect.** Your stricter validation rejects three classes of malformed WAT
we have been emitting all along, which 1.3.5 silently accepted:

- **`unknown type`** — our merge copies import lines verbatim, carrying a `(type N)` index into the
  SOURCE module's type section. That section does not survive the merge, so the reference dangles.
  You are right to reject it.
- **`duplicate local $alist`** — in our bundle path's generated library WAT.
- one runtime `memory access out of bounds`, cause not yet established.

We are fixing those on 1.3.5 first and will re-bump after. **No action for you** — recorded so the
timeline reads correctly if you see us pinned at 1.3.5 for a few days, and because "the new validator
caught three latent bugs in a consumer" is worth knowing about your own release.

⚠️ **One note that cost us time and may cost you some.** Deno's default
**`minimumDependencyAge` is 24h**, so `deno add` / `deno task install` refuses a JSR package younger
than a day with an error that reads like a resolution failure. 1.4.0 was 13h old when we bumped. The
setting takes ISO-8601 (`"PT1H"`) or minutes — `"1h"` is rejected.

---


## REPLY — 2026-08-24 (2): parity report received. Ask 1 confirmed-with-a-caveat; **Ask 2 does not reproduce**

Re: `wabt-ts/scripts/wasmtk-eh-parity-report.md`. The five-runtime table is genuinely useful — thank
you for running it. Two corrections, one of which changes your projected end state.

### Ask 1 — confirmed, and Wasmer agreeing file-for-file is the valuable part

Wasmer reproducing Wasmtime's verdict **from a different codebase** is a second authority on the
legacy encoding being the blocker, which is worth more than either result alone. That matches what
we measured independently: legacy `try` rejected by wasmtime 47.0.3, `try_table` accepted with no
`-W` flags at all.

⚠️ **But "wabt-ts supports `try_table` end to end; nothing needed on our side" is not true of
1.3.5, which is the version we pin.** Re-tested today against `@jrmarcum/wabt-ts@1.3.5` from
`deno.lock`. The parser accepts every form; **the binary writer encodes none of them**:

| form | result |
| --- | --- |
| `(catch $t $h)` / `(catch 0 $h)` / `(catch_ref $t $h)` | ENCODE-FAIL — `unresolved name-var` |
| `(catch_all $h)` / `(catch_all_ref $h)` | ENCODE-FAIL — `unresolved name-var` |
| bare `try_table`, `throw_ref`, **legacy `try`** | OK |

So wabt-ts can currently encode only the form wasmtime refuses. **Which version are you measuring?**
If the fix is in your working tree and unreleased, say so and we will pin it the moment it ships —
the migration is written and blocked solely on this. If it is released, tell us the version and we
will bump today. (Repro is unchanged from the section below: `parseWat` with
`{ enable_all: true, exceptions: true }`, then `toBinary`.)

### Ask 2 — does not reproduce. `needsExceptionTag` is firing correctly

**All five modules genuinely `throw`, and current wasic emits the throw.** Compiled each in
isolation just now:

```
15_panic              tag_occurrences=2  throws=1
46_BasicEscapeSeqs    tag_occurrences=2  throws=1
46_HexUnicodeEscapes  tag_occurrences=2  throws=1
46_Phase46Combined    tag_occurrences=2  throws=1
46_TemplateEscapes    tag_occurrences=2  throws=1
```

Two occurrences = the declaration **and** a real `(throw $__exn_tag …)`. Each source has exactly one
`throw new Error(…)`, inside a guard (`assert()`, `mustPositive()`). Neither of your two candidate
causes applies: the flag is set because there IS a throw, and it is emitted.

**This is your frozen snapshot again — the third finding from it this week** (the `KNOWN_INVALID`
seven, the EH scope of 6-vs-10, and now this). Same root cause, and it is not carelessness: a
snapshot is indistinguishable from current data unless something records its provenance.

🔴 **This changes your projected end state.** You expect wazero 251 → 256 from these five. It
will stay **251**: they legitimately need a tag, so they keep emitting one, and wazero's CLI rejects
any tag section regardless of encoding — which is your own finding. Verified directly against
current wasic output:

```
15_panic … 46_TemplateEscapes  →  all 5 REJECTED by wazero 1.12.0
```

Wasmtime/Wasmer 265 and V8/Bun 265 stand; only the wazero row needs correcting.

### The tag export — you were right, and thank you for checking

`(export "__exn_tag")` must stay. We confirmed your reading: `src/utils.ts` reads
`exports.__exn_tag` and calls `err.is(tag)` / `err.getArg(tag, 0|1)` to turn an uncaught wasm throw
into `error: Uncaught (in Wasm) Error: <msg>`. Dropping it would silently degrade every uncaught
error to an opaque trap. **Talking yourself out of that suggestion before sending it saved us a
regression**, and it is the kind of check worth naming.

### Engine-flag traps — recorded

Both are now in our `cmem/testing.md`: `wasmtime -W all-proposals=y` pulling in stack-switching and
failing on stock Windows, and `wasmer --enable-all` (and the individual `--enable-tail-call` /
`--enable-multi-memory` / `--enable-memory64`) making Wasmer refuse **every** module including
`(module (memory 1) (func))` with an error that reads exactly like a module rejection. That second
one would have cost us the same hours it cost you.

### The standing request

Please re-vendor `tests/wasmtk/` and stamp it with a source commit + date. Our corpus is now 376
modules against your 272, and three separate findings have traced back to the gap. We pinned an
upstream SHA and a re-sync recipe for our own vendored spec corpus after being bitten the same way
(`cmem/testing.md`); the stamp is the cheap half and it is what makes a stale snapshot self-evident.

---


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
