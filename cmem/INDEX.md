# cmem — Portable Project Memory for wasmtk

The **authoritative, portable** project memory for `wasmtk`. It lives inside the project tree, so it
travels with the repo and the USB — unlike the root `CLAUDE.md`, which is `.gitignore`d and
machine-local.

**Format:** one focused topic file per domain. **This index stays one line per file** — it is read
at the start of every session, so keep it cheap; put the detail in the topic file, not here.
(2026-07-30: the pointers had grown into paragraphs and this file had reached 121 KB, which made
every session start expensive. Trimmed back; earlier revisions are in git.)

## How to work here

1. Read this index. 2. Open only the topic files the task needs. 3. Record what you learn in the
matching topic file, then refresh its one-line pointer below.

**Method lessons go in [best-practices.md](best-practices.md), not in the topic file.** When a pass
produces a lesson that would apply to a completely different subsystem, add it there **and** leave
the detail in its home file.

**Doing a stress-test batch or a release? Read [workflow.md](workflow.md) first** — it holds the
established loop (branch → test → bisect → fix → full gate → memory → commit → merge → bump →
publish) and the traps that have already cost time.

## Policy (durable — set by the project owner 2026-05-31)

- **`cmem/` is the single home for ALL project memory.** Update the matching topic file, then
  refresh its pointer in the table. Convert relative dates to absolute; update existing entries
  rather than duplicating.
- **`README.md` is NOT project memory.** It is the public, user-facing doc shipped to GitHub/JSR
  (install, per-tool usage, capability surface, examples). Keep internal decision logs and bug
  post-mortems out of it.
- The root **`CLAUDE.md` is a small pointer file**, auto-loaded every session. Never put
  authoritative knowledge there — it is gitignored and would not survive a clone. Its pre-2026-07-30
  contents are archived verbatim in [legacy-claude-archive.md](legacy-claude-archive.md).

### Trigger — "update the project memory" (binding on every agent)

When the owner says **"update the project memory"** (or a clear synonym), do BOTH:

1. **Revise all relevant `cmem/` files** — fold in the latest decisions, found bugs, design changes
   and current state; refresh the one-line pointer below; absolute dates; update, don't duplicate.
2. **Sync `README.md` only where the change is user-relevant** — capability surface, install/usage,
   examples, status. **A new README roadmap row goes immediately beneath the phase row it belongs
   to — grouped by PHASE, not appended by date** — with the date in the **Phase** column
   (`NN bug fix (YYYY-MM-DD)` / `NN enhancement (YYYY-MM-DD)`), and ending with the test that covers
   it. Appending dated rows to the end of the `✅` block makes them invisible. `⏳` rows always come
   last. Full placement/labelling directive: top of [roadmap.md](roadmap.md).

### Trigger — "look for code issues" (binding on every agent)

Comprehensive audit across **both tested AND untested** paths for: (1) workarounds/temporary hacks;
(2) dead code (verify each with a grep); (3) bugs — silently-wrong codegen, inverted logic,
type-inference gaps, scanner off-by-ones; (4) **fall-throughs** — the worst failure mode: unhandled
input emitting a comment-stub + bare `0`/`""` instead of erroring. Prefer converting silent-wrong to
a hard `diagnostics` abort, guarding speculative probes with `quietEmit`. Fan out parallel read-only
investigators per category when the surface is large. Report `file:line` + severity, fix the safe
ones, and keep every suite green (**output-diff, not just exit codes**).

### Trigger — regression gate (owner directive 2026-07-28, binding)

**When a bug is found/fixed, run the ENTIRE suite set — including `wast_tests`.** Skip a suite only
when the change is provably outside its reach, justified from the impact map in
[testing.md](testing.md). Two traps that map records: **`go_merge_tests` is NOT a Go-only outlier**
(it compiles a TypeScript driver with `wasic`), and **both `dync_*` suites are wasic-dependent**
(`src/dync.ts` imports `compileWasiTs`). "Outlier" is relative to which FILE changed, never absolute
— verify with the greps in testing.md rather than assuming.

**The gate is triggered by a CHANGE, not by a batch (owner directive 2026-07-30).** If a stress-test
batch surfaces **no bug** and leaves `src/` untouched — the new tests pass as written — **do NOT run
the full suite.** Adding `.ts` files to `tests/wasi/wasm_wasi/` cannot regress the other 400; the
phase filter IS the whole gate. Full-suite runs cost >10 minutes and buy nothing here.

## Files

