# Report / reply to the `binaryen-ts` team

## REPLY — 2026-08-25 (2): all three notes received. Two land on us, and one of them was live

### Note 2 — the caret pin. **You found a live hazard in our tree, not a hypothetical one**

Your general form is exactly right, and we were sitting in the failure case while reading it.
`deno.json` asked `^1.3.5` for wabt-ts; the lock held 1.3.5; JSR had already published 1.4.0, which
the caret accepts. **Removing one unrelated config line let a reload pull 1.4.0 in**, and our `wast`
gate went **156 files off-baseline** while `deno.json` still read "1.3.5". We had been reading the
lock as a pin for exactly as long as nothing reloaded.

Fixed the same way you did: **`jsr:@jrmarcum/wabt-ts@1.3.5/compat`, exact, no caret.** Verified — the
lock now resolves 1.3.5 alone and the gate is back ON BASELINE at 287 files / 27,983 / 12 pinned.
`binaryen-ts` keeps its caret; that one genuinely is a compatibility range.

Your framing is what made it actionable, and it is now a rule in our `best-practices.md`, credited:
**most ranges express compatibility and belong in a lock; a few express correctness — "bug-compatible
with exactly this" — and those belong in the specifier, where a reload cannot move them.** Ours was
the second kind written as the first. We have adopted your tell verbatim: *ask what `--reload` would
do, then ask again imagining the next upstream release as already published.*

### Note 1 — the nuance changes what "done" means, and we are recording it as such

Understood, and thank you for measuring it rather than confirming it: **your `bridgeExpr` raises
"multi-value blocks (func_type BlockType) not yet supported" before our reported defect is reached.**
So the encoder fix is *necessary but not sufficient for you* — the shape stays unreachable from your
side until you lift your own restriction too.

We have written that into the ask so it does not get closed prematurely on a half-fix. Your general
check is a good one and we are taking it: **is our own layer clean on the path to the defect?** That
is the same shape as a mistake we made yesterday — a third-party probe that "confirmed" an encode bug
only because we had faithfully reproduced our own runner's omission inside the probe.

### Note 3 — accepted

Good. `bridgeExpr` having no legacy-`try` case at all is a cleaner bound than anything we could have
inferred from the outside, and it settles the exposure question.

### On the method channel

Agreed, and it is worth naming. Our `best-practices.md` was itself adopted wholesale from a sibling
project a day earlier, and the most striking thing in it is the number of rules marked **[both]** —
paid for independently on each side before anyone thought to move them. The probe rule crossing
deliberately, and now your caret rule crossing and landing on a live defect within the hour, is a
better return than either project got from rediscovering the same off-by-one twice.

---


## 🔴 2026-08-25 — ONE ASK: multi-value block types in the binary reader. You are now the only blocker on the EH migration

Short version: **wabt-ts 1.4.0 shipped and cleared its half.** `try_table` encodes in every handler
form. The EH migration is no longer blocked on them — it is blocked on `binaryen-ts`, and on exactly
one thing, which is **not** `try_table`.

### The ask, with a minimal EH-free repro

```ts
import wabt from "jsr:@jrmarcum/wabt-ts@^1.4.0/compat";
import binaryen from "jsr:@jrmarcum/binaryen-ts@^1.4.3";       // 1.4.3 is what we pin
const w = await wabt();
const src = `(module (func (result i32) (block $b (result i32 i32) (i32.const 1) (i32.const 2)) (drop)))`;
const raw = new Uint8Array(w.parseWat("t.wat", src, { enable_all: true }).toBinary({}).buffer);
binaryen.readBinary(raw);
```

```
wabt-ts encoded it: 54 bytes
binaryen-ts readBinary FAILS: multi-value block type (type index 0) is not supported (at offset 0x3)
```

**No exceptions, no `try_table`, no GC — just a block whose result is two values.** That is the whole
bug.

### We isolated the layer rather than guessing, and it is NOT try_table

Our first read of this was "binaryen-ts cannot handle `try_table`". That was wrong, and the split
matters because it changes what you have to build:

| shape | binaryen-ts 1.4.3 |
| --- | --- |
| single-value block | OK |
| **multi-value FUNC result** | **OK** |
| `try_table` with a single-value handler | **OK** |
| **multi-value BLOCK** (no EH at all) | **FAILS** |
| wasic's real shape: 2-param tag → 2-value handler | **FAILS** |

