/**
 * typed_decl_tests.ts — the typed-declaration rule (owner ruling 2026-09-28)
 *
 * Every let/const/var states its type on its FIRST definition; a later assignment needs none. A
 * counting-`for` counter written without a type is an integer by standard, and anything that could
 * make it fractional is an error. This suite asserts the REASON each program is refused (the
 * diagnostic text, and the line it names in the file as written), so a program cannot pass here by
 * failing for some other cause. The accepted forms are checked by compiling AND running them.
 *
 *   refused: untyped number / string / `new` / call result; untyped array or object pattern;
 *            an arrow missing its return type or a parameter type; a counter that starts
 *            fractional, is updated with `/=`, or is assigned a fraction in the loop body
 *            (multi-line AND one-line `for`, which are parallel emitters in wasic)
 *   accepted: reassignment without a type; for-of / counting-for bindings; a typed pattern;
 *            a fully typed arrow or function expression; `Promise<…>`, an object type literal,
 *            a tuple from a call, a union alias from a member, a `T | null` destructured
 *   line:    the line number is the one in the file, even after a block comment
 *
 * Everything runs in a temp dir.
 *
 * Usage:
 *   deno run --allow-read --allow-write --allow-run --allow-env tests/typed_decl_tests.ts
 *
 * @license MIT
 */

import { join } from "jsr:@std/path";

const WASMTK = "wasmtk";

let passed = 0;
let failed = 0;
function ok(desc: string, cond: boolean, detail = ""): void {
  if (cond) {
    passed++;
    console.log(`  ✓ ${desc}`);
  } else {
    failed++;
    console.error(`  ✗ ${desc}${detail ? `\n${detail}` : ""}`);
  }
}

async function run(args: string[], cwd: string): Promise<{ code: number; text: string }> {
  const out = await new Deno.Command(WASMTK, { args, cwd, stdout: "piped", stderr: "piped" })
    .output();
  const dec = new TextDecoder();
  return { code: out.code, text: dec.decode(out.stdout) + dec.decode(out.stderr) };
}

const H = "type i32 = number;\ntype f64 = number;\n";

// [name, source, expected diagnostic fragment]. The source is ONE fault, so the fragment is its cause.
const REFUSED: [string, string, string][] = [
  [
    "untyped number",
    `let a = 100000;\nconsole.log(a);`,
    "Declaration needs a type (line 3): 'let a = 100000;'",
  ],
  [
    "untyped string",
    `const s = "hi";\nconsole.log(s);`,
    "Declaration needs a type (line 3): 'const s = \"hi\";'",
  ],
  [
    "untyped new",
    `const m = new Map<string, i32>();\nconsole.log(m.size);`,
    "Declaration needs a type (line 3)",
  ],
  [
    "untyped call result",
    `function f(): i32 { return 1; }\nconst v = f();\nconsole.log(v);`,
    "Declaration needs a type (line 4): 'const v = f();'",
  ],
  [
    "untyped array pattern",
    `const p: [i32, i32] = [1, 2];\nconst [x, y] = p;\nconsole.log(x + y);`,
    "Type the pattern, e.g. 'const [a, b]: [i32, i32] = …'",
  ],
  [
    "untyped object pattern",
    `interface P { x: i32; y: i32; }\nconst p: P = { x: 1, y: 2 };\nconst { x, y } = p;\nconsole.log(x + y);`,
    "Type the pattern, e.g. 'const { x, y }: Point = …'",
  ],
  [
    "arrow without return type",
    `const k: i32 = 3;\nconst f = (x: i32) => x + k;\nconsole.log(f(1));`,
    "Declaration needs a type (line 4)",
  ],
  [
    "arrow with untyped param",
    `const g = (x): i32 => x;\nconsole.log(g(1));`,
    "Declaration needs a type (line 3)",
  ],
  [
    "counter starts fractional",
    `for (let i = 0.5; i < 3; i++) {\n  console.log(i);\n}`,
    "for-loop counter 'i' must stay an integer: it starts as '0.5'",
  ],
  [
    "counter divided",
    `for (let i = 64; i > 1; i /= 2) {\n  console.log(i);\n}`,
    "for-loop counter 'i' must stay an integer: 'i /= …'",
  ],
  [
    "counter given a fraction",
    `for (let i = 0; i < 3; i++) {\n  i += 0.5;\n  console.log(i);\n}`,
    "for-loop counter 'i' must stay an integer: it is assigned '0.5'",
  ],
  [
    "one-line loop, fractional start",
    `for (let i = 0.5; i < 3; i++) console.log(i);`,
    "it starts as '0.5'",
  ],
  ["one-line loop, divided", `for (let i = 64; i > 1; i /= 2) console.log(i);`, "'i /= …'"],
  [
    "line number counts a block comment",
    `/**\n * four\n * lines\n */\nconst ok: i32 = 1;\nlet n = 5; // the fault\nconsole.log(ok + n);`,
    "Declaration needs a type (line 8): 'let n = 5;'",
  ],
];

