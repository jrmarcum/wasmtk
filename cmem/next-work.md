# Next-work planning note

> Actionable backlog as of **2026-07-08** (after v1.11.3 shipped: goroutine Go with no external
> binaryen). Authoritative status lives in [roadmap.md](roadmap.md); this file is the short,
> prioritized "what to pick up next" list. Prune items as they land.

## Recommended next pickup

- **B3 (broaden goroutine coverage)** — small companion to lock down the in-house asyncify (one e2e).
- **B4/B5/B6** — the remaining small hardening items (all low priority).
  (A. feature work is now all DONE — utility-types + Go mergeable-leaf both shipped 2026-07-08.)

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

3. **Broaden goroutine-Go validation** — the in-house asyncify path has ONE e2e
   (`tests/go_asyncify_tests.ts`, a channel worker-pool → `sum: 30`). Add coverage for `select`,
   `time.Sleep`, `sync.WaitGroup`/`Mutex`, nested goroutines, and a larger program, to confirm the
   pass handles the full TinyGo goroutine surface. Small, worthwhile confidence. Force the in-house
   path with `WASMTK_GO_BINARYEN_ASYNCIFY=1` (works even with a real `wasm-opt` on PATH).
4. **asyncify liveness-minimized local saving** (binaryen-ts) — the pass saves ALL original locals
   per frame; upstream saves only the live set (smaller coroutine frames). Optimization, not
   correctness. See binaryen-ts `cmem/passes.md` known-gaps.
5. **hybrid nested-backtick-in-`${…}`** — the one documented residual edge in the context-aware
   hybrid call-rewriter (a template literal nested inside an interpolation). Rare, low priority. See
   design-decisions.md § "hybrid call-rewriting … MUST be context-aware".
6. **asyncify list-options ↔ binary-parse name retention** (binaryen-ts) — add/remove/only-list
   options key on internal `$funcN` names, so they don't match real symbols on a _binary-parsed_
   module (the binary reader drops the name section). Only needed if we ever expose asyncify lists
   on parsed input — the TinyGo path doesn't use lists. Deferred until there's a consumer.

## C. Blocked / deferred (not actionable now)

7. **P2 component container** — waiting on browser-native WASI P2 / Component Model support. The ABI
   is already forward-aligned (callee-allocated string returns + `cabi_post_<name>`), so it's a thin
   terminal `wasm-tools component new` wrap when the time comes; today a P2 wrap buys browser
   consumers nothing (they'd `jco transpile` it back to core wasm anyway). See roadmap.md P2 row.

## Published state (both repos clean as of 2026-07-08)

- **binaryen-ts 1.4.1** (in-wasm asyncify-import mode) and **wasmtk 1.11.3** (goroutine wiring) are
  live on JSR with provenance. Suites green: wasi 375/375, bindgen 142, go_bindgen 7/7, go_asyncify
  3/3, binaryen-ts 403/403.
