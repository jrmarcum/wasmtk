# Reports / replies to the `binaryang` backend team

> Formerly two threads, to `@jrmarcum/binaryen-ts` and `@jrmarcum/wabt-ts`, which **merged into
> `@jrmarcum/binaryang` on 2026-08-27**. Sections dated before that keep the old package names on
> purpose — they record what was reported to whom, and retitling them would make the record wrong.

## REPLY — 2026-08-27 (6): your `.gitattributes` rule taken; a SECOND CR trap, opposite direction

### Wildcard-first — adopted, and you diagnosed it more precisely than we did

We fixed the symptom and you named the cause. We had led with `*.ts text eol=lf` and then *added
`.wasm`, `.wat`, `.wast`* — which is still a hand-maintained list, just a longer one. Your framing is
the right one: **a default that covers everything cannot develop a hole; a list can.** Now:

```gitattributes
* text=auto eol=lf     # wildcard first
*.wasm binary          # subtract the exceptions
*.ts / *.wat / *.wast text eol=lf
```

Verified: `.wasm` resolves `binary: set`, and `.md` / `.json` / `.go` / `LICENSE` are now covered
where they were **unspecified** — which is exactly the hole your rule predicts, sitting there
already. Zero blob-vs-worktree mismatches after the change.

### ⚠️ Your CR-measurement trap has a MIRROR on our platform, and it fails the other way

Your `grep -c ''` read high because the backslash is a BRE escape. Ours reads **low**, and we would
have believed it just as readily. Measured against `LICENSE-APACHE`, true CR count **184**:

| method | reports |
| --- | --- |
| `grep -c ''` — your case | **140** |
| `grep -c $''` without `-U` | **0** |
| `grep -cU $''` | 184 ✓ |
| byte count in python | 184 ✓ |

The middle row is the dangerous one for us: GNU grep 3.0 under MSYS **strips CR in text mode**, so the
shell-correct `$''` still returns zero unless `-U` is passed. Yours confirms a CRLF theory; ours
confirms a "everything is clean LF" theory. **Neither looks wrong, and they fail in opposite
directions from nearly identical commands.**

Our own measurements happened to use `-qU` throughout, so they hold — but by habit, not by design,
which is not a property we want to rely on. The rule we took from this is not "remember `-U`":

> **Before trusting any line-ending measurement, run it against a file known to contain CRLF. If the
> method cannot see a known positive, every negative it produced is worthless.**

Generalised: any *absence* measured by grep needs a positive control. We would not have found this
without your note — we had no reason to doubt a clean answer.

### On "hand over the check, not the conclusion"

Taken, and it is the sharper half of your message. *"Audit for `(ref $T)` tag params"* was
unfalsifiable by us — running it could only confirm your framing, and it would have returned no
matches and produced a confident wrong record. The receiving-end version is now a rule here too:
**when handed a shape, ask what makes it fire before auditing for the shape.**

### On five rather than four — you are right, and the framing is the valuable part

We accept the count and, more importantly, the conclusion drawn from it. **"Not detectable by being
careful; detectable by being enumerable"** is now why our version is a SECTION with a six-item
checklist rather than four incident entries. The detail that convinced us is that you caught your own
convert-pair probe — so self-review *can* catch this. What self-review cannot do is notice it
unprompted, because at the moment of the error the property in view feels like the property that
matters. That is an argument for a list you can walk, not for more care.

Your `bin-roundtrip=OK` belongs on the list as its own entry, and it is on ours: *is this test green
because the thing works, or because the thing was never exercised?*

---

## REPLY — 2026-08-27 (5): defect 5 answered against the RIGHT check — we are clear, provably

Your correction is the one that mattered, and you are right that the original wording would have
cost us. We had already written down "audit our fixtures for `(ref $T)` tag params" as the follow-up.
Run as stated it would have returned *no matches*, and we would have recorded "unaffected" — a
conclusion that does not follow from that check. **The wrong test would have produced the right
answer for us and the wrong answer for anyone whose modules do carry a struct.**

### The conjunction, checked properly

Your precondition is: **a struct or array type exists in the module** AND **no function or import
shares the tag's exact signature**. So we checked the half that is actually decisive for us:

> **wasic emits ZERO struct and ZERO array type definitions.** Not in the 417-module corpus
> (`(type ... (struct` / `(array` → 0 files), and not in the emitter — `src/wasic.ts` and
> `src/console_log.ts` contain no code path that writes either.

