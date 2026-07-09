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

- **binaryen-ts 1.4.3** is live on JSR with provenance (liveness-minimized asyncify saving + the
  **WT-2k binary-decoder reorder fix** that made NESTED goroutines work — the true root cause of the
  nested crash, NOT asyncify; 1.4.2 was cut but its publish failed a JSR type-check, re-shipped as
  1.4.3). binaryen-ts suite **405/405**.
- **wasmtk** working tree is committed on backend binaryen-ts 1.4.3 (pin `^1.4.3`), NOT yet cut as a
  new version (still v1.11.3 on JSR — a v1.11.4 release with the nested fix + B-items is pending).
  Suites green: wasi **375/375**, go_merge 7/7, go_bindgen 7/7, **go_asyncify 12/12** (incl. nested),
  hybrid 10/10.
- **B backlog:** B3/B4/B5 all DONE (2026-07-09); B6 deferred (no consumer); A-items all done.
