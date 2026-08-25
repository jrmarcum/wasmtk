# Best Practices — the method rules, extracted from what went wrong

**This file holds METHOD, not findings.** Post-mortems stay in their homes —
[compiler-bugs.md](compiler-bugs.md) for defects, [roadmap.md](roadmap.md) for programme state,
[design-decisions.md](design-decisions.md) for the decisions, [testing.md](testing.md) for how to run
things. What lives here is the transferable part: *how to work on this codebase so the same class
does not recur.*

**Provenance.** Adopted 2026-08-24 from the sibling **wazmrt** project's `cmem/best-practices.md`,
which pioneered the format. Rules marked **[wazmrt]** are imported — they were paid for over there,
and several were then independently re-paid for here, which is exactly why they were worth
importing. Rules marked **[wasmtk]** are ones this project bought itself. Where a rule carries both,
the incident on each side is named.

⚠️ **Read this before a conformance pass, an audit, a backend bump, or any change to a
producer/consumer pair.** Most entries exist because someone competent did the obvious thing.

---

## 1. Verifying a change

**Diff the OUTPUT, not the exit code.** [wazmrt + wasmtk] A run that still exits 0 while silently
dropping passes is a regression. Already the standing rule in the `look for code issues` trigger in
[INDEX.md](INDEX.md).

**Judge a conformance pass by what it RUNS, not by the failure total. Check that no FILE lost
passes — that is the regression test; the total is not.** [wazmrt, then wasmtk] A number that only
ever goes down can be improved by running less. **Independently re-paid for here 2026-08-20:** the
`wast` gate asserted `failed === 0` plus a single global floor (`totalPass >= 10000` against
~12,444), so when a corpus sync took `return_call.wast` from 44 passes to 12, the gate printed
`ALL CLEAN`. The corpus could have shed ~2,400 more passes silently. The fix — a per-file baseline in
`tests/wast_baseline.json` where every file must hit its number exactly — is this rule implemented.
See [testing.md](testing.md).

**Pass counts over a corpus you cannot fully run are UPPER BOUNDS, not measurements. Skips are not
passes.** [wazmrt] Live figure here: the wast gate reads **27,983 passed / 37,252 skipped** — this
corpus still SKIPS MORE THAN IT RUNS. Any headline quoting the first and not the second is overstated
by more than the number itself. (A wabt-ts 1.4.0 bump would cross those two at 37,247 / 27,275; it
was attempted 2026-08-25 and reverted — see compiler-bugs.md.)

**Read the SKIP column in the same row as the failure count — and rank work by ASSERTIONS UNBLOCKED,
not failures closed.** [wazmrt] A file reading `0 passed, 0 failed, 34 skipped` is not healthy, it is
*dark*. **Vindicated hard on 2026-08-25:** `ref_null.wast` sat at 0 passes / 34 skips because wabt-ts
could not encode `ref.null` at all; the 1.4.0 fix moved the WHOLE CORPUS by **+9,264 passes and
−9,977 skips**. One toolchain fix lit up ten thousand assertions, and it had been sitting behind a
column nobody gates on. **An item whose symptom is a SKIP cannot be sized from the failure column at
all.**

**Do not FILTER output and then trust the filtered view — it is how a measurement lies to you.**
[wasmtk, 2026-08-24] Twice in one session: `deno run tests/wasi_tests.ts | grep -E "Passed|Failed" |
head -3` matched the suite's per-phase `✅ … Passed:` chatter and cut the 417/417 summary off
entirely, so the number most needed was discarded by the reader; and `wasmtk convert bad.wat | tail`
followed by `$?` reported **tail's** status, not wasmtk's, which nearly fabricated an exit-code
finding out of nothing. **Read the tail unfiltered, and use `${PIPESTATUS[0]}` — or do not pipe at
all when the exit code is the measurement.**

