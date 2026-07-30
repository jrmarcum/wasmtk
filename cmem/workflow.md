# Working process (the loop we actually run)

The end-to-end loop for a stress-test batch, from a fresh context to a published release. Written
down 2026-07-30 so it survives a context boundary — it produced 16 compiler-bug fixes and three
releases (v1.11.8 → v1.11.10) across Phases 22–30 and is worth keeping intact.

The *testing* half (where tests go, phase filter then full suite, verifying pre-existing failures)
lives in [testing.md](testing.md) § "Stress-test batches" and § "Which suites to run for a given
change". This file covers the git/release half and the traps.

## Context boundaries

**One context per batch.** Cut at the natural boundary: after the memory update and commit. That
boundary is safe precisely because the durable knowledge is already written to `cmem/` — a fresh
session picks the invariants back up from `design-decisions.md` and the history from
`compiler-bugs.md`.

**Never split mid-batch.** Compaction during a bisection discards exactly the transient state that
matters (which probes ran, what each printed), and it gets re-derived at real cost. If an
investigation is in flight, push through to the commit.

Opening a batch needs only:

> Read `cmem/INDEX.md`. Add the following stress tests to the test suite and label them
> appropriately: `<paste>`

Session bootstrap is ~9.5 KB (`CLAUDE.md` + `INDEX.md`), so starting fresh is cheap by design —
keep it that way (see the note at the top of INDEX.md).

## The batch loop

1. **Branch off `main` first.** Never commit a batch directly to `main`.
   Naming used so far: `test/phase29-stress-2026-07-29`, `fix/stress-test-batch-2026-07-28`,
   `chore/trim-session-bootstrap` — `<type>/<short-desc>-<date>`.
2. **Add the tests verbatim** as the owner supplied them, named `NN_DescriptiveLabel.ts` for the
   phase owning the core mechanic. Don't "improve" the owner's code — it is the specimen.
3. **Run the phase filter first** (`"^29_"`). While fixing, stay in the **debug phase** — the phase
   filter plus the tests that exercise the construct being changed (see "Debug phase" below). Save
   the full suite for the regression phase, once the targeted set is green.
4. **Bisect any failure to its minimal shape** with scratch probes before touching `src/`. Most
   failures this session were NOT about the feature under test — a getter/setter test exposed
   right-associative `*`/`/`, a namespace test exposed string members. Report what it *actually* is.
5. **Fix at the root, not the symptom.** Prefer deleting a special case over adding one (the
   `Ns.member` → `Ns_member` rewrite replaced two ad-hoc resolution branches and fixed a whole
   class of string bugs for free).
6. **Add a regression test** that pins the fix AND its guards — the shapes that were already
   correct, so a future "simplification" can't silently reintroduce the bug.
7. **Regression phase — run the full gate** (see below), once the targeted set is green.
8. **Update memory** — `compiler-bugs.md` (root cause + fix + why it went untested),
   `design-decisions.md` (any new must-not-revert invariant), `testing.md` (counts),
   `roadmap.md` (working-tree entry), INDEX pointers; then README rows if user-relevant.
9. **Commit and push** the branch.

## Debug phase: run the AFFECTED tests, not the full suite

The full wasi suite takes **>10 minutes**, so iterating on it while fixing is wasteful. Two phases
(owner directive 2026-07-30):

1. **Debug phase** — run the failing stress tests plus the tests that exercise the construct being
   changed. Iterate here until they all pass.
2. **Regression phase** — only then run the whole suite set (below) to catch what the fix disturbed.

### Deriving the affected set

The runner's filter is a regex tested against the **full filename including `.ts`**
(`wasi_tests.ts:241` → `fileFilter.test(entry.name)`), so anchor with `\.ts$`, not `$`.

Grep the corpus for the SYNTAX the change affects, then turn that into a filter:

```bash
# every test that uses .join( → a runner filter
FILTER=$(grep -l '\.join(' tests/wasi/wasm_wasi/*.ts \
         | xargs -n1 basename | sed 's/\.ts$//' | paste -sd'|' -)
deno run --allow-read --allow-write --allow-run --allow-env \
  tests/wasi_tests.ts tests/wasi/wasm_wasi "^($FILTER)\.ts\$"
```

Measured on the 400-test corpus (2026-07-30):

