// #14 fallback refinement — one GOOD dynamic body (eval+any, compiles) and one BAD (undefined call).
// Only `badDynamic` should fall back to the host; `goodDynamic` + `plus1` stay in the WASM core.
export function goodDynamic(n: f64): f64 {
  const x: any = eval("6 * 7");
  return (x as f64) + n;
}

export function badDynamic(n: f64): f64 {
  const o: any = eval("'x'");
  return notAFunction(o) as f64; // undefined → fails to compile → fall back to host
}

export function plus1(x: f64): f64 {
  return x + 1;
}

const a: f64 = goodDynamic(8); // 50
const b: f64 = plus1(41); // 42
console.log("goodDynamic(8) =", a);
console.log("plus1(41) =", b);