**Re-measure before quoting any number.** [wazmrt + wasmtk] Counts go stale silently, and a stale
number is worse than none because it reads as current. **wasmtk's own version of this rule is
stronger and predates this file:** regenerate the corpus before validating against another runtime,
or a stale artifact is a false positive ([testing.md](testing.md)). It earned its keep on 2026-08-24
— regenerating first is what proved a sibling project's `KNOWN_INVALID` list stale rather than
confirming it.

**A CARET RANGE PLUS A LOCKFILE IS NOT A PIN — it is a pin until someone reloads.** [sibling
project, then wasmtk the same day] Arrived as a report from the binaryen-ts side, and we were sitting
in it: `deno.json` asked `^1.3.5` for wabt-ts, the lock held 1.3.5, and JSR had published 1.4.0 —
which the caret accepts. Deleting one config line was enough to let a reload pull 1.4.0 in, and the
`wast` gate went **156 files off-baseline** while `deno.json` still read "1.3.5". Harmless until then
only by luck of timing.

**The distinction that matters is WHY the constraint exists.** Most ranges express *compatibility*,
and a lockfile is the right home for that. A few express *correctness* — "our code is bug-compatible
with exactly this version" — and those belong in the **specifier**, where a reload cannot move them.
Ours was the second kind written as the first: wabt-ts 1.4.0 is a stricter validator that regresses
our suite, so `1.3.5` is now an EXACT pin (no caret) until the three malformations it exposes are
fixed. `binaryen-ts` stays on a caret — that one really is a compatibility range.

**The tell:** ask what `--reload` would do, then ask again imagining the next upstream release as
already published. If the answers differ, the range is doing work a lock cannot.

**Reinstall before testing.** [wasmtk] The suites invoke the globally-installed `wasmtk`, so after
editing anything in `src/` or `deno.json` you MUST run `deno task install` or you are testing the old
binary. Never hand-write the `deno install` line — `--allow-ffi` is required.

## 2. Investigating a defect

**Before debugging a toolchain failure, prove it is yours: rebuild the UNMODIFIED commit.**
[wazmrt + wasmtk] A one-command falsification is worth more than any amount of reading the diff you
already believe in. **Used here 2026-08-20:** three Go suites went red during a session that had
touched `src/wast.ts`. Reverting that one file to HEAD reproduced the failure exactly, reclassifying
it in one step from "what did I break" to "what broke around me" — Go 1.27 had been installed that
morning and TinyGo 0.41.1 caps at 1.26.

**Identify the LAYER before naming a cause.** [wazmrt + wasmtk] Each layer has its own cheap query,
and the cheapest is often never run. **Used here 2026-08-24** on the `wast` runner OOM: parser →
assembly → instantiate → the `module quote` path, each tested in isolation. The first three were fine
at 6–7 MB; the fourth died. Without that split, the "obvious" conclusion — a memory-lifetime redesign
around instantiated modules — was the one already written down, and it was wrong.

**A prediction in a scoping note is not a diagnosis.** [wasmtk, 2026-08-24] The runner OOM was sized
**L** with "likely instantiated modules and their `WebAssembly.Memory` buffers … a lifetime
redesign". It was two discrete bugs: an infinite loop in our own S-expr reader on a lone `;`
(~1.9 GB), and a wabt-ts `parseWat` blow-up on `(ref (exact any))` — **50 characters → 4 GB**. With
ours fixed, 287 files peak at **52 MB**. There is no creep. Write the guess down as a guess, and
delete it the moment measurement lands.

**…and the same applies to a prediction about the FIX, not just the cause.** [wasmtk, 2026-08-24]
The `boolexpr` double-evaluation was filed as needing "a spare local plumbed through the emitter",
which is why it was deferred out of the `fd_write` change as too invasive. It needed **no local at
all** — one statement-form `if` with both stores inside each arm evaluates the operand once, and is
simpler WAT than what it replaced. A cost estimate written before opening the code deferred a
20-line fix on the strength of an imagined one. Size it when you look, not when you file it.

**A partial fix that measures as insufficient must be recorded as partial, loudly.** [wasmtk]
Hoisting the per-file WABT instance to a process-wide singleton was correct and did not stop the OOM.
Recording it as "the fix" would have sent the next reader looking in the wrong place; recording it as
"real but NOT sufficient — most retention is elsewhere" is what kept the investigation open.

