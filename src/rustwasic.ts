/**
 * @module rustwasic
 * @description Rust → WASM producer for wasmtk (polyglot-producer track, 2026-06-07).
 *
 * Unlike the Go/Zig producers (which shell to a compiler), the Rust producer **delegates fully to
 * `rsxtk`** — the owner's Rust WASM toolkit (crates.io/crates/rsxtk), which already does cargo +
 * dependency management + `wasm32-wasip1` builds + a wasmtime WASI runner with `.cwasm` caching.
 * wasmtk simply wraps rsxtk's command set under `--lang=rust` (the way the Go producer wraps TinyGo):
 *
 *   wasmtk init    --lang=rust  → rsxtk init      (wasi script/program template)
 *   wasmtk initmod --lang=rust  → rsxtk initmod   (library module template)
 *   wasmtk modc    --lang=rust  → rsxtk build     (build the library → wasm)
 *   wasmtk build   --lang=rust  → rsxtk build     (build a wasi program → wasm)
 *   wasmtk run     --lang=rust  → rsxtk run       (build + run a wasi program, rsxtk's wasmtime)
 *   wasmtk add/remove/list      → rsxtk add/remove/list   (dependencies)
 *   wasmtk fmt     --lang=rust  → rsxtk fmt       (format + inject a manifest where missing)
 *   wasmtk clean   --lang=rust  → rsxtk clean     (wipe the .tk build cache)
 *
 * `modc` and `build` both map to `rsxtk build` (rsxtk's build is universal — the lib-vs-program
 * distinction comes from the project shape `initmod` vs `init` created). WIT/bindgen/wasmmerge remain
 * wasmtk's job; rsxtk is the producer + native runner.
 */

import { rt } from "./rt.ts";

type RustResult = { success: boolean };

/** True if `rsxtk --version` runs and exits 0. */
export async function rsxtkAvailable(): Promise<boolean> {
  try {
    const r = await new rt.Command("rsxtk", {
      args: ["--version"],
      stdout: "piped",
      stderr: "piped",
    })
      .output();
    return r.success;
  } catch {
    return false;
  }
}

/**
 * Delegates a wasmtk Rust command to the corresponding `rsxtk` subcommand. `forwardArgs` are the
 * already-stripped CLI args (the wasmtk command name and `--lang` removed) passed straight through,
 * so rsxtk's own positional args AND flags work. Output is inherited (rsxtk streams its own progress).
 */
export async function runRust(subcommand: string, forwardArgs: string[]): Promise<RustResult> {
  if (!(await rsxtkAvailable())) {
    console.error(
      "❌ wasmtk (rust): `rsxtk` not found on PATH — it is the Rust producer/runner.\n" +
        "   Install it:  cargo install rsxtk   (see https://crates.io/crates/rsxtk)",
    );
    return { success: false };
  }
  // spawn (not .output()) with inherited stdio so rsxtk's build/run output streams live to the user.
  const child = new rt.Command("rsxtk", { args: [subcommand, ...forwardArgs] }).spawn();
  const status = await child.status;
  return { success: status.success };
}
