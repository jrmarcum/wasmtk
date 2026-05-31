// Tier-1 stdlib capability — Date (UTC integer calendar math) as a leaf modc library
// (wasmtk-stdlib-bundling-brief §5 / §7 work-item #3, third deliverable).
//
// Unlike the Set/Map capabilities (shared-heap, hold live structures), Date is a *leaf*:
// pure value-in / value-out integer math with no heap allocation and no mutable state. The
// merge is therefore a straight function splice — the Stage 0.6 allocator-unification pass
// is a no-op here. This exercises the "leaf capability merged when used" path from §5.
//
// The civil<->days conversions use Howard Hinnant's exact-integer algorithms, valid across
// the whole proleptic Gregorian calendar (including pre-epoch / negative day counts).
//
// Pipeline:
//   1. modc  — compile the Date capability library  → date_lib_modc.wasm
//   2. wasic — compile the driver (imports the .wasm); the merge splices the library
//   3. run   — execute; the driver is self-checking and traps (nonzero exit) on any wrong
//              result, so this step's success proves Date semantics, not just "it ran"
//
// Exercises: leap-year rules (4/100/400), days-in-month, civil→day-count, weekday, and the
// day-count→civil round-trip — including a leap day (2024-02-29) and a pre-epoch date
// (1969-12-31 → -1).
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/date_bundle/date_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/date_bundle/main_wasic.ts
// @step run ../wasm_wasi_bundle/date_bundle/main_wasic.wasm