// [name, source, expected stdout]. Each is compiled and RUN, so acceptance is also correctness.
const ACCEPTED: [string, string, string][] = [
  [
    "reassignment, loops, typed pattern, typed function values",
    `let total: number = 0;
total = total + 2.5;
const nums: number[] = [1, 2, 3];
for (const v of nums) { total = total + v; }
for (let i = 0; i < 3; i++) { total = total + i; }
const pair: [i32, i32] = [4, 5];
const [a, b]: [i32, i32] = pair;
const add = (x: i32, y: i32): i32 => x + y;
const twice = function (n: number): number { return n * 2; };
total = total + add(1, 2) + twice(1.5);
console.log(total, a + b);`,
    "17.5 9",
  ],
  [
    "Promise<T> on a promise-holding variable",
    `async function c(n: i32): Promise<i32> { return n * 2; }
async function main(): Promise<void> {
  const p: Promise<i32> = c(3);
  const v: i32 = await p;
  console.log(v);
}
main();`,
    "6",
  ],
  [
    "union alias from a member",
    `interface AddOp { type: "add"; value: i32; }
interface MulOp { type: "mul"; value: i32; }
type MathOp = AddOp | MulOp;
interface Ok { ok: true; operation: MathOp; }
function f(res: Ok): i32 {
  const op: MathOp = res.operation;
  if (op.type === "add") return op.value + 1;
  return op.value * 2;
}
const r: Ok = { ok: true, operation: { type: "mul", value: 4 } };
console.log(f(r));`,
    "8",
  ],
  [
    "T | null tuple alias, then a typed pattern",
    `type NT = [i32 | null, f64];
function g(flag: boolean): NT | null { if (!flag) return null; return [7, 0.5]; }
const v: NT | null = g(true);
if (v !== null) {
  const [a, b]: NT = v;
  console.log(a, b);
}`,
    "7 0.5",
  ],
];

const dir = await Deno.makeTempDir({ prefix: "wasmtk_typed_decl_" });
try {
  console.log("\n  refused, for the stated reason:");
  for (const [name, body, frag] of REFUSED) {
    const file = `r_${name.replace(/\W+/g, "_")}.ts`;
    await Deno.writeTextFile(join(dir, file), H + body + "\n");
    const r = await run(["wasic", file], dir);
    ok(
      `${name}`,
      r.code !== 0 && r.text.includes(frag),
      `    exit ${r.code}; wanted: ${frag}\n${r.text}`,
    );
  }
  console.log("\n  accepted, and correct when run:");
  for (const [name, body, want] of ACCEPTED) {
    const file = `a_${name.replace(/\W+/g, "_")}.ts`;
    await Deno.writeTextFile(join(dir, file), H + body + "\n");
    const c = await run(["wasic", file], dir);
    if (c.code !== 0) {
      ok(name, false, `    compile failed:\n${c.text}`);
      continue;
    }
    const r = await run(["run", file.replace(/\.ts$/, ".wasm")], dir);
    const got = r.text.replace(/\r\n/g, "\n").trim();
    ok(name, r.code === 0 && got === want, `    exit ${r.code}; wanted "${want}", got "${got}"`);
  }
} finally {
  await Deno.remove(dir, { recursive: true });
}

console.log(`\n  typed-declaration rule: ${passed} passed, ${failed} failed`);
if (failed > 0) Deno.exit(1);
