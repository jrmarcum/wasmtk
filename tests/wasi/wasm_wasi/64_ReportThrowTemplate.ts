// deno-fmt-ignore-file
// Report issue 1 (HIGH, was SILENT): `throw new Error(`template`)` escaped an enclosing try/catch —
// the throw emitted `proc_exit(0)` (clean exit) instead of `(throw $__exn_tag …)`, so the catch never
// ran and the program exited 0. Now a template/variable message is built + thrown properly.
type i32 = number;
function mayPanic(): void {
  throw new Error(`a problem ${1}`);
}
function safe(): void {
  try {
    mayPanic();
  } catch (r) {
    const msg: string = r instanceof Error ? r.message : `${r}`;
    console.log("Recovered:", msg);
  }
}
safe();
