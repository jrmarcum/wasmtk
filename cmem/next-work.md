# Next-work planning note

> Actionable backlog as of **2026-07-30** (after **v2.0.0** shipped — Phase 34 inline predicate
> targets + the first breaking change). Authoritative status lives in [roadmap.md](roadmap.md); this
> file is the short, prioritized "what to pick up next" list. Prune items as they land.

## Open as of 2026-07-30 (v2.0.0)

- 🔴 **JSR provenance is still missing — 11 releases now (v1.11.3 → v2.0.0).** The one thing that
  needs an environment this machine does not have. **Deno is RULED OUT** (v2.0.0 was published on a
  pinned Deno 2.9.1 and came out unattested anyway; pin reverted in `06e0b4f`). Also already
  eliminated: `publish.yml` itself, `id-token: write`, the OIDC prerequisite step, the JSR↔GitHub
  link, `--no-provenance`. **Remaining suspects: JSR-side or GitHub-side changes in the
  2026-07-03 → 07-09 window.** Next step needs an **authenticated `gh`** (not installed here — the
  Actions logs endpoint 403s unauthenticated): `gh run view <id> --log` on the v1.11.2 (attested)
  vs v1.11.3 (not) runs, diffing what `deno publish` actually reported. Full elimination list in
  [design-decisions.md](design-decisions.md). The "Verify provenance was recorded on JSR" step now
  fails the publish job whenever it is missing, so this can no longer regress unnoticed —
  **expect the v2.0.0 Actions run to be red for this reason; the package published fine.**
- ⏳ **Declare a Deno floor in `deno.json`.** There is none today, so nothing validates a minimum
  supported version and a release could silently start requiring a newer Deno — first signal would
  be a user report. Cheap to add, and it would make the compatibility question decidable.
- ⏳ **Chase the wabt-ts `ref.null` bug; do NOT expect the other two to move.** The 2026-08-20 corpus
  sync exposed three gaps, and they have **different owners** — see
  [compiler-bugs.md](compiler-bugs.md) § "wabt-ts `ref.null` + parser gaps". Only `ref.null`
  (cannot encode for any heap type; `ref_null.wast` is 0 pass / 34 skip) is a genuine wabt-ts bug and
  worth re-measuring after a bump. `ref.null $t` and `(module definition …)` are **parity with
  upstream wabt**, so they need an upstream feature, not a wabt-ts release. Report filed at
  `scripts/wabt-ts-bug-report.md`. **Zero failures introduced — gate on baseline at 287 files / 27983 / 12 pinned** —
  this is recovery-of-coverage, not a bug to chase on our side.
- 🔴 **Fix the `wast` runner's memory retention** — sized and argued in § "SCOPED: work opened by the
  2026-08-20 spec-corpus session" below. The only open item with a user-visible symptom.
- ⏳ **Decide whether to pin `*.wast text eol=lf` in `.gitattributes`.** Deliberately NOT done on
  2026-08-20 — a repo-wide checkout-behaviour change shouldn't ride along inside a corpus sync. It
  is a one-liner whenever wanted; rationale in [design-decisions.md](design-decisions.md).
- ⏳ **`docs/` and `cmem/*.md` are not `deno fmt`-clean.** `main.ts` + `src/` now are, and
  `.gitattributes` keeps them that way; the markdown was deliberately left alone (bare `deno fmt`
  mangles tables/code-fences — see [workflow.md](workflow.md)). If it is ever wanted, it needs its
  own pass with `fmt.exclude` tuned, not a blanket run.

## `fd_write` short writes — ✅ FIXED 2026-08-24 (and it opened one new item)

**Fixed.** `$__fd_write_all` loops until every iovec is drained (bailing on errno and on zero
progress); both `console_log.ts` call sites rerouted, and the `dync` `__host_print` path given its
own inline loop since it is spliced post-merge. Engine gate: **0 regressed, 37 improved** — every
`differ` flipped to `match`. Full suite green. Detail in [compiler-bugs.md](compiler-bugs.md).

### ✅ FIXED 2026-08-24: `console.log(<bool expr>)` evaluated its argument twice

Found in the same code while fixing the above, and **worse in kind** — it changes program
semantics, not just output. `boolexpr` interpolates its WAT into both the ptr store and the len
store, so a `bool`-returning CALL runs twice:

```ts
console.log(isPositive(5));   // isPositive() is invoked TWICE
```

- **Fixed with a single statement-form `if`** — both stores inside each arm, operand evaluated
  once. **No temp local was needed**; the earlier note claiming it required one plumbed through
  the emitter was wrong, and the simpler shape is also strictly better WAT.
- The gather branch had it worse (THREE evaluations) and got the same restructure, which is what
  let `boolexpr` join `gatherable`/`strBoolKinds`. `console.log(x > 0)` now inlines its newline
  into one iovec. **The exclusion and the bug were one knot, not two.**
