/**
 * Unit tests for the `wasmtk hybrid` parser/runner — focused on the context-aware
 * scanners: findCloseBrace (string/comment-aware body extraction) and
 * rewriteWasmCalls (call-site rewriting that skips strings, comments, member
 * accesses, and object method-shorthand definitions), plus multi-line import
 * injection in generateRunner.
 */

import { assert, assertEquals } from "jsr:@std/assert";
import { generateRunner, parseHybridFile } from "../src/hybrid.ts";

// ── findCloseBrace: a `}` inside a string must not truncate the function ────────

Deno.test("hybrid — a @wasm function body with a `}` in a string is fully extracted", () => {
  const src = [
    "// @wasm",
    "function f(x: i32): string {",
    '  const open: string = "{";',
    '  const close: string = "}";', // the naive scanner truncated here
    "  return open + close;",
    "}",
    "const y = f(1);",
  ].join("\n");
  const r = parseHybridFile(src);
  assertEquals(r.wasmFuncs.length, 1);
  const text = r.wasmFuncs[0].text;
  assert(text.includes("return open + close;"), "body truncated before the return");
  assert(text.trimEnd().endsWith("}"), "function did not extend to its real close brace");
  // The function was removed from remaining source (only the call site remains).
  assert(!r.remainingSrc.includes("function f"), "function not removed from remaining source");
});

Deno.test("hybrid — a nested-backtick interpolation whose text has a `}` does not truncate the body (B5)", () => {
  // The interpolation `${ `raw } text` }` contains a nested backtick template whose TEXT
  // holds a `}`. The naive scanner mistook the nested opening backtick for the outer
  // template's closing backtick, then counted that `}` as a real close brace and truncated
  // the function early (proven: body 68 chars vs 82). skipLiteral now descends into `${…}`.
  const src = [
    "// @wasm",
    "function tpl(x: i32): string {",
    "  const s: string = `${ `raw } text` }`;",
    "  return s;",
    "}",
    "const y = tpl(1);",
  ].join("\n");
  const r = parseHybridFile(src);
  assertEquals(r.wasmFuncs.length, 1);
  const text = r.wasmFuncs[0].text;
  assert(text.includes("return s;"), "body truncated before the return (nested-backtick `}` leaked)");
  assert(text.trimEnd().endsWith("}"), "function did not extend to its real close brace");
  assert(!r.remainingSrc.includes("function tpl"), "function not removed from remaining source");
  assert(r.remainingSrc.includes("const y = tpl(1);"), "trailing host statement lost");
});

Deno.test("hybrid — call rewriting descends through a doubly-nested-backtick interpolation (B5)", () => {
  // A @wasm call sits in an interpolation alongside a doubly-nested template whose inner
  // text has a `}` (`${ `a ${ `x}y` } b` + add(1, 2) }`). findInterpEnd → skipLiteral must
  // skip the nested templates to find the real interpolation end; without the fix the call
  // was NOT rewritten (proven: rewrote=false vs true).
  const src = [
    "// @wasm",
    "function add(a: i32, b: i32): i32 { return a + b; }",
    "const msg: string = `${ `a ${ `x}y` } b` + add(1, 2) }`;",
    "console.log(msg);",
  ].join("\n");
  const r = parseHybridFile(src);
  const runner = generateRunner(
    r.remainingSrc,
    new Set(r.wasmFuncs.map((f) => f.name)),
    "./m.bindings.ts",
    "./m.wasm",
  );
  assert(runner.includes("lib.add(1, 2)"), "nested-interpolation call was not rewritten to lib.add");
});

Deno.test("hybrid — a @wasm function with a brace inside a line comment is fully extracted", () => {
  const src = [
    "// @wasm",
    "function g(n: i32): i32 {",
    "  // closing brace } in a comment",
    "  return n * 2;",
    "}",
  ].join("\n");
  const r = parseHybridFile(src);
  assertEquals(r.wasmFuncs.length, 1);
  assert(r.wasmFuncs[0].text.includes("return n * 2;"));
});

// ── rewriteWasmCalls: only real call sites get `lib.` ───────────────────────────