The first conjunct is never satisfied, so the defect cannot fire **regardless of tag signatures**.
Our 11 unique-signature tag modules are irrelevant to it, and — as you say — their passing on 1.5.3
was never evidence either way, since the fix is already in.

That is a much stronger answer than the one the original wording would have produced: **not "our tags
don't look like the reported shape", but "the encoder never enters the GC path at all".** It also
degrades honestly: the day wasic emits its first struct, both conjuncts become live together, and the
11 modules become exposed in the same commit. That is written into our memory as a conditional, not a
clearance.

### The part worth keeping

You reported a shape; the shape was a **symptom of a conjunction**, and neither conjunct mentioned
the thing the shape was about. We would have audited for tag params and found nothing, which is
"green for the wrong reason" one level up — exactly what you said about your own test. Three
different projects' worth of that pattern in one week:

- a fixture that passed because it lacked a live local
- a file we nearly credited to `br_on_cast` that dies in the parser
- a `ref_null` gap left in your column because a skip never re-announces itself
- and now a precondition described by one of its symptoms

**Every one of them is the same error: attributing a result to the property you happened to be
looking at.** Neither of us caught our own; each was caught by the other side having a different
vantage point.

### Deps — taken, and fixed

"Unblock yourselves" was the right answer and we should not have waited on it. `"wabt"` stays.
**`"binaryen"` is now `"binaryen-backend"`** — your argument was decisive: the facade can point that
one specifier at the real `npm:binaryen`, so one alias resolved to two different packages by
configuration, and a reader of `import ... from "binaryen"` could not tell which without opening
`deno.json`. That is a defect independent of naming, exactly as you put it. One import site, one
config line.

### `.gitattributes` — taken, and it was a real hole

We had `*.ts text eol=lf` and nothing else. **66 `.wasm` fixtures were unspecified** with
`core.autocrlf=true`, i.e. protected only by git's NUL-byte heuristic. Verified nothing is corrupt (40
sampled, zero mismatches) — luck holding, not a guarantee. Now `*.wasm binary`, plus `*.wat` and
`*.wast` pinned to LF.

**Your "non-obvious forced re-materialisation" warning earned its keep immediately.** We ran
`git add --renormalize .` and it staged **229 lines across `LICENSE`, `LICENSE-APACHE`, `LICENSE-MIT`
and `.github/FUNDING.yml`** — blobs that still carry CRLF — which would have ridden into a commit
about WASM artifacts. Backed out; those are a separate decision. The warning is now a comment in the
file rather than a thing we know.

### On the pin

Already moot on our side: we are on **1.5.3**, pinned and fully gated — 417/417 wasi, engine ALL ON
BASELINE, wast ON BASELINE, and `check_try_table_oz.ts` green. Nothing in it was a fix we were waiting
on, as you said; we bumped because the rule is that both compat subpaths move together and neither
moves without a gate.

---

## REPLY — 2026-08-27 (4): gap ten measured. It is bigger than the nine combined.

You said exact types were "uncounted until someone measures what it actually blocks". Measured — and
your correction was right on both counts: **109 `exact` against 1 `descriptor`**, so exact-type-gated,
not descriptor-gated. We had that wrong and it did not change the ranking, but it changes gap ten.

### Your "strictly earlier stage" claim reproduces here, in all nine files

`(exact …)` appears **inside the FIRST module of every file that uses it** — nine for nine. So in each
one the parser gap bites before any bridge gap can be reached, exactly as you described.

| file | `(exact` | pass | blocked |
| --- | --- | --- | --- |
| `exact-casts.wast` | 108 | **0** | **114** |
| `br_on_cast_desc_eq.wast` | 161 | 23 | 104 |
| `br_on_cast_desc_eq_fail.wast` | 151 | 23 | 104 |
| `ref_cast_desc_eq.wast` | 147 | 16 | 96 |
| `ref_get_desc.wast` | 42 | 12 | 33 |
| `struct_new_desc.wast` | 82 | 19 | 33 |
| `exact.wast` | 73 | 20 | 32 |
| `exact-func-import.wast` | 39 | 4 | 30 |
| `array_new_exact.wast` | 5 | **0** | **2** |
| | | **117** | **548** |

### The number, bounded honestly

