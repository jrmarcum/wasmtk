# Async / Promise design (roadmap #13) — DESIGN + 13.1a/13.2/13.3a/13.3b SHIPPED

**Status:** DESIGN + **sub-phases 13.1a + 13.2 + 13.3a + 13.3b IMPLEMENTED (2026-06-15)**. Roadmap
track **#13 — Promise/async** (brief §5 / §7-#5). The owner chose "design doc first," then "start the
tasks." Suite **313/313**.

**13.1a shipped (suite 309→310):** `async` functions with `Promise<T>` returns (i32/f64); `await`
on async calls (with/without params) and on `Promise.resolve(...)`; un-annotated `const x = await …`
inference. Inline runtime (`getPromiseRuntimeWat`, gated by `needsPromiseRuntime`); promise object
in the canonical `result<T,E>` layout (§3.1). async-`Promise<void>` fns are plain void fns (body
runs eagerly) per §2.A. Test `54_AsyncBasic.ts`.

**13.2 shipped (suite 310→311, output-verified, zero regressions):** `.then(cb)` with a NAMED
callback (or a non-capturing arrow already lifted to one) — registers a reaction that runs as a
**microtask** (correct ordering vs sync code; FIFO across reactions), value-returning + void
callbacks, chained `.then().then()`, f64 callbacks, and `await` of a `.then` result. Microtask queue
= a FIFO linked list (`$__mt_head`/`$__mt_tail` globals, 16-byte reaction records); `$__drain_microtasks`
runs reactions via `call_indirect (type $ftype_i32_i32_r_void)` through **per-call-site trampolines**
(`genThenTrampoline`, registered in the funcref table). Drain runs inside `await` and once at the end
of `_start`. Test `55_AsyncThen.ts`. New touchpoints (all `src/wasic.ts`): `promiseTrampolineWat`/
`promiseThenCounter`; runtime gained `$__promise_enqueue`/`$__promise_then`/real `$__drain_microtasks`;
`genThenTrampoline` + `isPromiseExpr` (receiver-recursive, NOT a loose `.then(` substring match);
`emitExpr` `.then` handler + `emitStatement` fire-and-forget `.then` routing; `promiseInnerTypeOf`
`.then`/guarded-resolve cases; `emitFuncrefTable` forces a minimal table + `getPromiseRuntimeWat`
registers the reaction functype when `needsPromiseRuntime` (so await/resolve-only programs validate);
`_start` drain injection. **Two bugs found+fixed during 13.2:** (1) `isPromiseExpr` loose `.then(`
match mis-routed `const y = p.then(f)` as a statement → made it receiver-recursive; (2) greedy
`Promise.resolve(…)` regex in `promiseInnerTypeOf` swallowed a `.then` chain → added the
`parenDepthNeverNegative` guard.

**13.3a shipped (suite 311→312, output-verified, zero regressions):** `Promise.reject(reason)` (a
settled-rejected promise carrying the string reason) + **rejection→exception** — a rejected `await`
re-throws the reason via `(throw $__exn_tag …)`, caught by a surrounding `try/catch` (reuses the
Phase-15 EH machinery). Also: an **async function body that throws** is caught at the `await` site
**for free** under the eager model (eager execution + WASM exception propagation — no reject-wrapping
needed). Gated by a separate `needsPromiseReject` flag so resolve/then-only programs stay
exception-free: when set, the `await` helpers gain the `disc==1 → throw` check, `$__promise_reject`
is emitted, and `$__exn_tag` is declared. Test `56_AsyncReject.ts`. Known limit: `await
Promise.reject(x)` uses the i32 await helper (default), so an `f64`-typed assignment target would
mismatch — use an i32 context, or rely on the value never being read (it throws first).