- ⚠️ Only a **call** returning `bool` is observably affected; pure comparisons are not. That is why
  a corpus of mostly-pure predicates never surfaced it, and why the engine gate did not either —
  **every engine agrees on the wrong answer**, which is precisely the blind spot cross-engine
  testing cannot cover. Repro is in [compiler-bugs.md](compiler-bugs.md).

## 🔴 Zig and Rust producers have NO test suite (found by the 2026-08-24 audit)

`src/zigwasic.ts` (286 lines) and `src/rustwasic.ts` (64) are gated by **nothing**, while `zig`,
`cargo` and `rustc` are all installed and working on this machine and Zig fixtures already sit in the
corpus (`tests/wasi/wasm_wasi/1_fib-zig.zig`). Go has three suites; these have none.

**This is not theoretical — two of the audit's findings were in that unguarded code**, and both are
the kind a suite catches for free: `report()` announcing success without checking the artifact
exists, and a failed `binaryen -Oz` swallowed silently. See [compiler-bugs.md](compiler-bugs.md).

- **[S] `zig_tests.ts`** — skip-if-absent like the TinyGo gates. Build `1_fib-zig.zig` for both
  targets (`library` and `wasi`), assert the artifact exists and is non-empty, and run the wasi one
  (expect `Fibonacci(10) = 55`, verified by hand 2026-08-24). That alone would have caught both.
- **[S] `rust_tests.ts`** — thinner: `rustwasic.ts` only delegates to `rsxtk`, so assert the
  delegation and the not-found error path. Skip entirely when `rsxtk` is absent.
- ⚠️ Add them to the impact map in [testing.md](testing.md) at the same time, or the suite set
  grows without the "which suites does this change reach" table knowing about it.

## SCOPED: the 102 pinned wast failures after wabt-ts 1.4.0 (2026-08-25)

The 1.4.0 bump took the gate from 27,983 to **37,247 passing assertions** and dropped skips by
~10,000. What surfaced with it is 102 failures in **15 files** — all previously DARK, none of them
regressions. Pinned loudly per the standing policy; scoped here.

**RANK BY ROOT CAUSE, NOT BY FILE COUNT.** 73 of the 102 are one family, and two of those files are
byte-copies of two others (`proposals/custom-descriptors/br_on_cast*.wast`), so the *distinct* work
is far smaller than the row count suggests:

| # | class | files | root cause |
| --- | --- | --- | --- |
| **73** | GC casts | `ref_test` 32, `ref_cast` 11, `br_on_cast` 10, `br_on_cast_fail` 10, + 2 custom-descriptors copies @10 | **DIAGNOSED — ours.** See A below |
| 11 | linking | `linking` 6, `linking3` 4, `linking0` 1 | not yet probed |
| 6 | tables | `table_grow` 2, `table_grow64` 2, `table_get` 1, `table_get64` 1 | not yet probed |
| 2 | misc | `names` 1, `ref_is_null` 1 | not yet probed |

### A. GC casts — [S] DIAGNOSED, ours, and it is not what it looks like

**The runner skips the SETUP CALL, so every assertion after it reads an empty table.**
`ref_test.wast:101` is `(invoke "init" (ref.extern 0))`. `runAction` rejects any argument that is not
a numeric const (`__skip__: unsupported arg type`), so `init` never runs, `$ta` indices 3–5 stay
null, and all 32 assertions mismatch. Confirmed by construction:

```
BEFORE init: 0->2  3->2  5->2        <- what the gate sees
AFTER  init: 0->2  3->0  5->0        <- exactly what the spec wants
```

- **Fix:** accept reference-typed invoke arguments. `(ref.extern N)` is an opaque host value — in JS
  any value works, so pass `N` (or a distinct wrapper object per N if identity is ever compared).
  `(ref.null extern|func|any…)` → `null`. That is the whole change; `constToJs`/`constType` in
  `src/wast.ts` are the sites.
- **Expected effect:** most of the 73. Re-measure per file rather than predicting a number.

🎓 **METHOD NOTE — I nearly filed this against wabt-ts.** The first probe called
`ref_test_null_data` directly under V8 *and* wasmtime, got 2 from both, and "two independent engines
agreeing from the same bytes" pointed straight at an encode bug. It was wrong: **neither engine had
`init` called either**, because I reproduced the runner's own omission in the probe. A third-party
check only isolates the layer if the third party is given the SAME SETUP, not just the same bytes.

### B. linking (11) — [M] not probed

`linking0`/`linking` already carried cascade failures before the bump; `linking3` is new. Probe the
same way and expect the same question: is a setup command being skipped, or is the module genuinely
mis-linked? Check for `(register …)` ordering and for actions with non-numeric arguments first — that
is now a known blind spot, not a hypothesis.