| File | What it holds |
| --- | --- |
| [best-practices.md](best-practices.md) | **METHOD, not findings — how to work here so the same class of defect does not recur.** Adopted 2026-08-24 from the sibling **wazmrt** project, which pioneered the format; imported rules are marked [wazmrt], ones this project paid for are marked [wasmtk]. **Read before a conformance pass, an audit, a backend bump, or any change to a producer/consumer pair.** The load-bearing one: *a round-trip proves agreement with yourself* — a V8-only oracle held the wasi suite at 417/417 while every `try`/`catch` module was unrunnable on wasmtime. **Added 2026-08-25:** read a hang's CPU time before theorising (spinning ≠ blocked); check the suspect is REACHABLE from the failing input before bisecting it; when a text-parsing fix leaves the symptom, grep for siblings; and stopping a background suite kills the shell, not its children. **2026-08-27 — the STANDING QUESTION shared with binaryang: *where is this construct USED, not where is it NAMED?*** Both projects mis-sized work from a grep in opposite directions four days apart; grep finds names, sizing needs uses |
| [workflow.md](workflow.md) | **The working loop: test → bisect → branch-on-fix → gate → memory → commit → merge → bump → publish.** **A branch is cut only when a test FAILS and needs a `src/` fix** — a clean batch commits straight to `main` (owner directive 2026-07-30). Commit conventions, context boundaries, and the traps that have bitten. **Read at the start of a stress-test batch or a release.** |
| [overview.md](overview.md) | What wasmtk is; repo layout; the key source files |
| [architecture.md](architecture.md) | wasic / modc / bindgen / hybrid; pluggable wabt+binaryen backends; build & merge pipeline; Canonical ABI alignment; the `wast` spec runner |
| [testing.md](testing.md) | How to run every suite; **which suites a given change reaches** (impact map); current pass counts; **the `wast_tests` per-file baseline gate (100 known failures PINNED across 15 files, not excluded — real GC/ref-types conformance gaps, visible rather than masked) and the `engine_cross_check` multi-engine gate**; the vendored spec-corpus provenance; runner gotchas; **the vendored spec-testsuite provenance + re-sync recipe, and why `proposals/threads/` is frozen upstream rather than stale**; the pre-publish checklist — including that **`deno doc --lint` is NOT a doc-coverage check** (parse `deno doc --json` instead). **Both baselines were re-recorded 2026-08-27 and are CURRENT** — wast at 288 files / 37,370 assertions, engine ALL ON BASELINE (wasmtime 364/12, wasmer 363/13). **Gate order is load-bearing: `wasi_tests` → `engine_cross_check_tests` → `wast_tests`**, because the engine gate grades the corpus wasi regenerates |
| [compiler-bugs.md](compiler-bugs.md) | Live bug log — root cause + fix + regression test for every bug found. **Read before debugging anything.** Holds the **2026-08-25 `try_table` migration (legacy EH is gone; V8 and wasmtime now byte-identical)** and, in the same batch, **the worst failure ladder this repo has produced: six regexes that hard-coded wabt's folded `(i32.const N)` silently matched nothing on wabt-ts 1.4.1, which disabled data relocation and seated the heap inside static data — surfacing as a HANG, not an error.** Also the `fd_write` short-write fix, the 5-pass code audit (9 fixed, 1 retracted), and the wabt-ts backend findings |
| [design-decisions.md](design-decisions.md) | Load-bearing invariants that must NOT be silently reverted. **Read before changing codegen or bumping a backend** — holds the **single merged backend `@jrmarcum/binaryang@1.5.1` (wabt-ts + binaryen-ts merged 2026-08-27; two specifiers, `compat/wabt` + `compat/binaryen`, ONE exact version that must move together) and why the caret came off**, the **`minimumDependencyAge` keep-it directive (2026-08-25)**, the invariant that **`grep -rn -F '\(i32\.const' src/*.ts` must come back empty** (never require a bracketing you did not emit), versioning (odometer sequencing, NOT a semver signal), the fmt/CRLF `.gitattributes` rule, and the JSR provenance elimination list |
| [roadmap.md](roadmap.md) | Release status and phase status — **latest is v2.0.1 (2026-08-27): standard EH via `try_table`, the merged `binaryang` backend, and a merged-module memory-corruption fix; provenance on it is UNVERIFIED**; the README roadmap-table convention. **A BREAKING change goes in its own `### ⚠️ Breaking Changes` table above Feature Status, never as an ordinary row** (owner directive 2026-07-30) |
| [next-work.md](next-work.md) | Short "what to pick up next" list. **Top of the list: read v2.0.1's provenance result — the first release since the cache-bust fix, so the first whose answer can be believed.** Then `br_on_cast` coordination with binaryang, the `ref_null` runner fix (ours), and the Windows `os error 32` Go flake |
| [capabilities.md](capabilities.md) | Tier-1 stdlib capability libraries (Set, Map, Date, JSON, RegExp) and virtual `wasmtk:<cap>` imports |
| [polyglot-producers.md](polyglot-producers.md) | Go / Rust / Zig producers: CLI verbs, build invariants, mergeability rules, asyncify |
| [dynrt-design.md](dynrt-design.md) | The own dynamic runtime (`dync`) — value model, interpreter, `any` integration, GC |
| [async-design.md](async-design.md) | Promise/async design and its invariants |
| [math-cr-sweep.md](math-cr-sweep.md) | The correctly-rounded `mathlib` sweep: dd framework, recipe, gotchas, oracle harness |
| [stdlib-bundling-brief.md](stdlib-bundling-brief.md) | On-demand stdlib bundling design brief (§1–§7d) |
| [vision.md](vision.md) | Polyglot ecosystem vision; "TypeScript as a DLL"; loader strategy; repo map |
| [wasic-modularization-plan.md](wasic-modularization-plan.md) | Plan of record for decomposing the `src/wasic.ts` monolith |
| [component-model-discussion.md](component-model-discussion.md) | DRAFT/OPEN — polyglot monorepo component model; not implemented |
| [legacy-claude-archive.md](legacy-claude-archive.md) | The pre-2026-07-30 `CLAUDE.md` (228 KB) verbatim — historical phase notes only; **history, not policy** |

## Related files outside cmem

- `README.md` — the public, user-facing doc (install, usage, capability surface, examples).
- `CLAUDE.md` — small auto-loaded pointer file; machine-local, gitignored.
