# Tier-1 stdlib capability libraries (Stage 0.7)

Goal (stdlib-bundling brief §5/§7-#3): author stdlib features as `modc` libraries in the wasic
TS subset, and let `wasmbundle`/`wasmmerge` merge only the ones a program references — so typed
programs get JSON/Date/Map/Set/RegExp **without** embedding QuickJS via `javyc`.

**Two regimes:**
- **Shared-heap** (Set, Map, JSON): the library builds a live structure on the **one** heap it
  shares with the importing program (allocator unification, Stage 0.6). Handles are i32 pointers.
- **Leaf** (Date, RegExp): pure value-in/value-out, no allocation; the merge is a straight
  function splice (allocator unification is a no-op).

All five share one `@test-pipeline` shape: `modc lib` → `wasic driver` (imports the `.wasm`) →
`run`. The driver is **self-checking**: on any wrong result it reads far out of bounds → WASM
trap → nonzero exit, so a passing `run` proves semantics (a wasic uncaught `throw` exits 0 and
can't fail a pipeline). Fixtures in `tests/wasm_wasi_bundle/<name>_bundle/`; pipeline tests
`tests/wasm_wasi/18c–18g`.

## Status (all shipped, 2026-05-30 / 05-31)

| Cap | Kind | Pipeline | Handle / shape | Exports |
| --- | --- | --- | --- | --- |
| `Set<i32>` | shared-heap | 18c | i32 ptr → 4-slot Int32Array `[count,cap,keysPtr,usedPtr]` + 2 bucket arrays; linear probing on `key&(cap-1)`; ×2 grow/rehash @ load 0.5 | setNew/setAdd/setHas/setSize |
| `Map<i32,i32>` | shared-heap | 18d | 5-slot `[count,cap,keysPtr,valsPtr,usedPtr]` + 3 bucket arrays; reuses Set hash core + parallel values | mapNew/mapSet/mapGet(h,k,fallback)/mapHas/mapSize |
| `Date` | leaf | 18e | none (UTC integer calendar math; Howard Hinnant civil↔days) | isLeapYear/daysInMonth/daysFromCivil/weekdayFromDays/yearFromDays/monthFromDays/dayFromDays |
| `JSON` | shared-heap | 18f | i32 handle → 4-slot Int32Array node `[tag,a,b,c]` (tag 0=null 1=bool 2=number(int) 3=string 4=array 5=object); containers reuse native dynamic `i32[]`; strings decoded into `Uint8Array` | jsonParse/jsonType/jsonInt/jsonBool/jsonArrayLen/jsonArrayGet/jsonObjectLen/jsonStrLen/jsonStrCharAt/jsonStrEq/jsonGet/jsonHas |
| `RegExp` | leaf | 18g | none (backtracking matcher; pattern+text threaded as strings) | reTest/reSearch/reEnd |

**Remaining Tier-1:** none — RegExp was the last. Next tracks (brief §7): #4 feature-level
tree-shake wiring, #5 Promise/async (compiler work), #6 hybrid type-driven routing, #7 the §6
kernel scope decision.

## Reusable wasic idioms these established

- **TypedArray view over a pointer:** `const v: Int32Array = ptr as unknown as Int32Array; v[i]=x`
  — registers a view; reads AND writes work (fixed 2026-05-30). Also `Uint8Array` (shift 0).
- **Native dynamic `i32[]` round-trip:** build with `.push`, store the ptr via `arr as unknown
  as i32`, reconstruct with `ptr as unknown as i32[]` for index/`.length`/further `push`.
- **Type-erasure casts** `as unknown as T` are stripped up front (so the inner operand keeps its
  real type) — see design-decisions.md.
- **Two-value returns** use a module-level mutable global side-channel (JSON `lastLen`, RegExp
  `lastEnd`), read immediately after the call.
- **Mutable module-level `let`** works in modc (parser cursors: JSON `pos`, etc.).
- **String input across the merge** works once the importer recovers logical param types from
  the sibling `.wit` (the string-arg-import fix).

## JSON v1 scope / gaps

null, bool, **integer** numbers, strings, arrays, objects; escapes `\" \\ \/ \b \f \n \r \t`.
v2 gap: float numbers (fractional/exponent tail is consumed but truncated) and `\uXXXX`
(backslash dropped, hex passes through). Document literal needs DOUBLE escaping in the wasic
driver: `\"`→JSON quote, `\\n`→a JSON `\n` escape the parser then decodes. The `.wasm` import and
the JSON document string must each be **single-line**.

## RegExp v1 scope / gaps

literals, `.`, classes `[...]` (ranges, negation, `\d \w \s`), escapes `\d \w \s \D \W \S \n \t
\r` + escaped literals, quantifiers `* + ?` (greedy + backtracking), anchors `^ $`. Leftmost-match.
v2 gap: alternation `|`, groups/captures `(...)`, `{n,m}`, lazy `*?`, backreferences. Engine =
Kernighan/Pike recursive backtracker, index-based; `matchHere` returns the end text index (or -1).

**RegExp is written merge-safe:** it NEVER calls `charCodeAt` on an unchecked index, because the
merge mis-encodes an OOB `charCodeAt` nested in a non-short-circuit `&&` loop condition (the
matcher works standalone but traps merged otherwise). All bounds are checked by an enclosing
`if` first (helper `atomAt` does this). See compiler-bugs.md § "merge OOB-charCodeAt".

## Regenerating a capability's artifacts

`wasmtk modc <lib>.ts` → `.wasm`+`.wat`+`.wit`; then `wasmtk wasic <driver>.ts` (merges); then
`wasmtk run <driver>.wasm`. The test runner uses the **globally installed** `wasmtk`, so after
editing `src/` you MUST reinstall:
`deno install -g --allow-read --allow-write --allow-run --allow-env --allow-net --config deno.json --force -n wasmtk main.ts`.