### C. tables (6) — [S/M] not probed

`table_grow`/`table_get` mismatches on `size`. **Suspect cross-module state**, since these files
declare several modules and the runner keeps one `cur` instance plus a `named` map — but that is a
hypothesis and has NOT been tested. Probe: dump the sequence of module instantiations and check
whether the assertion targets the instance it names.

### D. misc (2) — [S]

`names.wast` is down to a single failure from 369 after the UTF-8 decode fix; whatever remains is
one specific name. `ref_is_null` 1 is probably class A.

### The probe recipe that works, in order

1. **Find the assertion's setup.** Grep backwards from the failing line for `invoke` / `register` /
   `module` — a skipped setup command explains more failures than a wrong opcode ever will.
2. **Ask V8 directly, with the setup performed by hand.** If it then matches the spec, the runner is
   the problem and the module is fine.
3. **Only then ask a third engine**, and give it the same setup. Same bytes is not the same test.
4. Re-measure per file; do not project a total.

## CORRECTIONS SCOPED — 2026-08-24 (while binaryen-ts + wabt-ts land their fixes)

Everything wasmtk must change from the 2026-08-20/24 exchange, split by whether it is blocked on the
sibling projects.

> **CORRECTED later on 2026-08-24.** This section first said "nothing is blocked on them except
> §C — the EH migration is entirely ours and can start now." **That was wrong.** Closing a caveat
> the binaryen-ts team raised turned up a hard blocker: **wabt-ts 1.3.5 cannot ENCODE `try_table`**
> (it parses it, then fails in the binary writer — every handler form, see compiler-bugs.md).
> wasic's pipeline is WAT → wabt → binary, so §A cannot ship until wabt-ts is fixed. §B is still
> fully ours and startable.

### A. `try_table` migration — [M/L], ⛔ BLOCKED on wabt-ts encode fix (was: "start now")

Detail in [compiler-bugs.md](compiler-bugs.md). `src/wasic.ts` 14749 / 14756 / 14772+14774.

**⛔ Blocked, and the block is NOT obvious — do not start and discover it.** wabt-ts 1.3.5 encodes
legacy `try` fine and **cannot encode any `try_table` with a handler clause**, which is exactly
backwards from what we need. The design work below is still valid and the target shape is proven
(a nested fixture using both forms runs correctly on `wasmtime 47.0.3`, no `-W` flags, exit code
confirming both the catch and `finally`-then-propagate paths). Only the encoder is missing. Filed in
`scripts/wabt-ts-bug-report.md`; likely the same fix as the `ref.null` encode bug.

**The recheck is one command, and the fixture is committed:** `scripts/eh_try_table_fixture.wat`
(nested, both required forms). `wasmtime scripts/eh_try_table_fixture.wat` must exit **34** — 33
from the tag param caught by the outer handler, +1 from the inner `finally` global. Then push it
through wasic's `watToOptimisedWasm` path (wabt → binaryen `-Oz`) and run the RESULT: exit 34 there
means the pipeline preserves `try_table` end to end and §A is unblocked. **Trust that, not the
release notes.**

1. **[M] Emitter: legacy `try` → `try_table`.** Two shapes only (`catch $__exn_tag`; and
   `catch_all`+`rethrow 0` → `catch_all_ref`+`throw_ref`). No `delegate`.
2. **[S] Update the doc block at `src/wasic.ts` 107–113** — it documents the legacy shapes and will
   be actively wrong the moment the emitter changes.

**Three risks, priced rather than assumed:**

- **Nesting is real, and it is the main risk.** `try_table` catch clauses are branch targets, so each
  nesting level needs its own uniquely-labelled enclosing block — legacy inline handlers needed no
  labels at all. 4 corpus modules carry multiple `(try`: `15_Exceptions` (3), `56_AsyncReject`,
  `15_LexicalShadowing_Stress`, `15_TestCase1-NestedEscalation` (2 each). The depth-tracking at
  ~14820–14835 exists precisely because nested `try`/`catch`/`finally` parsing is fiddly; expect the
  label generation to need the same care.
- **Two of the ten affected modules are async** (`56_AsyncReject`, `60_AsyncAll`). `try` inside an
  async function interacts with the asyncify pass — **verify those two specifically**; do not assume
  the sync cases generalise.
- **`finally` must still run on the non-throwing path.** Semantics unchanged, but it moves to the
  `$done` side of the block instead of being emitted inline in `(do …)`.

### B. Multi-engine gate — DONE 2026-08-24 (`tests/engine_cross_check_tests.ts`)

**Built, and it immediately earned its keep.** 376 modules × 3 engines against a V8 baseline,
per module/engine expectations in `tests/engine_baseline.json`, absent engines skipped. Modelled on
`dync_cross_runtime_tests.ts` as planned — no new machinery invented.