## 3. Producer/consumer pairs — the recurring blind spot

wasmtk sits in a three-project triangle with **wabt-ts** (assemble) and **binaryen-ts** (optimise),
and ships output to third-party engines. Almost everything here is about that boundary.

🚨 **A round-trip proves agreement with YOURSELF. When a bug can only be seen by a third party, the
test has to BE a third party.** [wazmrt, then wasmtk — the sharpest shared lesson] **Re-paid for here
2026-08-24 in the most expensive possible way:** every TypeScript `try`/`catch`/`finally` compiled to
the *legacy* exception-handling proposal. wabt-ts parsed and re-encoded it faithfully, V8 executed it
correctly, and the wasi suite was **417/417 green** — while all 10 affected modules were rejected
outright by wasmtime, the host WASI names. The corpus was blind by construction. Only putting the
bytes to a different engine could see it, and that is what the sibling project did.

**Two consumers agreeing is not corroboration when they share the mistake.** [wazmrt] Count the
implementations of a rule before trusting they check each other. Our oracle was V8 in *both* the wasi
runner and `wasmtk wast` — one engine wearing two hats is one data point, not two.

**A workaround in the producer for a gap in the consumer does not stay cosmetic.** [wazmrt] Live
decision this bears on: `wasic` emits legacy EH and wabt-ts cannot encode `try_table`. The available
shortcut is to keep emitting the dead form and post-process it downstream. Fix the gap; don't route
around it.

**A stale vendored snapshot is indistinguishable from live data unless something records its
provenance.** [wasmtk — twice in one week, in BOTH directions] `proposals/threads/` in the spec
testsuite still asserts "multiple memories" is invalid; that is upstream's frozen 2020 snapshot, not
local drift, and a downstream project filed it against us as a stale corpus. Days later a sibling
filed seven modules as "genuinely invalid" from *their* frozen 272-file copy of our corpus — all
seven run clean today. **Neither was carelessness.** The fix is mechanical: pin the upstream SHA and a
re-sync recipe next to the vendored copy ([testing.md](testing.md)).

