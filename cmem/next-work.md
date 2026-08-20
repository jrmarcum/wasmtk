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
  `scripts/wabt-ts-bug-report.md`. **Zero failures throughout — gate still clean at 12444/0/3467** —
  this is recovery-of-coverage, not a bug to chase on our side.
- ⏳ **Decide whether to pin `*.wast text eol=lf` in `.gitattributes`.** Deliberately NOT done on
  2026-08-20 — a repo-wide checkout-behaviour change shouldn't ride along inside a corpus sync. It
  is a one-liner whenever wanted; rationale in [design-decisions.md](design-decisions.md).
- ⏳ **`docs/` and `cmem/*.md` are not `deno fmt`-clean.** `main.ts` + `src/` now are, and
  `.gitattributes` keeps them that way; the markdown was deliberately left alone (bare `deno fmt`
  mangles tables/code-fences — see [workflow.md](workflow.md)). If it is ever wanted, it needs its
  own pass with `fmt.exclude` tuned, not a blanket run.

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
