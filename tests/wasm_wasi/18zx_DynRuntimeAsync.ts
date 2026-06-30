// @test-pipeline
// #14 Route A 2e.10 — dynrt async/await + Promise (SYNCHRONOUS model — the re-parse interpreter has no
// event loop). Compiles the dynrt library (modc) + a self-checking driver (wasic), then runs it. A clean
// `run` proves: an `async function` (id=-4) runs to completion and wraps its result in a settled Promise
// (rejected if it throws); `await` unwraps a settled promise (throws on rejected, integrating with the
// 2e.6 try/catch machinery); `.then`/`.catch`/`.finally` run their callbacks immediately and re-wrap;
// `Promise.resolve`/`reject`/`all`. (No deferred microtasks — there is nothing async to defer here.)
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_async.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_async.wasm