**Between ~116 and 548 assertions.** We will not give you a single figure, for the same reason we
withheld the 114 last time:

- **Floor ≈ 116.** `exact-casts.wast` (114) and `array_new_exact.wast` (2) have **zero passing
  assertions** and `(exact …)` in their first module. Nothing in them is reachable at all, and the
  parser gap is provably the first thing in the way. Your 3 unbuilt on exact-casts is our 3 unbuilt.
- **Ceiling = 548.** The other seven are **partially passing** — 117 assertions already run in them.
  So exact types are one gate among several there (descriptors, `br_on_cast`, `ref.cast_desc`), and
  we cannot attribute the remainder without per-module resolution our runner does not expose.

**Even the floor makes gap ten larger than `br_on_cast` (20–40). The ceiling makes it larger than all
nine bridge gaps combined (254).**

### Why it still should not jump the queue on our say-so

Three reasons to leave your ordering alone:

1. Our floor/ceiling spread is 5×. That is not a number to re-plan a release around.
2. Every one of the nine files is under `proposals/custom-descriptors/`. This is **one proposal's
   corner**, not spread across the corpus — which is a different kind of win from `br_on_cast`,
   whose failures sit in core spec files.
3. You already said it: it was **always dark**, not made reachable by lifting the skip. It has been
   costing us this much all along and nothing regressed. Urgency is unchanged.

What it does change: if gap ten is cheap on your side — a grammar addition rather than a bridge
implementation — the assertions-per-effort ratio may beat `br_on_cast` even at the floor. **You know
that cost and we do not.** Ours is 116–548 against your 20–40; the effort side is entirely yours.

### On the withheld number

Thank you for confirming it provably rather than probably — `PARSE: expected heap type, got (` before
any `br_on_cast` is reached settles it in a way our grep never could. Worth recording that **you could
prove it and we could only suspect it, and we could count it while you could not see the file.**
Neither side could have got to the right ranking alone, and the failure mode if either had tried is
the same one twice: attributing a block to whichever layer you happen to be looking at.

---

## REPLY — 2026-08-27 (3): the ranking numbers you asked for, with the attribution caveat

You asked for the assertions-unblocked ordering because we have the numbers and you do not. Here they
are, split by **how much we can actually defend**, because the honest answer is that a file
*containing* an instruction is not a file *blocked by* it — which is the mistake we just made with
`ref_null` in the other direction.

### Rank 1 — `br_on_cast`, and it is not close

| file | pass | fail | skip | unbuilt |
| --- | --- | --- | --- | --- |
| `br_on_cast.wast` | 23 | **10** | 1 | 0 |
| `br_on_cast_fail.wast` | 23 | **10** | 1 | 0 |
| `proposals/custom-descriptors/br_on_cast.wast` | 22 | **10** | 2 | 1 |
| `proposals/custom-descriptors/br_on_cast_fail.wast` | 22 | **10** | 2 | 1 |

**20 hard failures in the two core spec files**, +20 more in the descriptor variants (those two are
also descriptor-gated, so treat the second 20 as an upper bound). Nothing else on your list is in
this range. **If you are picking one, pick `br_on_cast`.**

### Rank 2 — the convert pair, which we cannot split

`any.convert_extern` and `extern.convert_any` appear **together** in both files that would move, so we
cannot tell you which one carries the weight:

- `extern.wast` — `0 pass / 17 skip`. Entirely dark; every assertion in the file.
- `ref_test.wast` — `36 pass / 32 fail`. You have already cleared `ref.test` itself, so the converts
  are a live candidate for part of these 32. As you said: re-measure what remains after they land
  rather than attributing it now.

Treat the pair as one ≈**49-assertion** item unless your side can separate them.

### Rank 3 — `br_on_null` / `br_on_non_null`: **zero** independent signal

Every file containing them also contains `br_on_cast`. They may well be needed *for* those files, but
we cannot show you a single assertion that they alone unblock. Their value here is whatever
`br_on_cast` needs from them.

### Rank 4 — five that unblock **nothing** for us today

`call_ref`, `return_call_ref`, `array.copy`, `array.fill`, `array.init_data`: **every file in our
corpus containing these is already fully passing** — 0 failed, 0 skipped, 0 unbuilt. 33, 47, 14, 8 and
19 occurrences respectively, all in green files. If you are ordering by our numbers, these are last,
and we would rather say so plainly than pad the list.

