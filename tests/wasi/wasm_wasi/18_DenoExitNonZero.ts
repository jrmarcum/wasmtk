// @expect-exit: 3  (Deno.exit(N) → WASI proc_exit(N) must exit N, silently — parity with wasmtime)
// Regression for 2026-09-28: `wasmtk run` recognised only proc_exit(0); any other code exited 1
// with a spurious "❌ Run error: RuntimeError: exit:N". Output before the exit is still compared.
type i32 = number;

function check(n: i32): i32 {
  console.log("checking", n);
  return n * 2;
}

const v = check(21);
console.log("value", v);
Deno.exit(3);
console.log("never printed");