🎓 **On its FIRST full run it found a second, unrelated bug**: 37 modules produce different
stdout on wasmtime and match everywhere else — `fd_write` short writes, ignored by our emitted
code. That is the whole argument for the gate, demonstrated rather than asserted: two independent
defects in one week that no V8-only test could reach. See [compiler-bugs.md](compiler-bugs.md). The suite was **417/417
green** while all 10 modules were unrunnable on the primary WASI host, because our oracle is V8 and
V8 still accepts legacy EH. Migrating without a second engine fixes the instance and leaves the
blind spot exactly where it was.

**Do not invent machinery — the pattern already exists.** `tests/dync_cross_runtime_tests.ts` already
does skip-if-absent cross-runtime execution with byte-identical-stdout comparison against a
`deno run` JS baseline, over `wasmtime`/`wasmer`/`wazero`. Model the EH gate on it directly.

- Installed here 2026-08-24: `wasmtime 47.0.3`, `wasmer 7.2.1`, `wazero`.
- **Wasmer cannot be part of an EH gate** — 7.2.1 supports no EH in any backend (legacy *or*
  `try_table`), so it must be skipped for these modules specifically or it fails everything.
- `wasmtk wast` (`src/wast.ts`) has the **same V8-only shape**; extending the same idea there is the
  natural follow-on, and is what its `--runtime <cmd>` hook was structured for (architecture.md).

### C. BLOCKED on the sibling releases — prep only

Nothing to build; this is a checklist so the bump is mechanical when it lands.

- **wabt-ts** — now blocking TWO things: `ref.null` (cannot encode for ANY heap type) **and
  `try_table` (cannot encode any handler form) — the latter gates §A entirely**. Same message, same
  binary writer, plausibly one fix. The two *parity* gaps
  (`ref.null $t`, `(module definition …)`) will **NOT** move on a wabt-ts release; they need
  upstream wabt. Do not expect them.
- **binaryen-ts** — **nothing from this exchange implicates it.** No wasmtk-side correction is
  pending; a version bump plus the regression gate is the whole job. Do not manufacture work to
  match the other side's activity.

### ⏳ THE NEXT BUMP IS **wabt-ts 1.4.0** (owner, 2026-08-24)

Named so the recheck is mechanical rather than rediscovered. Pin is currently `^1.3.5` in
`deno.json`; `deno.lock` resolves 1.3.5. **1.4.0 is expected to carry the `ref.null` and `try_table`
encoder fixes** — both filed in `scripts/wabt-ts-bug-report.md`, and both plausibly one fix (same
message, same binary writer, same unusable "run resolveNames" advice).

**Step 0 — PROVE THE ENCODER BEFORE ANYTHING ELSE.** Do not bump, re-record and then discover it did
not land; the two probes are seconds and they gate everything after them:

```bash
# a) does try_table encode at all? every handler form must say OK, not ENCODE-FAIL
#    (catch $t $h / catch 0 $h / catch_ref / catch_all / catch_all_ref)
# b) does ref.null encode for every heap type?
# Both probe shapes are recorded in scripts/wabt-ts-bug-report.md.

# c) the acceptance test for the whole EH migration — committed, one command:
wasmtime scripts/eh_try_table_fixture.wat        # must exit 34
# then push that fixture through wasic's watToOptimisedWasm path (wabt → binaryen -Oz)
# and run the RESULT. Exit 34 there means the pipeline preserves try_table end to end
# and §A is unblocked. TRUST THAT, NOT THE RELEASE NOTES.
```

If (a) still fails, **§A stays blocked and nothing else about the bump matters** — say so plainly
rather than proceeding. The wabt-ts side asserted "nothing needed on our side" once already while
1.3.5 could not encode a single handler form; that claim is worth re-measuring, not re-trusting.

**Bump procedure, and two things that WILL look like failures and are not:**

1. Update the pin in `deno.json` (`^1.3.5` → `^1.4.0`), then **`deno task install`** (mandatory —
   the suites invoke the global binary, and reinstalling MID-RUN silently invalidates a run).
2. Run the wast gate. **EXPECT IT TO GO RED**, in either or both of two ways:
   - `GAINED COVERAGE` — `ref_null.wast` is pinned at **0 passes** precisely so a fix announces
     itself; any file that improves fails until re-recorded.
   - `OFF BASELINE: failures N → M` — the 12 known failures are pinned at their exact counts now, so
     a backend fix that clears a cascade also trips the gate. **Both are the gate working.**
3. Re-record deliberately, then **diff the baseline** — that diff is the measurement of what 1.4.0
   actually fixed, and it is the number worth reporting back to them:
   `deno run --allow-read --allow-write --allow-net --allow-run tests/wast_tests.ts --update-baseline`
