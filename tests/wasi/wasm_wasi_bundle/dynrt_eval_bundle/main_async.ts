// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2e.10: async/await + Promise in eval
// source, SYNCHRONOUS model (the re-parse interpreter has no event loop). A Promise is a SETTLED value
// wrapper; an `async function` runs to completion and wraps its result (rejected if it throws); `await`
// unwraps a settled promise (throws on rejected); `.then`/`.catch`/`.finally` run callbacks immediately;
// `Promise.resolve`/`reject`/`all`. Awaiting a rejected promise integrates with try/catch (2e.6).
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves async/await + Promise.

type i32 = number;
type f64 = number;

import { dynNumberValue, dynObject, dynRun, dynTypeof } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000]; // force a WebAssembly trap → nonzero exit
    console.log(x);
  }
}

function checkRun(src: string, expected: f64): void {
  const e: i32 = dynObject();
  const r: i32 = dynRun(src, e);
  check(dynTypeof(r) === 3 ? 1 : 0); // result must be a number
  check(dynNumberValue(r) === expected ? 1 : 0);
}

// ── async function returns a promise; await unwraps ──────────────────────────────────────────────
checkRun("async function f() { return 42; } return await f();", 42);
checkRun("return await 5;", 5); // await of a non-promise = the value
checkRun("return await Promise.resolve(99);", 99);
checkRun("async function f() { const x = await Promise.resolve(10); return x + 5; } return await f();", 15);
checkRun("async function a() { return 3; } async function b() { const x = await a(); return x * 2; } return await b();", 6);
checkRun("async function sum() { const a = await Promise.resolve(1); const b = await Promise.resolve(2); return a + b; } return await sum();", 3);

// ── rejection integrates with try/catch ──────────────────────────────────────────────────────────
checkRun("let r = 0; try { const x = await Promise.reject(7); } catch (e) { r = e; } return r;", 7);
checkRun("async function f() { throw 5; } let r = 0; try { await f(); } catch (e) { r = e; } return r;", 5);

// ── .then / .catch / .finally (callbacks run immediately) ─────────────────────────────────────────
checkRun("let r = 0; Promise.resolve(10).then((v) => { r = v; }); return r;", 10);
checkRun("return await Promise.resolve(5).then((v) => v * 2);", 10);
checkRun("let r = 0; Promise.reject(8).catch((e) => { r = e; }); return r;", 8);
checkRun("let r = 0; Promise.resolve(1).finally(() => { r = 99; }); return r;", 99);

// ── Promise.all ──────────────────────────────────────────────────────────────────────────────────
checkRun("const ps = [Promise.resolve(1), Promise.resolve(2), Promise.resolve(3)]; const arr = await Promise.all(ps); return arr[0] + arr[1] + arr[2];", 6);
checkRun("const arr = await Promise.all([10, 20, 30]); return arr[0] + arr[1] + arr[2];", 60);

console.log("dynrt 2e.10 async/await: all checks passed");
