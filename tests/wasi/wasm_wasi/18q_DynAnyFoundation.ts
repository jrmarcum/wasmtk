// wasmtk own dynamic runtime — #14.3.1: the wasic `any` type + auto-merge foundation
// (design + log in cmem/dynrt-design.md "Increment 3").
//
// First slice of increment 3 (wiring the dynamic runtime into the wasic COMPILER, not just the
// library). It establishes:
//   • `any` as a tracked type — `mapType("any")` now returns i32 (a boxed dynrt value handle),
//     instead of falling through to f64. Which i32 locals are `any` will be tracked in a side-set
//     for the box/unbox/operator paths; existing code keeps seeing a plain i32.
//   • AUTO-MERGE — a program that uses `any` (or `eval`) gets `wasmtk:dynrt` merged automatically:
//     the bundler injects a synthetic `import { …ops… } from "wasmtk:dynrt"` on `any`/`eval` usage,
//     reusing the existing virtual-capability merge + tree-shake. Programs without `any` are
//     byte-for-byte unaffected. (Note this driver has NO explicit dynrt import — the merge is
//     triggered purely by its use of `: any`.)
//   • BOX/UNBOX round-trip — box a number/string/bool into an `any` handle and unbox it via the
//     dynrt ops; pass an `any` through a function (param/return type `any` = i32 handle).
//   • A new dynrt export `dynStrBytes` (raw byte ptr) used to unbox an `any` string → wasic string.
//
// 3.1-sugar (also covered here): IMPLICIT boxing of literal initialisers — `const x: any = 42` /
// `"hi"` / `true` are rewritten to dynNumber/dynString/dynBool by a source pre-pass — and
// `as`-UNBOXING — `x as i32` / `as f64` / `as bool` emit dynNumberValue(+trunc)/dynToBool when `x` is
// an `any` var (tracked in an `anyVars` side-set). The driver self-checks via traps, so a successful
// `run` proves it.
//
// Pipeline (no modc step — the runtime is auto-merged during `wasic`; no run-ts step — the dynrt
// ops don't exist in native TS):
//
// @test-pipeline
// @step wasic ../wasm_wasi_bundle/dynrt_any_bundle/main_wasic.ts
// @step run ../wasm_wasi_bundle/dynrt_any_bundle/main_wasic.wasm
