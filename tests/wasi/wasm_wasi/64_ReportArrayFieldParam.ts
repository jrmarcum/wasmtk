// deno-fmt-ignore-file
// Report issue 4 (HIGH): an array-typed interface field accessed via a function PARAMETER —
// `p.origin.length` / `p.origin[i]` — was "Unsupported expression". Root cause also included struct
// literals not allocating array fields at all. Both fixed.
type i32 = number;
interface P { origin: string[]; }
interface Nums { vals: i32[]; }
function build(p: P): string { let s: string = ""; for (let i: i32 = 0; i < p.origin.length; i++) { s = s + p.origin[i]; } return s; }
function total(n: Nums): i32 { let t: i32 = 0; for (let i: i32 = 0; i < n.vals.length; i++) { t = t + n.vals[i]; } return t; }
console.log(build({ origin: ["a", "b", "c"] }));
console.log(total({ vals: [3, 4, 5] }));
