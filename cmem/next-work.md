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

3. **Broaden goroutine-Go validation — ✅ DONE (2026-07-09).** `tests/go_asyncify_tests.ts` is now
   table-driven over the full goroutine surface through the forced in-house path: worker-pool
   (`sum: 30`), `select`/unbuffered (`select-total: 300`), `time.Sleep` (`sleep-result: 42`),
   `sync.WaitGroup`+`Mutex`+closure+defer (`wg-counter: 45`), 3-stage fan-out pipeline
   (`pipeline-total: 55`) — 11/11. **FOUND A REAL BUG** doing so → see B4. `nested/` (suspend inside
   a suspend) miscompiles under the in-house pass (`memory access out of bounds`) but works via
   external `wasm-opt`; it's kept as a CONTROL and excluded from the forced list until B4 lands.
4. **asyncify nested-suspension correctness + liveness-minimized local saving** (binaryen-ts) —
   **PROMOTED to correctness (2026-07-09):** B3 proved the pass MISCOMPILES nested suspension (a
   goroutine that blocks on `inner.Wait()` inside another suspending goroutine) → runtime OOB, even
   at 2×2=4 goroutines, while external `wasm-opt --asyncify` on the same TinyGo output is correct.
   Corroborating: in-house output is ~3× larger (56 KB vs 19 KB) — over-instruments + saves ALL
   locals per frame (upstream saves only the live set). Fix the re-entrant unwind/rewind handling
   (and add liveness-min local saving) in binaryen-ts's Asyncify pass, then re-enable `nested/` in
   the forced in-house list. See binaryen-ts `cmem/passes.md` known-gaps + wasmtk
   `cmem/polyglot-producers.md` § "KNOWN GAP — NESTED SUSPENSION".
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

## Published state (both repos clean as of 2026-07-08)

- **binaryen-ts 1.4.1** (in-wasm asyncify-import mode) and **wasmtk 1.11.3** (goroutine wiring) are
  live on JSR with provenance. Suites green: wasi 375/375, bindgen 142, go_bindgen 7/7, go_asyncify
  3/3, binaryen-ts 403/403.
