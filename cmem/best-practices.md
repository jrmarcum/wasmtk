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
passes.** [wazmrt] Live figure here: the wast gate reads **37,370 passed / 27,154 skipped**
(re-recorded 2026-08-27 after `ref.null` support; binaryang 1.5.3). **The two crossed over** — this
corpus used to skip more than it ran (27,983 / 37,252 on 1.3.5). The prediction that a bump would
cross them was right, and the bump LANDED — an earlier 1.4.0 attempt was reverted, 1.4.1 was not.
Any headline quoting passes without skips is still overstated by more than the number itself.

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
Ours was the second kind written as the first. **Both backends are now EXACT pins**, and since
2026-08-27 they are one package: `@jrmarcum/binaryang@1.5.3`, reached through `compat/wabt` and
`compat/binaryen` at the same version. The caret came off binaryen-ts too — "that one really is a
compatibility range" did not survive contact with an optimiser that silently miscompiles.

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

**A hang is a MEASUREMENT before it is a mystery — read the CPU time.** [wasmtk, 2026-08-25] A
process pinned near 100% CPU is spinning; one at ~0% is blocked on I/O. They are different bugs with
disjoint suspect lists, and the check costs one command
(`Get-Process deno | Select Id,CPU,StartTime`). **Paid for here:** a `wasi_tests` run appeared stuck;
the two live processes showed 1146s and 540s of CPU against roughly the same wall-clock. That single
reading killed the plausible "blocked waiting on stdin" theory outright and reframed it as a loop —
which is what memory corruption looks like from the outside. Do not infer a hang's nature from where
the log stopped.

**Check whether the suspect code is REACHABLE from the failing input before bisecting it.**
[wasmtk, 2026-08-25] The freshest, most invasive change is the intuitive culprit and it is often
innocent. The `try_table` EH migration had landed hours before the hang, in the same pipeline — but
`grep -c 'try\|catch'` on the two hanging modules returned **0**, and their WAT contained no
`try_table`. One grep, before any bisect, moved the search to the actual variable (the backend bump).
Reachability is cheaper than bisection and strictly more conclusive.

**When a text-parsing fix is correct but the symptom persists, the bug has SIBLINGS — grep, don't
re-derive.** [wasmtk, 2026-08-25] Three folded-only `(i32.const N)` regexes were fixed in
`wasmmerge.ts`; the module still failed with the identical symptom. Three more lived in
`wasmbundle.ts` and `wasic.ts`. The second round of debugging was pure waste — a single
`grep -rn -F '\(i32\.const' src/*.ts` enumerated all six up front. This is the
**parallel-code-paths** warning in `CLAUDE.md` in its most expensive form: when you fix a pattern,
search for the pattern, and make the search's empty result the acceptance criterion.

**Parsing generated text: a no-match must be distinguishable from a legitimate empty result.**
[wasmtk, 2026-08-25] A regex that hard-codes a formatter's choices does not throw when the formatter
changes — it returns "nothing found", which every caller reads as valid. Here that meant "this module
has no data segments", which disabled relocation, seated the heap inside static data, and surfaced
two layers away as an infinite loop. If a scan over a non-empty input yields zero matches, that is a
defect signal, not a value.

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

**A green baseline proves nothing about shapes the corpus does not contain — coverage of INPUTS is a
separate axis from strictness of COMPARISON.** [binaryang → wasmtk, 2026-08-27] binaryang's 421-file
byte-identical baseline was unchanged by every one of six real defects, "which is also why none of
this was ever caught by it". A very strict comparison over a narrow corpus reads as reassurance it
has not earned. **Ours has the identical blind spot:** the 417-module corpus contains no ref types,
so it is structurally incapable of seeing four of those five defects no matter how green it reads.
Before trusting a baseline, ask what shapes it *contains*, not how tightly it compares them.

**When a lookup rejects your input, "my input is wrong" and "their lookup is wrong" are BOTH live —
do not record the first as fact.** [wasmtk, 2026-08-27] We tried `runPasses(["coalesce-locals"])`,
got `Unknown pass`, and wrote it down as "unknown to the compat surface" — phrasing that quietly
blames our spelling. The spelling was right; their resolver was wrong (their compat layer emulates
`npm:binaryen`, where kebab-case is what the docs specify). The cost was abandoning a pass bisect
that would have named the defect in an afternoon. An error message is a claim by the other side, not
a verdict on you.

**Do not lift a safety measure on an upstream's word that it is fixed — wait for a version you can
pin, then re-run your own gate.** [binaryang + wasmtk, 2026-08-27] Fixes existing on an unpublished
branch are not a thing you can pin, roll back to, or hand a colleague. Upstream said this plainly
themselves — *"we'd rather you re-verified than took this note's word for it"* — which is worth more
than the fix. The prior removal of this same skip was authorised by evidence that felt equally
solid.

**A fixture that proves a FEATURE works does not prove an OPTIMISER is safe — never lift a safety
skip on one.** [wasmtk, 2026-08-25] `scripts/eh_try_table_fixture.wat` was written to show
`try_table` survives the pipeline, and it does: exit 34 through full `-Oz`. On that evidence the
binaryen skip for throwing modules was deleted — and the full gate immediately failed
`15_Exceptions` and `15_LexicalShadowing_Stress`, because the fixture holds **no local live across a
catch edge**, which is the only thing the bug touches. A skip exists to prevent a *class* of defect;
the evidence for removing it must exercise that class, not the happy path the feature already owns.
**Ask what the skip was protecting, then check the fixture actually reproduces it — a green fixture
is not a green gate.**

