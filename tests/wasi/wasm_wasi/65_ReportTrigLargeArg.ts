// deno-fmt-ignore-file
// Report issue 5 (5a — Cody-Waite range reduction): Math.sin/cos/tan of a LARGE argument lost ~7 sig
// figs to a single-constant mod-2π subtract. Now a 3-term Cody-Waite split keeps ~13 sig figs.
// Self-checking (values aren't byte-identical to the JS engine, so we assert tight tolerance bands the
// OLD reduction would fail): on a miss, read far OOB → WASM trap → nonzero exit. Runs under both engines.
type i32 = number;
const guard: i32[] = [0];
function check(cond: i32): void { if (cond === 0) { const x: i32 = guard[9000000]; console.log(x); } }

const s: number = Math.sin(500000000); // JS: -0.28470407323754404 (old buggy: -0.2847041112)
check(s > -0.284704074 && s < -0.284704073 ? 1 : 0);
const c: number = Math.cos(500000000); // JS: -0.9586154550610746
check(c > -0.958615456 && c < -0.958615455 ? 1 : 0);
const t: number = Math.tan(500000000); // JS: 0.2969950794496686
check(t > 0.296995079 && t < 0.296995080 ? 1 : 0);
console.log("trig large-arg accuracy ok");