**13.3b shipped (suite 312→313, output-verified, zero regressions):** `.catch(onR)` / `.finally(onFin)`
rejection *reactions* + `.then(onF, onR)` two-arg form. `genThenTrampoline` was generalized to
`genReactionTrampoline({kind: then|catch|finally, t, u, onF?, onR?, onFin?})` — a **dual-path**
trampoline that reads `src.disc` (+8) and branches: `then` fulfilled→`onF(value:T)` / rejected→propagate
(or `onR` when `.then(onF,onR)`); `catch` fulfilled→passthrough / rejected→`onR(reasonPtr,reasonLen)`
(reason is the STRING at payload@16+plen@24, so `onR` is a string-param fn); `finally` runs `onFin()`
on both paths then passes the settlement through. Passthrough/propagate use a type-agnostic
`copySettlement` (full 32-B image, 8-B payload via `i64`). The fixed `(src,result)→void` reaction
functype is unchanged. `.catch`/`.finally` reuse the existing `$__promise_then` runtime (it just
registers a reaction regardless of `src.disc`) — no new runtime fn. The `emitExpr` `.then` handler and
the statement router were widened to `(then|catch|finally)` with `splitArgs` (handles `.then(onF,onR)`);
`isPromiseExpr` recurses through all three; `promiseInnerTypeOf` adds `.catch`→`onR.result` and
`.finally`→src inner type. Test `57_AsyncCatch.ts` (`.catch` recover + fulfilled-passthrough, `.finally`
passthrough, `.then(dbl).catch(recover)` chain). Plain `.then` trampolines are now dual-path too
(propagate on rejected) — strictly more correct; 55's sources are fulfilled so output is unchanged.

**Not yet done:** 13.1b promise-holding-var inner-type tracking (`const p = f(); await p` / `.then` on a
*capturing-closure* callback — 13.3b callbacks are still NAMED fns only); 13.4 `Promise.all`/`allSettled`;
13.5 lift the `hybrid` async exclusion. See §5.

## RESUME POINT — next session (paused 2026-06-15)

**State:** 13.1a + 13.2 + 13.3a + 13.3b done; full `tests/wasm_wasi` suite **313/313**, output-verified,
zero regressions; bindgen 104/104, jstyper 73/73. Tests: `54_AsyncBasic` / `55_AsyncThen` /
`56_AsyncReject` / `57_AsyncCatch`. All code in `src/wasic.ts`. Load-bearing invariants recorded in
[design-decisions.md](design-decisions.md) → "Async / Promise (#13)" (incl. the dual-path trampoline rule).

**Next task — 13.1b: promise-holding-var inner-type tracking + capturing-closure callbacks.**
- Track the inner type `T` of a local that holds a promise (`const p = asyncFn(); await p` / `p.then(cb)`):
  add a side-table (e.g. `promiseInnerType: Map<varName, WatType>`) populated when a `const/let` is
  assigned a promise expr (`isPromiseExpr(rhs)` → `promiseInnerTypeOf(rhs)`); `promiseInnerTypeOf`/
  `isPromiseExpr` consult it for a bare identifier. Today a promise-holding local defaults to i32.
- Allow `.then`/`.catch`/`.finally` callbacks to be **capturing closures** (currently NAMED fns only —
  the react routers require `/^\w+$/` + a `this.functions` match). The trampoline would need to pass the
  closure env ptr; mirror the Phase-44 funcref-array closure-call path.
- Test `58_AsyncPromiseVar.ts`: `const p = compute(); const v = await p;` + `p.then(cb)`; capturing arrow cb.

**After 13.1b:** 13.4 `Promise.all`/`allSettled` (i32/f64 element types v1); 13.5 lift the `hybrid`
async exclusion (`src/hybrid.ts` ~line 90/166). README stays untouched until the async surface is
feature-complete enough to document.

**Dev environment (must-do each session):**
- The test runner shells out to a GLOBAL `wasmtk` (`WASMTK_BIN="wasmtk"`). This machine has no global
  install by default — install it and re-install after EVERY `src/` change, else the suite runs stale code:
  `deno install -g --allow-read --allow-write --allow-run --allow-env --allow-ffi --allow-net --config deno.json --force -n wasmtk main.ts`
  then `export PATH="$HOME/.deno/bin:$PATH"`.
