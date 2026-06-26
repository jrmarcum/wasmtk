// Unit tests for the #14 Route A 2e.7b var→let consumption gate (src/varscope.ts).
// Run standalone:  deno run --allow-read tests/varscope_tests.ts
// (Not part of the wasm_wasi suite; that suite has 18zk/18zl/18zm integration tests. This file is the
// thorough classification coverage: each safe pattern rewrites to `let`, each unsafe pattern hard-errors.)

import { gateVarToLet, maskCode, VarGateError } from "../src/varscope.ts";

let pass = 0;
let fail = 0;

function safe(src: string, expectContains: string): void {
  try {
    const out = gateVarToLet(src);
    if (out.includes(expectContains)) pass++;
    else {
      fail++;
      console.log(`FAIL(safe-rewrite): ${JSON.stringify(src)}\n   got: ${JSON.stringify(out)}`);
    }
  } catch (e) {
    fail++;
    console.log(
      `FAIL(should be safe): ${JSON.stringify(src)}\n   threw: ${
        (e as Error).message.split("\n")[0]
      }`,
    );
  }
}

function unsafe(src: string, expectReason: string): void {
  try {
    gateVarToLet(src);
    fail++;
    console.log(`FAIL(should be unsafe): ${JSON.stringify(src)}`);
  } catch (e) {
    if (e instanceof VarGateError && e.message.includes(expectReason)) pass++;
    else {
      fail++;
      console.log(
        `FAIL(wrong error): ${JSON.stringify(src)}\n   ${(e as Error).message.split("\n")[0]}`,
      );
    }
  }
}

// ── SAFE → auto-repaired to `let` ──────────────────────────────────────────────────────────────
safe("function f() { var x = 1; return x; }", "let x = 1"); // function top level
safe("function f() { for (var i = 0; i < 3; i++) { s += i; } }", "for (let i"); // loop, no closure
safe("function f() { if (c) { var x = 1; return x; } }", "let x = 1"); // used within its block
safe("const a = 5;\nvar y = a + 1;", "let y = a + 1"); // module level
safe('function f() { var msg = "var x = 1"; return msg; }', "let msg"); // `var` inside a STRING is untouched
safe("function f() { return x + (function () { var x = 1; return x; })(); }", "let x = 1"); // inner IIFE var self-contained
safe("function f() { var a = 1; { var b = a + 1; return b; } }", "let b = a + 1"); // nested block, used within

// ── UNSAFE → hard error (never silently rewritten) ─────────────────────────────────────────────
unsafe("function f() { if (c) { var x = 1; } return x; }", "block closes"); // block-escape (leak)
unsafe("function f() { use(x); var x = 1; return x; }", "before its declaration"); // use-before-declaration
unsafe("function f() { var x = 1; var x = 2; return x; }", "redeclared"); // redeclaration
unsafe(
  "function f() { var fns = []; for (var i = 0; i < 3; i++) { fns[i] = () => i; } }",
  "captured by a closure",
); // loop-closure

// maskCode sanity: a `var` inside a string is masked (so the gate cannot see it)
const masked = maskCode('const s = "var x = 1"; var y = 2;');
if (!/var x/.test(masked) && /var y/.test(masked)) pass++;
else {
  fail++;
  console.log(`FAIL(maskCode): ${masked}`);
}

console.log(`\nvarscope: ${pass} passed, ${fail} failed`);
if (fail > 0) Deno.exit(1);
