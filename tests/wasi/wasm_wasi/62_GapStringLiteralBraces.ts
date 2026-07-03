// deno-fmt-ignore-file
// Compiler-gap regression (2026-06-30): Gap 4 — a module-level string literal CONTAINING `{`/`}`/`;`
// must not be mis-parsed (parseFunctions was string-blind and treated `function f(){…}` inside the
// string as a real declaration → mangled source / "Unsupported statement" fragments).
type i32 = number;
const code: string = "function f() {\n  return 1;\n}\nf();";
console.log(code.length);
console.log(code);
