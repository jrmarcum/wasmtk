// Self-checking driver for the relocateDataPtrs arithmetic-constant fix. modByInRange does `x % 271`,
// and 271 lands INSIDE the library's static-data range [260, ~301) (the banner string). The old
// merge heuristic relocated EVERY in-range i32.const, corrupting the modulo divisor (271 -> 531) and
// returning wrong values -> the guard trap below fires -> nonzero exit -> pipeline FAILS. The fix
// excludes pure-arithmetic operands, so 271 is preserved while the banner string POINTER (also 260,
// but in store-value position) still relocates correctly. Trap-on-failure (no run-ts; can't import a
// .wasm from .ts directly).
type i32 = number;
import { modByInRange, banner } from "./reloc_lib_modc.wasm";

const guard: i32[] = [0];
function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000]; // OOB read -> trap -> nonzero exit
    console.log(x);
  }
}

banner(); // exercises a genuine data POINTER relocation (the string moved 260 -> dataOffset)
check(modByInRange(1000) === 194 ? 1 : 0); // 1000 % 271 + 7
check(modByInRange(542) === 7 ? 1 : 0); // 542 % 271 + 7  (542 = 2*271)
check(modByInRange(271) === 7 ? 1 : 0); // 271 % 271 + 7
console.log("reloc-arith-const OK");