**Run gates in dependency order: a gate that reads a generated corpus must run AFTER the suite that
regenerates it.** [wasmtk, 2026-08-25] `testing.md` says to run `engine_cross_check_tests` after
`wasi_tests`; the first full-gate script ran it before. Its `0 regressed, 8 improved` was therefore
measured against a corpus built by the *previous* compiler — a real-looking number that answered a
question nobody asked. Ordering inside a gate script is load-bearing, not cosmetic.

**A reported SHAPE may be a symptom of a PRECONDITION that never mentions it — ask for the
precondition.** [binaryang → wasmtk, 2026-08-27] A defect was reported to us as "a tag whose param
is `(ref $T)`". We wrote down the obvious follow-up: audit our fixtures for `(ref $T)` tag params.
Upstream then re-probed it and the real precondition was a **conjunction neither half of which
mentions the tag's types** — the module contains a struct or array type, AND no function shares the
tag's exact signature. Our audit would have returned no matches and we would have recorded
"unaffected", a conclusion that does not follow from that check. We were in fact clear, for an
entirely different reason (wasic emits no struct or array types at all). **The right answer arrived
by luck; the check was wrong.** When an upstream reports a shape, ask what makes it fire.

**An import alias must not collide with a package the project could actually resolve.**
[binaryang → wasmtk, 2026-08-27] Our `"binaryen"` alias pointed at a JSR compat subpath, but the
facade behind it can also be pointed at the real `npm:binaryen`. One specifier, two packages,
selected by configuration — and `import ... from "binaryen"` told the reader nothing about which.
Renamed to `binaryen-backend`. **The test is not "is the name accurate?" but "could this name also
resolve to something else here?"**

**An upstream fix that does not move your number means the binding constraint may have MOVED, not
that the fix failed.** [wasmtk, 2026-08-27] `ref_null.wast` sat at 0 pass / 32 skip, recorded as an
upstream encoder bug. Upstream fixed their half; our number did not move, because our own runner's
`constType()` had become the binding constraint — and **nothing re-announced it, because a skip is
not a failure**. The tell was in the row all along: `unbuilt modules = 0` meant the modules
ASSEMBLED, so whatever stopped them was downstream of the assembler. Teaching the runner to marshal
`ref.null` was worth **+123 assertions across 16 files**. **When a fix lands and your metric is flat,
re-ask which layer binds before re-reporting it upstream.**

**Converting a SKIP into a FAILURE is a false negative — read what the new failures actually say.**
[wasmtk, 2026-08-27] Admitting `ref.null` turned 32 skips into 25 passes and **7 failures**. All
seven were `type incompatibility when transforming from/to JS` — V8 refusing to marshal `exnref` /
`anyref` / user-defined heap types. That is a limit of the HARNESS; recording it as a failure asserts
the toolchain got something wrong when the module is fine and only the test cannot see it. The runner
already had the precedent — NaN payloads that cannot cross the JS boundary are skipped, with a
comment saying why. **A new failure appearing beside a big win deserves the same scrutiny as a
regression, and is exactly when you are least inclined to look.**

### 🔁 STANDING QUESTION, both projects: *where is this construct USED, not where is it NAMED?*

[binaryang + wasmtk, adopted 2026-08-27 — carried in binaryang's handoff and here, deliberately in
both so neither side has to remember it alone.]

**Ask it before sizing any conformance or migration work.** Both projects made this error
independently, four days apart, in opposite directions:

| | estimate | actual | why |
| --- | --- | --- | --- |
| wasmtk, `ref.null` | 32 assertions | **123** | `table_fill` / `table_set` / `table_grow` pass `ref.null` as an ARGUMENT — the count found where the instruction is *asserted*, not where the value is *used* |
| binaryang, `br_on_cast` | inflated by a 114-assertion file | **20–40** | the file was counted because it *contained* `br_on_cast`; it dies in the parser on `(exact $T)` long before reaching one |

Undershooting cost nothing but a surprise. Overshooting would have reordered a release around a file
that no amount of `br_on_cast` work could move. **Same failure, and the direction is luck.**

The generalisation covers a whole family this week: *"contains the instruction" ≠ "is blocked by the
instruction"*; a fixed thing left in the wrong column because a skip never re-announces itself; a
defect reported by a SHAPE when the precondition was a conjunction not mentioning it. **Every one is
attributing a result to the property that happened to be in view.**

The check is cheap and mechanical: **grep finds names; sizing needs uses.** Before quoting a number,
name the construct, then ask separately — where is it *declared*, where is it *asserted*, and where
is it *consumed*? If those three sets differ, the estimate is measuring whichever one the grep
matched.

**Neither project caught its own instance.** Each was found by the other side having a different
vantage point, which is the argument for writing the question down rather than trusting care.

**Stopping a background suite kills the SHELL, not its children — verify the machine is idle before
the next measurement.** [wasmtk, 2026-08-25] A hung `wasi_tests` run was stopped via the task
harness; two orphaned `deno` processes kept spinning at ~98% CPU and were still there **30 minutes
later**, at 2140s and 1533s of CPU, competing with every build and timing measurement taken in
between. Nothing reported an error — the harness said the task was stopped, and it was. After killing
a long run, list the process table and kill survivors by PID. On a gate whose failures are *timeouts*,
a stray CPU hog is not just noise, it manufactures the symptom you are hunting.

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