4. Full suite set — a backend bump reaches everything (impact map in testing.md).
5. Regenerate the corpus **before** any cross-engine claim (testing.md rule), then re-run the engine
   gate and re-record `tests/engine_baseline.json` if it moved.

### D. `wast` runner + its 15 failures — unchanged, independent of all the above

Sizes and the class-A policy question are in the SCOPED section below. Unaffected by either sibling
release. The runner OOM remains the only item with a user-visible symptom.

## 🔴 wasic emits LEGACY exception handling — Wasmtime cannot run it (2026-08-24)

**The largest open item, and the only one that breaks real user output.** Every TS
`try`/`catch`/`finally` compiles to the superseded legacy EH proposal; `wasmtime 47.0.3` rejects all
10 affected modules at compile time, and there is **no `-W legacy-exceptions` flag** to work around
it. Reported by the wabt-ts side, confirmed here against regenerated artifacts. Full detail:
[compiler-bugs.md](compiler-bugs.md) § "wasic emits LEGACY exception handling".

- **[M] Migrate the emitter to `try_table` / `throw_ref`** — `src/wasic.ts` lines 14749 / 14756 /
  14772+14774. Only **two** shapes (`catch`, and `catch_all`+`rethrow 0`), no `delegate`. Not a
  mechanical swap: in `try_table` a catch clause is a **branch target**, so handler bodies move out
  of the try into an enclosing block and the tag's params arrive as that block's results.
- **[S] Add Wasmtime to the EH gate — do this WITH the migration, not after.** This is the part
  that matters beyond the bug: **the suite was 417/417 green the whole time this was broken**,
  because our oracle is V8 and V8 still accepts legacy EH. Migrating without adding a second engine
  fixes the instance and leaves the blind spot. `wasmtk wast` has the same V8-only shape.
- Caveat (measured by them): **Wasmer 7.2.1 runs neither form** — no EH support in any backend. The
  migration fixes Wasmtime and does not change Wasmer. Not a reason to defer.

**Their `KNOWN_INVALID` list of 7 "invalid" modules is stale — do NOT chase it.** All 7 run clean on
Wasmtime from current `wasic`. Their corpus copy is 272 `.wat` vs our 373. Reply sent in
`scripts/wabt-ts-bug-report.md`; fix is on their side.

## SCOPED: work opened by the 2026-08-20 spec-corpus session

Everything below came out of one session (corpus sync -> per-file baseline gate -> wabt-ts report).
Sized S/M/L by *uncertainty*, not keystrokes. **Nothing here is a release blocker** — every suite
that can run on this machine is green, and none of it touches `wasic` codegen.

### The 15 execution failures the new gate made visible

These live in the 7 files excluded from `tests/wast_baseline.json`. **They were never in the old
41-file gate**, so they have been invisible the whole time, not newly broken. Triaged 2026-08-20:

| # | Class | Files | What it actually is |
| --- | --- | --- | --- |
| **A** | knock-on (10) | `load1` 5, `linking` 4, `type-equivalence` 1 | A module fails to assemble, so a LATER assertion against a *different, still-valid* named instance reads state the failed module never wrote. e.g. `load1.wast`: `(module $M)` assembles, the second module (which populates it) does not, so `$M.read(20)` returns 0 instead of 1. Reported as `assert_return mismatch` — loud, and technically true, but the cause is a toolchain gap, not an engine bug. |
| **B** | misclassification (2) | `imports` | `assert_invalid` the toolchain fails to reject is documented and counted as a SKIP everywhere else in the runner (see the note at the end of `runWast`), but these two land as FAILURES. An inconsistency in the runner, not a finding. |
| **C** | runner bug (1) | `annotations` | `parse error: Invalid array length` — our own S-expr reader, not wabt. The only one here that is unambiguously our defect. |
| **D** | unknown (1) | `float_memory` | Genuine `assert_return` mismatch: `(invoke "i32.load") -> 0x7fd00001` expected. NaN bit-pattern surviving a memory round-trip. **Not yet explained** — could be runner, wabt-ts, or a real JS-boundary limit like the existing `nan:0x` skip. |
| **E** | unknown (1) | `linking0` | `assert_return action trapped: null function`. Probably class A, not confirmed. |

- **A — S.** Decide the policy, then it is small. The honest fix is to mark a named instance
  *poisoned* when a module it depends on fails, so downstream actions SKIP instead of producing a
  wrong-value FAIL. **Counter-argument worth weighing before doing it:** a loud false alarm is safer
  than a silent skip, and this whole session exists because skips hid a regression. Do not
  reflexively convert these to skips — that is the same mistake in the other direction.