- Fast inner-loop (no reinstall needed): `deno run --allow-read --allow-write --allow-run --allow-env main.ts wasic <f.ts>` then `… main.ts run <f.wasm>`.
- ALWAYS output-diff ts-run vs wasm-run (`deno run <f.ts>` vs the wasm). Full suite: `deno run -A tests/wasi_tests.ts` (capture to a file — don't `| tail`, it truncates; ~3–5 min; runs in background here).
- Filter one phase: `… tests/wasi_tests.ts tests/wasm_wasi "^5[4-7]_"`.

**After 13.3b:** 13.4 `Promise.all`/`allSettled` (i32/f64 element types v1); 13.1b promise-var inner-type
tracking + capturing-closure callbacks; 13.5 lift the `hybrid` async exclusion (`src/hybrid.ts` ~line
90/166). README stays untouched until the async surface is feature-complete enough to document.

---

**Design (below) — agreed before coding.** No design questions remain open (see §7).

**Owner scope decisions (2026-06-15) — ALL RESOLVED after the value-engineering pass:**

- **Lowering strategy:** **Approach A (microtask-drain) for v1, expand to Approach B (state-machine
  CPS) later** to add true-interleaving capability. A's runtime is reused by B unchanged (only the
  async-body lowering changes), so A is not throwaway.
- **API surface for v1:** `async`/`await` + `Promise.resolve`/`Promise.reject`; `.then`/`.catch`/
  `.finally`; `Promise.all`/`Promise.allSettled`. (`Promise.race`/`any` explicitly **out** of v1.)
- **Execution target:** **standalone WASI, self-contained** — `wasic` `_start` embeds the microtask
  loop and drains it at end of `_start`. No host-driven event loop in v1. (`modc` library + host
  loop is a later track.)
- **Value-slot representation (§3.1):** **type-tagged union internally** (generic runtime, heterogeneous
  promises) **+ the settled-value memory image laid out as the Canonical ABI `result<T,E>`**
  (discriminant i32 + naturally-aligned payload) **+ opaque promise handles**. Chosen for **maximum
  forward-compatibility** — same "align layer-1 representation now, container later" bet as the
  string-return ABI (`polyglot-producers.md` §1). Free now; makes a future WASI-P3 / async-component
  lift mechanical.