| Change touches | Grep | Affected | Debug-phase cost |
| --- | --- | --- | --- |
| `join` handling | `\.join(` | 3 tests | **7.4 s** (vs >10 min) |
| namespaces | `namespace` | 7 tests | seconds |
| enum handling | `enum ` | 11 tests | seconds |
| string methods | `\.repeat(\|\.trim(\|\.charAt(` | 5 tests | seconds |
| `for…of` | `for (const .* of ` | 7 tests | seconds |

**When it degenerates, skip it.** `console\.log` matches 351/400 tests (87%) — for a change that
broad (most of `console_log.ts`, or the binary-op loop) the targeted set isn't meaningfully cheaper
than the full suite, so go straight to the full run. Rule of thumb: **>60 % of the corpus means
don't bother filtering.**

Always include the batch's own phase filter alongside the construct filter — the failing stress
tests are the primary signal, and a fix must not regress its own phase.

## The full gate

Per the regression-gate trigger in [INDEX.md](INDEX.md): when a bug is found/fixed, run
**everything**, including `wast_tests`. Order that works:

```bash
# 1. full wasi suite — backgrounded, it exceeds 10 minutes
deno run --allow-read --allow-write --allow-run --allow-env tests/wasi_tests.ts tests/wasi/wasm_wasi

# 2. every non-Go suite
#    bindgen bundle merge go_merge dync_conformance dync_cross_runtime
#    mod varscope wasmmerge_guard hybrid jstyper

# 3. the Go suites — ALONE (see traps)
#    go_bindgen go_asyncify

# 4. wast_tests   → expect 41 files / 12444 assertions / 0 failed
```

Always `deno task install` first, or the suites silently test the previous binary.

## The release flow

Only when the owner asks. Steps, in order:

```bash
git checkout main && git merge --ff-only <branch> && git push   # 1. merge FIRST
# 2. bump "version" in deno.json ONLY, then:
deno task update-version        # propagates to package.json + src/utils.ts VERSION
# 3. CHANGELOG entry (user-facing; lead with impact, not internals)
# 4. promote roadmap.md's working-tree entry to a Release-status section
# 5. pre-publish gate:
deno publish --dry-run --allow-dirty
deno doc --lint <the 16 deno.json entrypoints>      # MUST be clean — see traps
# 6. commit, then:
deno task publish               # tags + pushes; GitHub Actions publishes to JSR
# 7. verify: curl -s https://jsr.io/@jrmarcum/wasmtk/meta.json | grep latest
# 8. delete the merged branch (local + remote) with `git branch -d` (safe form)
```

**Releases go out from `main`**, so the tag is reachable from `main` — the owner chose this
explicitly. Publishing from a branch would leave the tag dangling if the branch were deleted.

## Commit conventions

Conventional-commit subject (`fix(wasic):`, `docs(cmem):`, `chore:`, `release:`). The body is where
the value is: **state the root cause, the concrete wrong output, why it went untested, and what was
deliberately NOT done**. Several bodies this session recorded a rejected alternative — that is the
part a future reader needs. End every commit with:

```
Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
```

## Traps that have actually bitten

- **Untracking a file AFTER switching branches deletes it.** `git rm --cached` correctly keeps the
  file on disk, but a later `git checkout main` restores the still-tracked file and the
  fast-forward merge then applies the deletion to the working tree. Merge first, then untrack — or
  do it on `main`. (Cost a restore-from-git on 2026-07-30.)
- **`grep -c` exits 1 when the count is zero**, so `… ; grep -c "FAILED"` as a script's last command
  makes a perfectly green run report a non-zero exit. Trust the runner's own summary.
- **Do NOT run the Go suites concurrently with the wasi suite on Windows** — TinyGo's build races
  the OS file lock and yields spurious `os error 32` failures that look like real regressions.
- **`deno doc --lint` must be clean across all 16 JSR entrypoints** or the JSR score drops below
  100. This has bitten twice: v1.11.4 scored 94 (missing `@module` tag), and v1.11.8 nearly shipped
  with an undocumented `scaffoldZigProject`.
- **Verify a "new" failure against a clean tree** (`git stash` + `deno task install` + re-run)
  before attributing it to your change. `bundle_tests`/`StructImport` and the string-namespace
  failures were both confirmed pre-existing this way.
- **Never run `deno fmt` broadly on the docs.** The repo is not fmt-clean (mostly CRLF), so it
  reflows untouched prose — one run produced a 1606-line diff for a 60-line change and had to be
  reverted.
- **Fix `src/wasic.ts` and `src/console_log.ts` together.** They hold parallel binary-op loops and
  parallel string handling; three bugs this session were half-fixed by changing only one.