**A `KNOWN_*` list that asserts a thing STAYS broken inverts its own purpose the moment the thing is
fixed.** [wasmtk, from the sibling's incident] Theirs was designed to shrink as our codegen improved;
frozen against old bytes it passes for the wrong reason and masks the fix. Applies directly to our
own baseline entries pinned at 0 — those are safe only because `--update-baseline` re-measures them.

**A claim about ANOTHER project's code is a HYPOTHESIS until you open their source and grep for it.**
[wazmrt, then wasmtk] wazmrt bought this when an adoption ledger's "Benefit" line — *loaders bind
once to a familiar ABI* — turned out to be false; the loaders used a different API entirely, and
nobody had checked. **Re-paid for here 2026-08-24, in both directions in one day:** a sibling's
report asserted *"wabt-ts's WAT parser already accepts `try_table`, so this needs no wabt-ts
change"* — the parser does; the binary writer cannot encode any handler form, which inverted their
whole recommendation. The same day, their list of seven "genuinely invalid" modules turned out to run
clean. **Both reports were careful and both were partly wrong, because the checkable half was
assumed.** Verify inbound claims before acting, and expect the same of ours — mark what you measured
and what you inferred, so the other side knows which half to check.

**Never green-wash our own gaps; a well-argued entry in a baseline is still an entry.** [wazmrt] The
alternative to fixing a class is a permanent "known deviation" nobody re-examines, which hides the
next genuine failure in the same file. That argument arrived here from a downstream consumer on
2026-08-20 and it was right.

## 4. Tests and gates

**A new test that has never failed has not been shown to test anything.** [wazmrt + wasmtk] **Applied
here 2026-08-20:** before committing the per-file baseline gate, its baseline was deliberately
perturbed in both directions (one file +5, one −3) to confirm it reported LOST and GAINED coverage
and exited non-zero. A gate that cannot fail is not a gate.

**A CHANGE'S OWN NEW SURFACE IS THE ONE PLACE THE AUDIT THAT PRODUCED IT WILL NOT LOOK.** [wazmrt]
The new gate's own `--update-baseline` path is exactly such a surface — it is the part that OOMed
after the gate itself was working.

**A goal with no gate is a preference, and a gate with no trigger is a preference too.** [wazmrt]
wasmtk's trigger is written down in [INDEX.md](INDEX.md): a CHANGE fires the full suite set, not a
batch. Know which one you are in.

**Design the gate so an IMPROVEMENT also fails.** [wasmtk, 2026-08-20] Files pinned at 0 passes —
like `ref_null.wast` — exist so that the day a backend learns to encode `ref.null`, the gate *says
so* rather than absorbing the win silently. This will look like a regression during a version bump;
it is written down in [next-work.md](next-work.md) so nobody has to diagnose it live.

**Prefer a self-discovering list to a hand-maintained one.** [wasmtk] `--update-baseline` finds
unrunnable files by chunking across subprocesses and retrying a dead chunk file-by-file, because a
hardcoded skip list goes stale exactly like the `KNOWN_*` lists in §3. An OOM cannot be caught
in-process, so a single-process scan is one bad file away from losing every result.

**Assert forward progress structurally, not per-symptom.** [wasmtk, 2026-08-24] The S-expr reader
stalled on a lone `;` because `readAtom` stopped without consuming it. The fix was not "handle `;`" —
it was "any character `readAtom` cannot consume is taken as a one-character atom", so the loop can
never stall on a future one.

## 5. Recording what you found

**"Update the project memory" means AUDIT for stale live claims, not edit the files you happened to
touch.** [wazmrt] The audit that works is a grep for the OLD VALUES, then classifying every hit as
live (fix) or dated history (leave, and mark it superseded if it claims to be current). Watch for
"final" and "the number to quote" — both tend to appear on figures superseded within days.

**When two files disagree, do not pick the newer one — measure.** [wazmrt]

**Record findings that were WRONG so they are not "fixed" again — and note that a retraction
re-checks the REASONING, not the REQUIREMENT.** [wazmrt + wasmtk] **Used here 2026-08-24:**
[compiler-bugs.md](compiler-bugs.md) carries a visible correction where an earlier entry blamed
"typed function references `(ref null $t)`" — the real gap was the `ref.null` *instruction operand*,
and two of the three items turned out to be parity with upstream wabt rather than wabt-ts bugs. The
retraction is visible rather than a silent overwrite, so the next reader sees the claim was withdrawn
and why.

**Before scoping work, grep for the thing you are about to build.** [wazmrt] A status line written
from an ARGUMENT rather than from the code costs time in both directions — recording work as TODO
that already exists, or as DONE when it is not.

**Say which claims are live and which are as-triaged.** [wazmrt] Per-item counts are accurate when
written and stale as soon as the next item lands. Mark them.

**A write that truncates BEFORE it can fail will eat the file.** [wasmtk, 2026-08-24] Editing a
`cmem` file with `open(path, "w").write(text)` truncates on open, so an encoding error raised by
`write()` leaves **zero bytes** — `next-work.md` went from 347 lines to 0 because a string held an
emoji as a surrogate pair. Nothing was lost only because the content was still in `HEAD` and
`git checkout HEAD -- <file>` restored it. **Encode first, write to a temp, then `os.replace`.**
The general form: any edit whose failure mode is *destructive rather than a no-op* needs the
destructive step to happen last. ⚠️ This is sharper for `cmem/` than for source — project memory
is often the only copy of a decision, and an uncommitted memory edit has no other home.

**Name the blast radius of a guarantee you cannot currently meet.** [wasmtk, 2026-08-20] When three
Go suites could not run, the useful record was not "3 suites red" but "'ran the ENTIRE suite set'
carries a three-suite asterisk on this machine, including in today's commit messages".