- **B — S.** Make the classification consistent with the documented rule. Low risk, mechanical.
- **C — S/M.** A real parser bug; size unknown until the malformed input is isolated.
- **D — M.** Genuinely unknown. Must not be assumed to be a wabt-ts bug without a minimal repro —
  the last two "wabt-ts bugs" this session turned out to be upstream-wabt parity.
- **E — S.** Confirm it is class A, then it folds into A.

**Superseded 2026-08-24:** the failing files are now PINNED in the baseline rather than excluded, so
the gate already covers them (287 files). Fixing the remaining causes would flip their pinned counts
to 0 — which the gate reports as drift and refuses until re-recorded. What is left is `float_memory`
(1, the only independent failure) and the cascades behind ~25 unbuilt modules. Was: taking the gate from 280 files to ~286
and closing the "8 corpus files not in the baseline" line the gate prints every run.

### Runner memory retention (dir-run OOM) — L, and the only one with a user-visible symptom

`wasmtk wast <dir>` over the full corpus OOMs; `proposals/custom-descriptors/exact.wast` exhausts
the heap alone. README documents the crashing form, so this is the one item a user could hit.
Partially fixed 2026-08-20 (per-file WABT instance -> singleton) and **measured insufficient**.
Sized L because the remaining retention is not yet located — likely instantiated modules and their
`WebAssembly.Memory` buffers, which is a lifetime redesign in `runWast`, not a one-liner. Full
measurements in [compiler-bugs.md](compiler-bugs.md) § "wast runner memory".

**Do this before A–E if any of it is done at all** — it is the only item with a user-facing
failure, and `--update-baseline` currently carries subprocess-chunking machinery that exists purely
to work around it. Fixing it lets that machinery be deleted.

### Go 1.27 vs TinyGo — ✅ RESOLVED 2026-08-20 (owner downgraded to Go 1.26.7)

Was: `go_merge` (0/1), `go_bindgen` (0/1), `go_asyncify` (0/12) failing with `requires go version
1.19 through 1.26, got go1.27`. **Now green: 7/7, 7/7, 12/12** — all matching their recorded
baselines. The "entire suite set" gate has no hole on this machine again.

**Toolchain now pinned at Go 1.26.7 / TinyGo 0.41.1** (`tinygo version` confirms
"using go version go1.26.7"). Keep them in step — this WILL recur:

- **TinyGo 0.41.1 is the newest RELEASE** (2026-04-22) and caps at **Go 1.26**. It was not a stale
  install; no released TinyGo supported 1.27 at the time.
- Go 1.27.0 had been installed 2026-08-20 09:36 and broke the three suites the same morning — this
  was same-day breakage from a toolchain upgrade, never a long-standing environmental quirk.
- **Go 1.27 support IS on TinyGo `dev`** (`0.42.0-dev`, commit "all: build/test using Go 1.27.0",
  2026-08-20). **When 0.42.0 ships, Go 1.27 becomes safe again** — that is the moment to move
  forward, not before.
- Note for whoever hits this next: scoop's `versions` bucket has **no `go125`/`go126` manifest**
  (it jumps `go124` 1.24.13 → `go` 1.27.0), so a scoop-only downgrade lands on 1.24.13. 1.26.7 came
  from outside scoop.
- **The Go suites are not Go-only coverage** — `go_merge` compiles a TypeScript driver with `wasic`
  (see [testing.md](testing.md)), so leaving them red silently drops `wasic` coverage too. That is
  the real cost of tolerating this, and the reason to fix it rather than wait it out.

### External / decisions — no work, just tracking

- **wabt-ts `ref.null`** — filed in `scripts/wabt-ts-bug-report.md`; waiting on them. The other two
  gaps are upstream-wabt parity and will not move on a wabt-ts release.
- **Upstream propagation gap** — the 3 `"multiple tables"` assertions are fixed in
  `WebAssembly/threads` but never propagated into `WebAssembly/testsuite`. Filing it upstream is
  optional and costs us nothing either way; **do not patch it locally** (see testing.md).
- **`*.wast text eol=lf`** — one-line decision, deliberately deferred; see design-decisions.md.

## Recommended next pickup (updated 2026-07-28)

- **THE BIG TRACK: wasic modularization** — see [wasic-modularization-plan.md](wasic-modularization-plan.md).
  **Phase 0 = "look for code issues" audit, run as a loop to ZERO (HARD GATE)** before any module
  extraction. This is the agreed next major effort.
- **✅ v2.0.0 PUBLISHED (2026-07-30)** — latest on JSR; supersedes the v1.11.7 note that used to sit
  here. See [roadmap.md](roadmap.md) § "Release status — v2.0.0".
