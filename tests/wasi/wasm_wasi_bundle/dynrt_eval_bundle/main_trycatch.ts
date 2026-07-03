// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2e.6: `throw` / `try` / `catch` /
// `finally` in eval source. A throw propagates (via evalThrew) up through statements, loops, and
// FUNCTION CALLS until a catch clears it; finally always runs.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves the exception handling.

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

// ── basic throw / catch ──────────────────────────────────────────────────────────────────────────
checkRun("let r = 0; try { throw 5; } catch (e) { r = e; } return r;", 5);
checkRun("let r = 0; try { r = 1; } catch (e) { r = 2; } return r;", 1); // no throw
checkRun("let r = 0; try { throw 10; r = 1; } catch (e) { r = e + 1; } return r;", 11); // throw skips r=1
checkRun("let r = 0; try { throw 2 + 3; } catch (e) { r = e * 2; } return r;", 10); // thrown expression
checkRun("let r = 0; try { throw 1; } catch { r = 99; } return r;", 99); // catch without binding
checkRun("let r = 0; try { throw 5; } catch (e) { r = e; } r = r + 1; return r;", 6); // continue after catch

// ── throw propagating through function calls ─────────────────────────────────────────────────────
checkRun("function f() { throw 7; } let r = 0; try { f(); } catch (e) { r = e; } return r;", 7);
checkRun("function g() { throw 3; } function f() { g(); return 99; } let r = 0; try { f(); } catch (e) { r = e; } return r;", 3);

// ── finally ──────────────────────────────────────────────────────────────────────────────────────
checkRun("let r = 0; try { r = 1; } finally { r = r + 10; } return r;", 11); // try/finally, no catch
checkRun("let r = 0; try { throw 5; } catch (e) { r = e; } finally { r = r + 100; } return r;", 105);
checkRun("let r = 0; try { r = 1; } catch (e) { r = 2; } finally { r = r + 10; } return r;", 11); // finally always runs

// ── throw out of a loop ──────────────────────────────────────────────────────────────────────────
checkRun("let r = 0; try { for (let i = 0; i < 10; i++) { if (i === 3) { throw i; } r = r + 1; } } catch (e) { r = r + e; } return r;", 6);
checkRun("let r = 0; let i = 0; try { while (i < 10) { if (i === 4) { throw 100; } i = i + 1; } } catch (e) { r = e; } return r;", 100);

// ── nested try/catch + re-throw ──────────────────────────────────────────────────────────────────
checkRun("let r = 0; try { try { throw 1; } catch (e) { throw e + 10; } } catch (e2) { r = e2; } return r;", 11);

console.log("dynrt 2e.6 try/catch/throw: all checks passed");
