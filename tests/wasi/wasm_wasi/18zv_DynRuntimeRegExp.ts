// @test-pipeline
// #14 Route A 2f.7 — dynrt RegExp (last f-series stdlib bridge). Compiles the dynrt library (modc) + a
// self-checking driver (wasic), then runs it. The driver traps on any wrong result, so a clean `run`
// proves the RegExp surface in eval source: `new RegExp(pat)` + a compact backtracking matcher (literals,
// `.`, quantifiers `*`/`+`/`?`, anchors `^`/`$`, character classes `[…]`/`[^…]` with ranges, and the
// `\d \w \s` escapes), with `re.test(str)` → bool, `re.exec(str)` / `str.match(re)` → first matched
// substring or null. (Alternation/groups/backreferences are a later increment.)
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_regex.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_regex.wasm