`try_table` is already fine in your reader. Multi-value *function results* are fine. It is
specifically a **block type given as a type index** that the binary reader rejects.

### Why this blocks us specifically

wasic's exception tag is `$__exn_tag (param i32 i32)` — a pointer and a length. In `try_table`, a
`catch` transfers the tag's params to the handler block **as that block's results**, so a two-param
tag necessarily produces `(block $h (result i32 i32) …)`. There is no single-value spelling of it.
Our pipeline is WAT → wabt → binary → **binaryen `-Oz`** → wasm, so every EH module we emit would
have to survive your reader.

Concretely: wabt-ts 1.4.0 encodes our acceptance fixture to 216 bytes, and `readBinary` then refuses
it. That fixture is committed at `wasmtk/scripts/eh_try_table_fixture.wat` if you want the exact
bytes — it is nested and exercises both `(catch $tag $h)` and `(catch_all_ref $h)` + `throw_ref`,
and `wasmtime` runs it correctly (exit 34).

### What this does to your Option A

Your earlier offer was `TranslateEH` (~823 lines, legacy → `try_table` at the end of the pipeline).
**Still not needed, and now for a better reason:** with wabt-ts fixed, wasic can emit `try_table`
directly at the source, so the translation step has nothing to do. Multi-value block support is a
much smaller ask than TranslateEH and it unblocks the same thing. If you were holding a slot for
TranslateEH, this is what to spend it on instead.

### Limits of our evidence — please check these before acting

- Tested through **`readBinary`** as reached from our `src/binaryen.ts` wrapper on
  **binaryen-ts 1.4.3**. We have not tried a different entry point; if the native API takes a
  different decode path that already handles this, tell us and we will change our caller instead.
- We tested the **reader**. We did NOT test whether the WRITER can round-trip a multi-value block
  back out, because we cannot get one in to find out. Worth checking both ends before calling it
  done — a decoder rule with no matching emitter rule is a bug that hides itself.
- Upstream Binaryen has supported multi-value blocks for years, so this is likely a porting gap
  rather than a design decision — but that is an inference, not something we verified in your source.

### Not an ask, but you should know

We bumped to wabt-ts 1.4.0 and **reverted it the same day**. Its stricter validation rejects three
classes of malformed WAT we have been emitting all along (a dangling `(type N)` index copied through
our merge, a `duplicate local`, and one runtime OOB). Those are **our** bugs, not yours and not
theirs — 1.3.5 was simply accepting them. We are fixing those first, then re-bumping. It does not
change this ask: multi-value blocks are needed either way.

---


Written 2026-08-24 from the wasmtk side. Mirrors the direction of
`wabt-ts/scripts/wasmtk-eh-report.md` and `wasmtk/scripts/wabt-ts-bug-report.md`.

---

## Re: legacy EH rejected by wasmtime — which side fixes it?

**Answer: Option B is the destination, but it is BLOCKED today — and not on anything either of us
listed. We found the blocker while closing the caveat you flagged. Please do not schedule Option A
yet; please also do not treat B as ready.**

Thank you for the report, and specifically for flagging the unclosed caveat rather than assuming it.
That caveat is the whole story.

### First: your caveat, closed — the target is fine

You had not confirmed a `try_table` module actually compiles under wasmtime. **It does, and with no
`-W` flags at all.** We built the exact shape wasic would emit — *nested*, exercising both required
forms (`catch $tag $h`, and `catch_all_ref $h` + `throw_ref` for the `finally` path) — and ran it on
`wasmtime 47.0.3`:

```
wasmtime tt_fixture.wat                  -> exit 34
wasmtime -W exceptions=y tt_fixture.wat  -> exit 34
```

34 is `l(33) + finally_ran(1)`, so this is not mere acceptance: the catch handler bound the tag's
params correctly **and** the `finally` body ran before the exception propagated to the outer handler.
The semantics of the replacement shape are sound. `exceptions` is on by default in 47.

We deliberately did **not** hand-assemble a binary fixture — that is the trap that cost you a cycle,
and a malformed fixture proves nothing in either direction. The above went through wasmtime's own
WAT parser.

### The blocker: wabt-ts cannot ENCODE `try_table`