- **Runtime delivery (§3.6):** **inline WAT helpers emitted on demand** (gated by a
  `needsPromiseRuntime` flag, like `needsStringHelpers`/`needsMathLib`/`dynArrHelpers`), **NOT a
  merged `wasmtk:promise` capability.** *(Corrected 2026-06-15 from the earlier capability-library
  rec — see §3.6 for the reason: the `wasmmerge` `call_indirect` guard at `src/wasmmerge.ts:728`
  rejects any merged module containing `call_indirect`, and the Promise runtime fundamentally needs
  `call_indirect` to invoke reaction callbacks. Set/Map/JSON merge cleanly only because they are
  callback-free.)* The **locked invariant still holds**: the generic runtime NEVER introspects
  callbacks — it stores/invokes opaque `(trampoline_idx, env_ptr)` pairs through one fixed
  `$__promise_reaction` functype — so Approach B drops in (B's frame-resume thunk uses the same slot).
  Inline delivery actually *simplifies* this: runtime + compiler-emitted per-`T` trampolines live in
  **one module sharing one function table and one type section**, so `call_indirect` just works — no
  merge, no virtual import, no allocator unification (the runtime calls the main module's `$__malloc`
  directly). Tree-shaking is preserved at the function level (emitted only when async is used; `-Oz`
  strips unreached helpers).
- **Policies (§3.5):** **unhandled rejection → warn to stderr** (exit unchanged — matches the project's
  existing exit-0-on-uncaught posture in `utils.ts`; future `--strict-async` knob may trap/exit-nonzero).
  **Deadlock (queue empty, awaited still pending) → trap + diagnostic**, but routed through a single
  `__on_quiescent()` seam so the later host-driven mode can rebind it to *yield-to-host* without rework.

**Cross-language note (why the canonical choices, not foreign interop):** there is **no cross-language
async ABI in WASI-P1** (async-across-components is WASI-P3: `wasi:io/poll` + the async Canonical ABI),
and the runtime is callback-bearing so it lives **inline in the main module** (not mergeable — §3.6) —
i.e. v1 async is **strictly intra-module**. "Max compatibility" therefore means *canonical-shaped
in-memory representation now* (so a future P3 lift is a wrap), **not** making the wasic Promise
callable from Rust/Go/Zig today.

---

## 1. The governing constraint (read this first)

A WASI Preview 1 module is **single-stack, single-threaded, and has no event loop and no external
async source** — no timers, no network, no host callbacks. True suspension (awaiting a value that
is settled *later* by something outside the module) is **impossible** without the WASM
**stack-switching proposal**, which the project already lists as out-of-scope
(`roadmap.md` "Out of scope without more WASM proposals").

Consequence: **async in this target is deterministic deferral with ordering guarantees, not
concurrency.** A Promise can only ever be settled by *code running* (an async body completing, a
`.then` reaction firing, or an explicit `resolve`/`reject`). There is nothing to "wait for" that
isn't itself just more synchronous code. Every async function therefore *can* run to completion
synchronously; the only thing Promises add over plain calls is **microtask ordering**.

This reshapes "implement async": v1 is a **mini Promises/A+ runtime + a lowering that resolves
synchronously by draining the microtask queue**, not a coroutine/scheduler with real suspension.

---

## 2. Two strategies

### Approach A — Microtask-drain (RECOMMENDED for v1)

- Ship a **Promise runtime** (heap promise objects + a global microtask queue + a `__drain` loop),
  congruent with the existing Set/Map/JSON capability libraries.
- `async function f(): Promise<T>` compiles to a normal function returning a **promise pointer
  (i32)**. The body runs **eagerly to completion**; `return v` ⇒ return a *fulfilled* promise, a
  thrown error ⇒ return a *rejected* promise.
- `await p` ⇒ `__promise_await(p)`: if `p` is already settled (the common case under eager
  execution), take its value; if pending, **drain microtasks until `p` settles**, then take the
  value. A rejected `p` re-`throw`s the reason (integrates with the Phase-15 exception machinery so
  `try/catch` around `await` works).
- `.then`/`.catch`/`.finally` register reactions; reactions on a settled promise are enqueued as
  microtasks; the queue is drained at each `await` and once more at the end of `_start`.

**Covers:** sequential `await`s computing a value, `.then`/`.catch` chains, `Promise.all`/
`allSettled` over computed promises — i.e. essentially all *pure-compute* async code.

**Documented gap:** microtask **interleaving order across concurrently-pending async functions** is
not preserved, because async bodies run eagerly rather than suspending. Example that diverges from
Node/V8 ordering:

```ts
let log = "";
async function a() { log += "1"; await Promise.resolve(0); log += "3"; }
async function b() { log += "2"; }
a(); b();          // V8: "123"   (a suspends at await, b runs, then a's continuation)
                   // A:   "132"   (a runs eagerly through its await, then b)
```

This pattern (observing interleaving via shared mutable state) is the *only* class A gets wrong, and
the cases that genuinely *require* suspension are impossible under any approach here without
stack-switching. Honest framing, same spirit as "JSON integer-number v1" / "RegExp v1 subset."

**Cost / risk:** ~1–2 weeks; fits wasic's capability-library + inline-helper patterns. Low risk.

### Approach B — Full state-machine (CPS) lowering (LATER / general)

Split each async body at every `await` into a resumable state machine with a **heap-allocated frame**
holding live locals, and register continuations on the awaited promise. This is what Babel
regenerator / Rust async / C# do. Fully general: correct interleaving, `await` inside loops /
branches / `try-catch`.

**Cost / risk:** multi-week; the hardest single feature in the compiler. wasic's codegen is
regex/string-based with no real CFG/SSA, so splitting control flow at await points across loops and
persisting locals into a frame struct is high-effort and error-prone. Recommended **only if** a real
need for true interleaving appears after A ships.

**Recommendation:** ship **A** for v1; keep B documented as the escalation path. A's runtime
(promise objects, queue, combinators, rejection↔exception bridge) is **reused unchanged** by B — B
only replaces the *lowering* of async bodies, not the runtime. So A is not throwaway work.

---

## 3. Approach A — concrete design

### 3.1 Promise heap object

A promise is a bump-allocated struct. The **handle the program passes around is an opaque i32** —
today it equals the base ptr, but user code must never do pointer arithmetic on it, so we can later
intern it into a component resource/future handle table (the `polyglot-producers.md` ADR rule
"model resources as opaque handle indices NOW") without touching user code or codegen call sites.

The value slot is a **type-tagged 8-byte union** so one generic runtime can hold `Promise<i32>`,
`Promise<f64>`, `Promise<string>`, or `Promise<ptr>` (struct/array) without monomorphizing the
runtime. **Crucially, the settled-value sub-image (`disc` + `payload`) is laid out as the Canonical
ABI `result<T, E>` shape** — discriminant i32 then naturally-aligned payload — so a fulfilled
`Promise<T>` *is* `result<T, string>::ok(T)` and a rejection is `::err(reason)`. This is the
"align the layer-1 representation now, defer only the container" bet (`polyglot-producers.md` §1)
applied to promises: a future WASI-P3 / async-component lift reads existing memory with no re-layout.

| Offset | Field | Notes |
| --- | --- | --- |
| +0 | `state` i32 | 0=pending, 1=settled. Scheduling state — internal, NOT part of the canonical sub-image. |
| +4 | `vtype` i32 | 0=i32, 1=f64, 2=string(ptr+len), 3=ptr(struct/array/promise). Internal dispatch tag for the generic runtime. |
| +8 | **`disc`** i32 | **Canonical `result` discriminant: 0=ok (fulfilled), 1=err (rejected).** Start of the lift-ready sub-image. |
| +12 | pad i32 | alignment to 8 for the f64/i64 payload case |
| +16 | **`payload`** 8 bytes | canonical payload: i32 / f64 / string-ptr (len in +24) / ptr — read per `vtype`/`disc` |
| +24 | `plen` i32 | string byte length when payload is a string (ok with `vtype==2`, or the err reason) |
| +28 | `reactions` i32 | head ptr of the reaction list (dynamic `i32[]` of reaction-record ptrs), 0 if none. Internal. |

Note the deliberate split: `state`/`vtype`/`reactions` are **internal scheduling fields**; `disc` +
`payload` (+`plen`) are the **boundary value image** in canonical `result<T,E>` form. A future lift
projects the `[disc, payload]` window; the scheduling fields are dropped. (Exact offsets/padding are
an implementation detail to finalize at 13.1; the invariant is: canonical `result` window is a
contiguous, naturally-aligned sub-region.)

A **reaction record** (one `.then` registration):

| Offset | Field | Notes |
| --- | --- | --- |
| +0 | `onF_tramp` i32 | per-T trampoline table index for the fulfill callback (0 = none / passthrough) |
| +4 | `onF_clo` i32 | the user closure ptr (or func-table idx) for the fulfill callback |
| +8 | `onR_tramp` i32 | trampoline for the reject callback |
| +12 | `onR_clo` i32 | closure for the reject callback |
| +16 | `result` i32 | the promise returned by this `.then`, settled when the reaction runs |
| +20 | `kind` i32 | 0=then, 1=finally, 2=all-element, 3=allSettled-element (for combinator glue) |

### 3.2 Microtask queue + drain

- Global `__mt_queue: i32[]` (wasic dynamic array) of *pending reaction-record ptrs* (each paired
  with the settled promise it reacts to — store the promise ptr in a parallel slot or widen the
  record). Enqueued when a promise settles and has reactions, or when `.then` is called on an
  already-settled promise.
- `__drain_microtasks()`: while queue non-empty, pop the front reaction, run it (invoke the
  appropriate trampoline+closure via `call_indirect`, settle its `result` promise with the callback's
  return value, which may enqueue further reactions). FIFO order.
- Drained: (a) inside `__promise_await` until the awaited promise settles; (b) once at the end of
  `_start` so trailing `.then` callbacks fire before exit.
- **Deadlock guard — routed through one `__on_quiescent()` seam (mode-scoped).** If `__promise_await`
  (or the `_start` final drain) finds the queue empty but a target still pending, it calls the single
  `__on_quiescent()` hook. In v1's **self-contained `_start` mode** that hook **traps with a
  diagnostic** ("awaited a promise that can never settle — no async source in WASI-P1") — the correct
  loud failure per the "no silent-wrong" rule, since with no external source the pending state is a
  *provable* deadlock. Keeping it behind one seam means the later **modc + host-driven mode** rebinds
  `__on_quiescent()` to *yield control to the host event loop* instead of trapping — no rework.

### 3.3 The central codegen challenge — generic runtime ↔ monomorphic callbacks

The runtime is generic (i32 handles, type-tagged value slot). But wasic **monomorphizes**: a
`Promise<i32>.then(v => …)` has `v: i32`, a `Promise<f64>.then(v => …)` has `v: f64`. The bridge:

- At each `.then`/`await`/combinator **call site**, the compiler knows `T` (the value type) and the
  callback's typed signature. It emits/reuses a **per-T trampoline** `(reactionValuePtr) → settle`
  that reads the generic value slot as `T` and invokes the user closure with a correctly-typed arg,
  then writes the typed result back into the result promise's value slot with the right `vtype`.
- The runtime stays type-agnostic; **all type-specific glue is inline compiler codegen** at call
  sites (same division of labor as Phase 44 function-pointer-array trampolines and the capability
  per-call-site adapters). This is the part that needs the most care and the most tests.

### 3.4 Lowering rules

| Source | Lowering |
| --- | --- |
| `async function f(p): Promise<T> { … }` | `FuncDef.isAsync=true`; result type ⇒ promise-ptr i32; body wrapped so `return v` ⇒ `return __promise_resolve_T(v)`, and an uncaught throw ⇒ `return __promise_reject(reason)` (wrap body in an internal try/catch). |
| `return expr;` (in async fn) | `return __promise_resolve_T(expr)` |
| `await expr` | `__promise_await(expr)` → drains; fulfilled ⇒ value (typed via `vtype`); rejected ⇒ `(throw $__exn_tag reason)` |
| `Promise.resolve(x)` | `__promise_resolve_T(x)` (settled fulfilled) |
| `Promise.reject(r)` | `__promise_reject(r)` (settled rejected; `r` is a string reason) |
| `p.then(onF, onR?)` | build result promise; register reaction (per-T trampolines for `onF`/`onR`); if `p` settled, enqueue; return result |
| `p.catch(onR)` | source-desugar to `p.then(undefined, onR)` |
| `p.finally(onFin)` | runtime reaction `kind=1`: run `onFin()`, pass the original settlement through |
| `Promise.all(arr)` | counter = `arr.length`; per element register a reaction storing value at index `i`, decrement; at 0 ⇒ fulfill result with the `T[]`; first rejection ⇒ reject result. v1: element types **i32/f64** (string/struct later). |
| `Promise.allSettled(arr)` | like `all` but never rejects; each slot stores a `{status, value|reason}` record; fulfill when all settle. |

### 3.5 Rejection ↔ exception integration

Promise rejection reasons are **strings** (matching wasic's existing `throw "msg"` / `throw new
Error("msg")`, whose catch-vars are strings — Phase 15). `__promise_await` on a rejected promise
emits `(throw $__exn_tag reasonPtr reasonLen)`, so:

```ts
try { const x = await mightReject(); }
catch (e) { console.log("caught:", e); }   // works via existing EH machinery
```

An async function whose body throws ⇒ the wrapper catch turns it into `__promise_reject(reason)`.
**Unhandled rejection policy (RESOLVED):** at end of `_start`, a rejected promise that never had a
`.catch`/reject handler ⇒ **warn to stderr** (via `fd_write`), **exit code unchanged**. This matches
the project's existing uncaught-error posture (`utils.ts` already catches `WebAssembly.Exception` and
exits 0 with a stderr message; run-ts parity). A future **`--strict-async`** knob may switch this to
trap / nonzero-exit for CI-failing semantics, but the default stays warn.

### 3.6 Runtime delivery — inline WAT helpers (NOT a merged capability)

**Why not a capability library (the corrected decision).** Set/Map/Date/JSON/RegExp ship as merged
`modc` capabilities because they are **callback-free** (value-in / value-out). The Promise runtime is
**callback-bearing** — `.then`/`all`/the drain loop must invoke user reactions via `call_indirect`.
But `wasmmerge` has a hard guard (`src/wasmmerge.ts:728`) that **throws on any `call_indirect` in a
merged module** (Phase 18 strips imported type sections, so a merged `call_indirect (type N)` / table
ref would dangle). Therefore the Promise runtime **cannot** be a merged capability — it must live
**inline in the main module**, where it shares the one function table and one type section with the
compiler-emitted trampolines.

**Delivery mechanism:** a `getPromiseRuntimeWat()` template emitted on demand (gated by a
`needsPromiseRuntime` flag set when async/Promise syntax is seen), appended by `emitHelpers()`
alongside `getStringHelperWat()` / `emitDynArrHelpers()` (`src/wasic.ts` ~line 13268). The runtime
is hand-written WAT (the established helper-template pattern), calling the main module's `$__malloc`
directly. Non-async programs set no flag and pay nothing; `-Oz` strips any unreached helper.

- **The one fixed reaction functype.** All reactions are invoked through a single named type
  `$__promise_reaction = (param $env i32) (param $src i32) (param $result i32)` (void). The runtime
  `call_indirect`s `(type $__promise_reaction)` over a stored `(tramp_idx, env)` pair; the per-`T`
  trampoline (compiler-emitted, monomorphic) reads the settled value from `$src`'s canonical
  `result<T,E>` window as `T`, invokes the user closure, and writes the typed result into `$result`.
- **LOCKED INVARIANT — the runtime NEVER introspects callbacks.** It only stores/invokes the opaque
  `(tramp_idx, env)` pair through `$__promise_reaction`; it must not branch on callback identity,
  body, or shape. This is what makes **Approach B drop-in**: B's per-frame *resume thunk* conforms to
  the same `$__promise_reaction` functype and goes in the same slot, so switching from eager bodies
  (A) to suspendable state machines (B) changes only compiler-emitted lowering — the runtime is
  untouched.
- **Per-T trampolines + all the lowering** are emitted inline by the compiler at call sites (§3.3),
  in the same module/table as the runtime they call.

### 3.7 `_start` integration

After the last top-level statement in `_start`, emit `__drain_microtasks()`. Top-level `await` in
`_start` lowers exactly like in-function `await` (`__promise_await`), so a standalone WASI program
can `await` at module scope.

---

## 4. Where it plugs into `wasic`

- **Source desugar pre-pass** (small): `.catch(f)` → `.then(undefined, f)`; recognize `async`
  modifier positions. Runs alongside the other `expand*` pre-passes in `transpile()`
  (`src/wasic.ts` ~line 16873+).
- **`parseFunctions`** (~line 142 pattern already tolerates `async`): set `FuncDef.isAsync`, rewrite
  result type to promise-ptr, wrap the body (try/catch → resolve/reject).
- **`emitExpr` / `emitStatement`**: handle `await`, `Promise.resolve/reject/all/allSettled`,
  `.then/.finally`; emit per-T trampolines; thread `vtype` through value reads/writes.
- **`inferInitType`**: `async` call results and `Promise.*` ⇒ promise-ptr (i32) with a tracked
  inner type `T` (new side-table, e.g. `promiseInnerType: Map<varName, WatType>`), so `await x`
  recovers `T`.
- **Inline runtime**: a `getPromiseRuntimeWat()` hand-written WAT template + `needsPromiseRuntime`
  flag, appended by `emitHelpers()` (NOT a `modc` capability / virtual import — §3.6). Defines the
  `$__promise_*` runtime functions and the `$__promise_reaction` functype in the main module.

---

## 5. Phased implementation plan (each ships with output-verified tests)

| Sub-phase | Scope | Test(s) |
| --- | --- | --- |
| **13.1a** ✅ | Promise object (canonical `result<T,E>`) + `resolve` (i32/f64) + `await` (drain no-op) + async-fn-returns-promise + `Promise.resolve` | ✅ `54_AsyncBasic.ts` (async fn value, sequential `await`, `await Promise.resolve`, f64, un-annotated infer) |
| **13.2** ✅ | `.then(namedCb)` (per-`T` trampolines via `call_indirect`) + microtask queue + drain (in `await` and at `_start` end) | ✅ `55_AsyncThen.ts` (ordering vs sync, FIFO, value/void cb, chained `.then().then()`, f64, `await` of a `.then`) |
| **13.1b** | promise-holding-var inner-type tracking (`const p = f(); await p` / `p.then`); `.then` on a capturing-closure callback | `await p` via a local; capturing arrow cb |
| **13.3a** ✅ | `Promise.reject` + rejection→exception (`await` rejected → `throw`, caught by `try/catch`) + async-body-throw (free, eager model) | ✅ `56_AsyncReject.ts` |
| **13.3b** ✅ | `.catch`/`.finally` rejection *reactions* (string reasons, dual-path trampoline) + `.then(onF,onR)` | ✅ `57_AsyncCatch.ts` (`.catch` recover + fulfilled-passthrough, `.finally` passthrough, `.then(dbl).catch(recover)` chain) |
| **13.4** | `Promise.all` / `allSettled` (i32/f64 element types v1) | `all` of computed promises; `allSettled` mixed fulfil/reject |
| **13.5** | Lift the `hybrid` async exclusion — route async fns whose awaited graph is self-contained to the wasic core (`src/hybrid.ts` line 90/166) | hybrid async fixture compiles instead of being skipped |

**Test discipline (project rule):** the runner judges by per-step **exit code**, but a broad codegen
change can be green-but-wrong — **output-diff ts-run vs wasm-run** for every async test
(`testing.md` / the Phase-51.3 process note). Add a `tests/wasm_wasi/NN_*.ts` per sub-phase.

---

## 6. Known v1 limitations (document in README on ship)

1. **Interleaving order** across concurrently-pending async functions not preserved (eager body
   execution) — §2.A example. Sequential/`.then`-chained ordering *is* correct.
2. **No real async sources** (timers/I/O); awaiting a never-settled promise traps with a diagnostic
   (the deadlock guard), not a hang.
3. **`Promise.all`/`allSettled` element types** limited to i32/f64 in v1 (string/struct later).
4. **`Promise.race`/`any`** not in v1 (deferred).
5. **modc library + host-driven event loop** not in v1 (standalone WASI only).

---

## 7. Decisions (ALL RESOLVED 2026-06-15 — value-engineering pass)

1. **Strategy:** ✅ **Approach A for v1, expand to B later.** A's runtime is reused by B unchanged.
2. **Value-slot:** ✅ **type-tagged union internally + settled value as Canonical ABI `result<T,E>`
   + opaque handle** (§3.1). Canonical chosen for maximum forward-compatibility (future P3 lift = wrap).
3. **Runtime delivery:** ✅ **inline WAT helpers** (`getPromiseRuntimeWat()` + `needsPromiseRuntime`),
   NOT a merged capability — the `wasmmerge` `call_indirect` guard forbids a callback-bearing merged
   module (§3.6). Locked "never introspects callbacks" invariant preserved so B is drop-in.
4. **Unhandled rejection:** ✅ **warn to stderr, exit unchanged** (matches `utils.ts` posture); future
   `--strict-async` knob optional (§3.5).
5. **Deadlock:** ✅ **trap + diagnostic via the `__on_quiescent()` seam** (mode-scoped so the future
   host mode rebinds to yield-to-host) (§3.2).

No open questions remain blocking sub-phase 13.1. Implementation-time details still to finalize (not
blockers): exact promise-struct offsets/padding (§3.1), the per-`T` trampoline emission mechanism
(§3.3), and whether `Promise.all` element types beyond i32/f64 land in 13.4 or later.

---

## 8. Why this is unblocked and self-contained

Track #13 is gated only by Phase 51 (language hardening), which is **complete** — and it *lowers
onto* exactly the hardened paths (struct layout, field access, closures + `call_indirect` through
named functypes, exception machinery, on-demand inline WAT helpers). It needs **none** of the
polyglot loaders (orthogonal/ungated) and shares its runtime with the future Approach B, so no work
here is throwaway.
