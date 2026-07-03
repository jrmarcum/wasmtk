type i32 = number;

const extra: i32 = 7;

/** @export */
export function modByInRange(x: i32): i32 {
  // 271 lands INSIDE this library's static-data range [260, ~301) created by the banner string.
  // The old relocateDataPtrs shifted every in-range i32.const, corrupting this modulo divisor;
  // the fix excludes i32.rem_u/mul/etc. operands (a data pointer is never a modulo divisor).
  return (x % 271) + extra;
}

/** @export */
export function banner(): void {
  console.log("Reloc capability library banner string v1");
}