Your Option B premise was *"wabt-ts's WAT parser already accepts `try_table` … so this needs no
wabt-ts change."* The parser does accept it. **The binary writer cannot encode it.** wasic's
pipeline is WAT text -> wabt -> binary -> binaryen, so wabt is unavoidable on that path.

Running our fixture through wasic's exact pipeline (`watToOptimisedWasm`, `src/wasic.ts:205-240`)
fails at step 1:

```
binary writer: unresolved name-var "$__exn_tag" for var - run resolveNames before encoding
  at BodyWriter.beginTryTableExpr (wabt-ts/src/writer/binary-writer.ts:407)
```

It is not the tag spelling, and not one bad form. **Every `try_table` carrying a handler clause
fails to encode** — we tested all of them on wabt-ts 1.3.5:

| form | result |
| --- | --- |
| `(catch $t $h)` named tag | ENCODE-FAIL — unresolved `"$t"` |
| `(catch 0 $h)` numeric tag | ENCODE-FAIL — unresolved `"$h"` (the *label*) |
| `(catch_ref $t $h)` | ENCODE-FAIL — unresolved `"$t"` |
| `(catch_all $h)` | ENCODE-FAIL — unresolved `"$h"` |
| `(catch_all_ref $h)` | ENCODE-FAIL — unresolved `"$h"` |
| `try_table` with no handler | OK |
| `throw_ref` alone | OK |
| **legacy `(try (do …) (catch …))`** | **OK** |

So wabt-ts today can encode *only* the form wasmtime refuses. That is the actual shape of the
problem, and it is why B cannot ship on a wasmtk-only change.

**This is very likely the same defect we already filed with them.** It is the same class as the
`ref.null` encode bug in `scripts/wabt-ts-bug-report.md` — same message, same
"run `resolveNames`" advice, same binary writer, and `resolveNames` is not exposed on either the
`/compat` or `wat2wasm` surface. One fix may well clear both. We have added the `try_table` finding
to that report.

### What this does to the fork

- **Option B — still the right destination.** wasic should emit the modern form directly rather than
  emit a dead form and post-process it. It keeps the pipeline honest and leaves nothing to strip
  later. **Blocked on the wabt-ts encode fix, which is already filed.**
- **Option A — genuinely unblocked, and we are still not asking for it.** It works today: wasic
  emits legacy, wabt encodes legacy (fine), your `TranslateEH` rewrites to `try_table` on the way
  out. But it is ~823 lines to carry a translation step that becomes redundant the moment wabt-ts
  encodes `try_table`, after which wasic emits the right thing at the source. **We would rather not
  ask you to write that.**

**Our call: wait on the wabt-ts fix, then do B.** We will not schedule A.

Two conditions that would change our answer, stated so you can hold us to them:

1. **If the wabt-ts encode fix slips**, A becomes the pragmatic unblock and we will say so plainly
   rather than sit on broken output.
2. **Your "compatibility shim for already-built binaries" argument survives either way.** If you
   want `TranslateEH` for consumers with legacy binaries they cannot rebuild, that is a real use
   case independent of wasmtk — just not one wasmtk needs, so please do not let our timeline drive
   it.

### What we are doing on our side regardless

- The `try_table` migration in `src/wasic.ts` (10 affected modules; sites at 14749/14756/14772/14774)
  is scoped and ready, now marked BLOCKED on the wabt-ts fix instead of startable.
- **Adding a second engine to our EH gate**, which is the part that actually matters. Our suite was
  417/417 green the entire time every one of these modules was unrunnable on wasmtime, because our
  oracle is V8 and V8 still accepts legacy EH. That is the lesson we are taking, and it is the one
  worth propagating: a single-engine gate cannot see this class of defect. Yours found it; ours
  should have.

### One thing to double-check on your side

You noted binaryen-ts "parses, optimizes and re-encodes that faithfully". We could not verify the
converse — that binaryen-ts can **emit** `try_table` — because with wabt-ts unable to encode it and
no `wasm-tools`/`wat2wasm` on this machine, we have no way to get a `try_table` binary *into*
binaryen-ts. Worth confirming before either option is committed to; you have
`test/passes/dwarf_with_exceptions.wasm` and your own writer, so it should be quick on your side.
If binaryen-ts also cannot emit the new form, both options need it and that changes the sequencing
again.
