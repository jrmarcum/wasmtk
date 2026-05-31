// Tier-1 stdlib capability — RegExp (backtracking matcher) as a leaf modc library
// (wasmtk-stdlib-bundling-brief §5 / §7 work-item #3, fifth and final Tier-1 deliverable).
//
// Like Date, RegExp is a *leaf*: value-in / value-out, no heap allocation and no persistent
// structure. The pattern and text are threaded through the recursive matcher as wasic strings
// (ptr+len), so the merge is a straight function splice (allocator unification is a no-op).
// It is, with JSON, one of the capabilities that takes string input across the merge boundary.
//
// The engine is a classic Kernighan/Pike recursive backtracking matcher generalised to
// index-based scanning. SCOPE v1: literals, `.`, char classes `[...]` (ranges, negation,
// `\d \w \s`), escapes `\d \w \s \D \W \S \n \t \r`, quantifiers `* + ?`, anchors `^ $`.
// v2 gap (documented): alternation `|`, groups/captures, `{n,m}`, lazy quantifiers,
// backreferences.
//
// NOTE: the matcher is written to never call `charCodeAt` on an out-of-bounds index, because
// wasic's `&&` is non-short-circuit and a merge-path codegen bug traps on an OOB `charCodeAt`
// nested in an `i32.and` loop condition (merge-only; the standalone .wasm is correct). See
// CLAUDE.md / cmem § "RegExp / merge OOB-charCodeAt bug".
//
// Pipeline:
//   1. modc  — compile the RegExp capability library  → regex_lib_modc.wasm
//   2. wasic — compile the driver (imports the .wasm); the merge splices the library
//   3. run   — execute; the driver is self-checking and traps (nonzero exit) on any wrong
//              result, so this step's success proves RegExp semantics, not just "it ran"
//
// Exercises: literals + unanchored search, reSearch start/reEnd span, anchors `^`/`$`, `.`,
// quantifiers `* + ?` (incl. greedy backtracking), char classes with ranges + negation,
// `\d \w \s` shorthands, and a small `\w+@\w+` pattern — all over the shared heap.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/regex_bundle/regex_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/regex_bundle/main_wasic.ts
// @step run ../wasm_wasi_bundle/regex_bundle/main_wasic.wasm
