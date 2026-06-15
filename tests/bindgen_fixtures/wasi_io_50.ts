// modc library that performs I/O (console.log → wasi_snapshot_preview1.fd_write).
// Used by the universalWasmLoader reference suite to exercise the SPEC §10 WASI-P1 shim:
// without a host WASI shim this module fails to instantiate (missing fd_write import).
type i32 = number;

export function logAndDouble(n: i32): i32 {
  console.log("doubling");
  return n * 2;
}