- **Producer verbs unified + `--lang` auto-detect + Go browser removed — ✅ DONE (2026-07-28).** Same
  verbs across go/zig/rust (`init`=program, `initmod`=library, `build`=program→`.wasm`); `--lang`
  optional for run/build/modc (auto-detected); add/remove/list/fmt/clean need no `--lang`; Go
  `--go-target=wasm` browser scaffold removed (→ universal wasm loader). Correction recorded:
  producers do NOT auto-emit `.wit` (TS-only). See [polyglot-producers.md](polyglot-producers.md)
  § "UPDATED 2026-07-28". **Follow-up ⏳: producer `.wit` auto-emission** (Go/Zig/Rust) — a real
  roadmap item, currently hand-written for Go bindgen.
- **Dynamic runtime → runs on ANY WASI runtime — ✅ DONE (2026-07-27).** `wasmtk dync` output now
  imports ONLY `wasi_snapshot_preview1.*` and runs unchanged on wasmtime/wasmer/wazero (byte-identical
  stdout, 9/9). Shipped as a post-merge WAT transform **`internalizeDynrtHostImports`** in
  `compileWasiTs` (NOT the planned intrinsic — that would have broken bindgen, which shares the dynrt
  library; the transform is scoped to the hostless WASI-executable path only). print → inline WASI
  `fd_write(1,…)`; `__host_call` → `unreachable` trap. Standing gate:
  `tests/dync_cross_runtime_tests.ts` (asserts pure-WASI imports always; byte-diffs under any present
  runtime, skip-if-absent). Suites green: wasi 375/375, dync_conformance 3/3, bindgen 142/142. Full
  write-up in [dynrt-design.md](dynrt-design.md) § "Dynamic modules → run on ANY WASI runtime" →
  "### ✅ IMPLEMENTED".
- **wasic ↔ dync: keep both engines; abort GUIDES to dync-or-fix — ✅ DONE (2026-07-27).** Owner
  question ("do we need both? can wasic detect + use dync?") → keep both (different targets), NO
  silent fallback (interpreter-size cliff + masks wasic gaps). On a `wasmtk wasic` abort the CLI now
  classifies the diagnostics and points to `wasmtk dync <file>` (dynamic feature) or "fix this first"
  (undefined name — dync fails on it too); mixed shows both. `compileWasiTs` surfaces `aborted` +
  `diagnostics` in `WasicResult`; the guidance lives in the `wasic` CLI wrapper only (auto-gated —
  the dync driver + modc don't use it). Also merge notices `⚠️`→`ℹ️`. See
  [dynrt-design.md](dynrt-design.md) § "wasic ↔ dync". Deferred: the fuller `wasmtk compile` router
  (classify-and-route typed/dynamic/mixed) — owner chose the actionable-abort scope.
- **B6** — asyncify list↔binary-parse name retention: still deferred (no consumer).
  (A + B3/B4/B5 all DONE 2026-07-09.)

## A. Feature work (optional, self-contained)

1. **Utility-types batch — ✅ DONE (2026-07-08).** The core (`Partial`/`Readonly`/`Required`/
   `NonNullable` pass-through; `Pick`/`Omit`/`Record` synthetic structs) was already implemented
   (Phase 51.4, `51_UtilityTypes.ts`). Added **`ReturnType<F>` / `Parameters<F>`** this session
   (`expandFnUtilityTypes` in `src/wasic.ts`): F may be a named fn-type alias / `typeof fn` / inline
   `(…) => R`; inline uses substitute the resolved scalar/struct/tuple, and a `type X = Parameters<F>`
   alias becomes a `type X = [tuple]`. Test `51_UtilityTypes.ts` extended (returntype/parameters
   cases). DEFERRED (low value in wasic's typed subset): `Exclude`/`Extract` (need first-class
   string-literal-union types wasic lacks) and a `type X = ReturnType<F>` alias where F returns a
   SCALAR (wasic has no scalar type aliases — write it inline).
2. **Go "mergeable leaf" — ✅ DONE (2026-07-08).** `modc --lang=go --go-target=wasm-unknown` →
   `buildGoLeaf` builds TinyGo's freestanding `wasm-unknown` target (0 imports, no `memory.grow`),
   which `wasmmerge`s into a wasic/bundle build like a Zig `FixedBufferAllocator` leaf. The merge
   (`mergeOneWasmImport`) calls the leaf's `_initialize` + floors memory at 2 pages (TinyGo's export
   init-guard sits at fixed address 65536). Test `go_merge_tests.ts` (7/7). Caveat: host must not use
   page 1 — small hosts only; else use reactor/bindgen. See polyglot-producers.md § "Mergeable Go leaf".

## B. Hardening / follow-ups from the 2026-07-08 asyncify work (small)