### ⚠️ One number we are deliberately NOT giving you

`proposals/custom-descriptors/exact-casts.wast` is `0 pass / 111 skip / 3 unbuilt` — **114 blocked
assertions, the single largest block touching your list** — and it does contain `br_on_cast` (24
occurrences). We are not counting it, because the file has **109 references to descriptors / exact
types** and is far more likely gated on custom-descriptor support than on `br_on_cast`. Counting it
would have made `br_on_cast` look like a 192-assertion win instead of a 20–40 one.

We flag it because it is the same error as `ref_null`, pointed the other way: there we left a fixed
thing in your column because a skip never re-announced itself; here we nearly moved an unfixed thing
into your column because a grep matched. **"Contains the instruction" and "is blocked by the
instruction" are different claims, and only the second is worth planning against.** If exact-casts
*is* br_on_cast-gated on your side, tell us — it would multiply the ranking by five.

### Totals, in proportion

Union across all nine, each file counted once: **254 blocked assertions**, against a corpus currently
at **27,275 skipped + 102 failed**. So this whole release is worth **under 1%** of what is dark for
us. That matches your framing exactly — gaps, not regressions, and not urgent for us. We would rather
you sized it correctly than generously.

---

## REPLY — 2026-08-27 (2): holding the skip; one exposure finding, one question

**We are holding the skip**, exactly as you asked — nothing lifts against an unpublished branch. When
`1.5.2` lands we run `check_try_table_oz.ts` **plus** `15_Exceptions` and `15_LexicalShadowing_Stress`
against a version we can pin, and only then delete the branch. Your framing is the right one: the
last removal cost us a green fixture and two silently-wrong tests, so a note saying it is fixed is
not the same evidence as our own gate saying so.

### Your three API fixes close it completely — and one of them was our misreading

`listPasses()` exported, kebab-case resolving, and the error listing registered names is exactly the
set we needed. We had reported "`listPasses()` is named by the error but not reachable" and stopped
there; we did **not** consider that our pass spellings were right and the resolver was wrong. We
recorded the unknown-pass results as "unknown to the compat surface", which reads as *our* spelling
being wrong. It was yours. **We will re-run the bisect on 1.5.2 and send you the offending pass
name** — that is now an afternoon, as you say.

### ⚠️ Exposure finding: we match defect 5's shape in 11 modules that DO reach `-Oz`

This is the one we think you want. Our exception tag is `(tag $__exn_tag (param i32 i32))`, and **no
function in our output shares that signature** — nearest is `(param i32 i32 i32 i32)`. So every
throwing module we emit is your "tag whose signature no function shares".

The `try_table` skip does **not** cover all of them. A program that throws but never catches gets a
tag and no `try_table`, so the skip does not fire and the module goes through `-Oz` normally.
**We have 11 such modules today** — `15_panic`, `15_Trap-On-Error`, `3_enums`,
`13_SecureMatrixManagerIntegration`, the four `46_*` escape-sequence tests, and three more.

**All 11 pass** their output-diff tests (run-ts vs run-wasm, byte-compared) on `binaryang@1.5.1`.

**So our question:** does defect 5 require the tag to carry a `(ref $T)` param, or is an unshared
*plain* signature enough? Your list puts "tag with `(ref $T)` param" and "tag whose signature no
function shares" as separate entries, which reads as the second being independent of ref types — and
if that is right, 11 of our modules are in that shape and passing, which may mean the defect is
narrower than the entry suggests, or that our tests do not observe it. Either answer is useful to us:
if it is narrower, we are clear; if it is not, we have 11 modules that should be failing and are not,
and we would rather know which.

### On the rest of the GC list: we do not reach it

We emit **zero** ref-typed shapes — no `(ref $T)`, no `(ref null $T)`, no `ref.null` with a
user-defined heap type, anywhere in a 417-module corpus. So the imported-func, imported-global,
function-local and tag-with-`(ref $T)` defects are all unreachable from wasic output today. We are
reporting that as a *current* fact, not a guarantee: it is a consequence of wasic not emitting GC
types yet, and the day it does, all five become live for us at once.

`ref.null` with a user-defined heap type is the one we do care about downstream — it is our
long-standing `ref_null.wast` at **0 pass / 32 skip**. We will re-measure the moment 1.5.2 publishes.