Deno.test("hybrid — call rewriting skips strings, comments, member access, and method shorthand", () => {
  const remaining = [
    'import { x } from "./x.ts";',
    "const a = add(1, 2);", // real call -> rewritten
    'console.log("please add() two");', // inside a string -> NOT rewritten
    "// call add() from here", // inside a comment -> NOT rewritten
    "const o = { add(p: i32) { return p; } };", // method shorthand def -> NOT rewritten
    "obj.add(3);", // member access -> NOT rewritten
    "const b = readd(9);", // word-prefix collision -> NOT rewritten
  ].join("\n");
  const runner = generateRunner(remaining, ["add"], "./b.bindings.ts", "./m.wasm");

  assert(runner.includes("const a = lib.add(1, 2);"), "real call was not rewritten");
  assert(runner.includes('console.log("please add() two");'), "string content was altered");
  assert(!runner.includes("lib.add() two"), "rewrote inside a string literal");
  assert(runner.includes("// call add() from here"), "comment content was altered");
  assert(runner.includes("{ add(p: i32) { return p; } }"), "object method shorthand was rewritten");
  assert(runner.includes("obj.add(3);"), "member access was rewritten");
  assert(runner.includes("const b = readd(9);"), "word-prefix collision was rewritten");
});

// ── generateRunner: multi-line import injection ─────────────────────────────────

// ── regex-literal awareness ─────────────────────────────────────────────────────

Deno.test("hybrid — a regex literal in host code does not disable downstream call rewrites", () => {
  const remaining = [
    'import { x } from "./x.ts";',
    'const cleaned = s.replace(/["\'{}]/g, "");', // regex with quotes+braces
    "const a = add(1, 2);", // must STILL be rewritten
  ].join("\n");
  const runner = generateRunner(remaining, ["add"], "./b.bindings.ts", "./m.wasm");
  assert(runner.includes("const a = lib.add(1, 2);"), "rewrite disabled by a preceding regex literal");
  assert(runner.includes(`s.replace(/["'{}]/g, "")`), "regex literal was altered");
});

Deno.test("hybrid — a routed name inside a regex literal is NOT rewritten", () => {
  const remaining = "const re = /add(x)/; const a = add(1);";
  const runner = generateRunner(remaining, ["add"], "./b.bindings.ts", "./m.wasm");
  assert(runner.includes("const re = /add(x)/;"), "regex body was corrupted");
  assert(runner.includes("const a = lib.add(1);"), "real call not rewritten");
});

Deno.test("hybrid — a routed call inside a template ${...} interpolation IS rewritten", () => {
  const remaining = "const msg = `result=${add(2, 3)} done`;";
  const runner = generateRunner(remaining, ["add"], "./b.bindings.ts", "./m.wasm");
  assert(runner.includes("`result=${lib.add(2, 3)} done`"), "interpolated call not rewritten");
});

Deno.test("hybrid — a `}` inside a regex literal in a @wasm body does not truncate extraction", () => {
  const src = [
    "// @wasm",
    "function f(x: i32): i32 {",
    "  const re = /}{/;", // brace chars inside a regex
    "  return x + 1;",
    "}",
  ].join("\n");
  const r = parseHybridFile(src);
  assertEquals(r.wasmFuncs.length, 1);
  assert(r.wasmFuncs[0].text.includes("return x + 1;"), "body truncated at a regex brace");
});

Deno.test("hybrid — loadModule is injected after a multi-line import, not mid-statement", () => {
  const remaining = [
    "import {",
    "  foo,",
    '} from "./x.ts";',
    "const a = add(1);",
  ].join("\n");
  const runner = generateRunner(remaining, ["add"], "./b.bindings.ts", "./m.wasm");

  // The binding import + loadModule must appear AFTER the multi-line import closes.
  const lines = runner.split("\n");
  const closeImportIdx = lines.findIndex((l) => l.includes('} from "./x.ts";'));
  const loadIdx = lines.findIndex((l) => l.includes("await loadModule"));
  assert(closeImportIdx >= 0, "multi-line import not present");
  assert(loadIdx > closeImportIdx, "loadModule injected before the import closed");
  // The `foo,` continuation must not have been split from its `import {`.
  assert(!runner.includes('import {\nimport { loadModule'), "loader spliced inside the import");
  assert(runner.includes("const a = lib.add(1);"), "call not rewritten in runner body");
});