3. **Broaden goroutine-Go validation — ✅ DONE (2026-07-09).** `tests/go_asyncify_tests.ts` is now
   table-driven over the full goroutine surface through the forced in-house path: worker-pool
   (`sum: 30`), `select`/unbuffered (`select-total: 300`), `time.Sleep` (`sleep-result: 42`),
   `sync.WaitGroup`+`Mutex`+closure+defer (`wg-counter: 45`), 3-stage fan-out pipeline
   (`pipeline-total: 55`), and **`nested/` (re-entrant suspend, `nested-sum: 36`) — now in the forced
   list — 12/12.** **FOUND A REAL BUG** doing so → fixed under B4.
4. **asyncify nested-suspension correctness + liveness-minimized local saving — ✅ DONE (2026-07-09),
   binaryen-ts 1.4.3.** Two independent deliverables. (a) **Liveness-minimized saving** — the Asyncify
   pass now saves only locals live across a suspend (`computeRelevantLocals`, CFG point-wise
   liveness), frames smaller than `wasm-opt`. (b) **The nested crash's TRUE root cause was NOT
   asyncify** — it was a binaryen-ts **binary-decoder reorder bug (WT-2k)**: the decoder took a value
   kept on the operand stack (TinyGo's trampoline keeps `$__stack_pointer` there across a
   `global.set $sp; call…` then restores it) and reordered it past the `global.set` that overwrote it
   → `global.set(global.get)` self-assign that corrupted the shadow stack → boundary OOB. Fix: spill
   the reordered value to a temp local. `nested/` re-enabled in the forced in-house list (12/12).
   wasmtk pins `@jrmarcum/binaryen-ts@^1.4.3`. See binaryen-ts `cmem/correctness.md` § "WT-2k" + wasmtk
   `cmem/polyglot-producers.md` § "NESTED SUSPENSION — found then FIXED". (The earlier "memory-grow
   ordering" hypothesis was a red herring — see that note's "Investigation lesson".)
5. **hybrid nested-backtick-in-`${…}` — ✅ DONE (2026-07-09).** `skipLiteral` now descends into
   `${…}` via `findInterpEnd` (mutual recursion), so an arbitrarily-nested backtick template no
   longer truncates a `@wasm` body (a nested template whose text held a `}` leaked it into
   brace-depth) or defeats call-rewriting in a doubly-nested interpolation. Two teeth-verified
   regression tests in `tests/hybrid_tests.ts`. No known residual scanner edge remains.
6. **asyncify list-options ↔ binary-parse name retention** (binaryen-ts) — add/remove/only-list
   options key on internal `$funcN` names, so they don't match real symbols on a _binary-parsed_
   module (the binary reader drops the name section). Only needed if we ever expose asyncify lists
   on parsed input — the TinyGo path doesn't use lists. Deferred until there's a consumer.

## C. Blocked / deferred (not actionable now)

7. **P2 component container** — waiting on browser-native WASI P2 / Component Model support. The ABI
   is already forward-aligned (callee-allocated string returns + `cabi_post_<name>`), so it's a thin
   terminal `wasm-tools component new` wrap when the time comes; today a P2 wrap buys browser
   consumers nothing (they'd `jco transpile` it back to core wasm anyway). See roadmap.md P2 row.

## Published state (2026-07-09)

- **binaryen-ts 1.4.3** is live on JSR (liveness-minimized asyncify saving + the **WT-2k
  binary-decoder reorder fix** that made NESTED goroutines work — the true root cause of the nested
  crash, NOT asyncify; 1.4.2 was cut but its publish failed a JSR type-check, re-shipped as 1.4.3).
  binaryen-ts suite **405/405**.
- **wasmtk 1.11.5** is live on JSR, **score 100** — ships the nested-goroutine fix + B3/B4/B5 + the
  std-Go merge guard, on backend binaryen-ts 1.4.3 (pin `^1.4.3`). Suites green: wasi **375/375**,
  go_merge 7/7, go_bindgen 7/7, **go_asyncify 12/12** (incl. nested), hybrid 10/10. (1.11.4 shipped
  the nested fix but scored 94 — `src/wast.ts` lacked an `@module` tag so JSR's `allEntrypointsDocs`
  was false; 1.11.5 added it → all 16 entrypoints have a module doc, `deno doc --lint` clean, score
  back to 100.)
- **KNOWN (not a regression): JSR provenance is absent** on wasmtk (`hasProvenance: false`, since
  ≥1.11.3 — `rekorLogId` is null). The publish.yml IS set up for it (`id-token: write` + an
  OIDC-availability check), so this is a GitHub **org/enterprise OIDC policy** blocking the token, an
  infra setting — NOT a code fix. Doesn't drop the score below 100. `deno publish` auto-attaches
  provenance once the org OIDC policy allows the Actions token.
- **B backlog:** B3/B4/B5 all DONE (2026-07-09); B6 deferred (no consumer); A-items all done.