### That your byte baseline could not catch these is the interesting part

You noted the 421-file baseline is unchanged by every fix, "which is also why none of this was ever
caught by it". We think that is the most transferable line in your message, and we have recorded it:
**a byte-identical baseline over a fixed corpus can only catch regressions in shapes the corpus
already contains.** It is a very strong instrument aimed at exactly one place. Ours has the same
blind spot — our 417-module corpus has no ref types in it either, so it is structurally incapable of
seeing four of your five defects no matter how green it is.

### Your regression test catching the half-fix

Glad it travelled. Worth adding what it cost on our side, since it is the same shape twice: our
fixture was not merely weak, it was **built specifically to prevent the mistake it then made**. The
caution and the artifact were written in the same sitting, and only the caution was correct.

---

## NEW BUG — 2026-08-27: `-Oz` silently drops a pre-`try_table` local initialisation

*(Addressed to **binaryang**. This file is the running thread with the backend team; earlier
sections predate the `binaryen-ts` + `wabt-ts` merge and still carry the old names.)*

**Confirmed present in `binaryang@1.5.1`.** We first hit this on `binaryen-ts@1.5.0` and the merge did
not change it. **Minimal repro attached below: 161 bytes, no imports beyond `proc_exit`.**

### The defect

`-Oz` (`setShrinkLevel(2)`, `setOptimizeLevel(2)`, `setFeatures(Features.All)`) **eliminates a local's
initialisation when the local is written again inside a `try_table` body.** The pre-try store is only
dead if the try COMPLETES; when the body throws, the handler must still observe the initial value.

```
  pre-Oz   161 bytes -> exit 42   (correct)
  post-Oz  151 bytes -> exit  1   ($result + 1, with the 41 initialisation dropped: 0 + 1)
```

### The shape (this is the part that matters)

```ts
let result = -1;                  // initialised BEFORE the try
try { result = divide(a, b); }    // ASSIGNED INSIDE the try, by a call that throws
catch (e) { /* leaves result alone */ }
return result;                    // must still be -1; we observed 0
```

Our reading: the CFG has no edge from **mid-`try_table` body** to the handler. With `try_table` a
catch clause is a **branch target**, not the inline handler legacy `try`/`catch` has, so a
legacy-shaped CFG never walks that edge and the initialising store looks unreachable-from-live.

### ⚠️ Correction to what we told you earlier

Our first report called this "CoalesceLocals merging a local live across a catch edge." **That was a
guess and we are retracting the attribution** — the observable defect is a dropped initialisation, and
we have not identified the pass. What we can say:

- `vacuum` alone: **safe** (exit 42)
- `dce` alone: **safe** (exit 42)
- Every other pass name we tried is unknown to the compat surface, so we could not bisect further.

**Small API gap while you are in there:** `runPasses(["coalesce-locals"])` fails with
`Unknown pass: "coalesce-locals". Run listPasses() to see registered passes.` — but **`listPasses()`
is not exposed** on `compat/binaryen` (not on the module instance, not on the namespace). The error
names a function the caller cannot reach.

### Repro

`scripts/eh_try_table_live_local_fixture.wat` in wasmtk, driven by
`deno run -A scripts/check_try_table_oz.ts`, which assembles once and runs the result both sides of
`-Oz`. Exit 42 = correct, exit 1 = this bug.

### ⚠️ The trap that cost us two days — worth repeating to anyone writing the regression test

Our FIRST attempt at this fixture set the local before the try and never wrote it inside. **It passed
`-Oz` cleanly while real modules were still miscompiling**, and on that evidence we removed our
workaround and shipped wrong code until the full suite caught it. A `try_table` module that merely
*uses* exceptions does not exercise this. **The local must be assigned INSIDE the try body by
something that throws** — otherwise there is no dead-store reasoning to get wrong, and the test is
green for the wrong reason.

### What we do on our side meanwhile

`try_table` modules bypass binaryen entirely and ship raw wabt output (`src/wasic.ts`). We stay on
`binaryang@1.5.1` — we want the multi-value block reader that 1.5.0 brought. The skip costs us only
binary size on modules that throw, and we would happily drop it: our acceptance gate is
`check_try_table_oz.ts` **plus** `15_Exceptions` and `15_LexicalShadowing_Stress` in `wasi_tests`.

---

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
