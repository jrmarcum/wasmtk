// deno-fmt-ignore-file
// Report issue 3 (MEDIUM): a module-scope try/catch with a bound catch var aborted
// (`$e_ptr/$e_len cannot be resolved`) — _start's local decls were built from startLocals only, missing
// the (ptr,len) pair the catch handler pushed to startDeclaredLocals.
type i32 = number;
function fail(): void { throw new Error("bad"); }
try {
  fail();
} catch (e) {
  const msg: string = e instanceof Error ? e.message : `${e}`;
  console.log("error:", msg);
}
