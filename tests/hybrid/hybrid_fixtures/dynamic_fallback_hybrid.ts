// #14.3.4 fallback — a dynamic-bodied function that wasic+dynrt CANNOT compile (calls an undefined
// function) must fall back to the TS host instead of failing the whole build; the static `plus1`
// still routes to WASM.
export function brokenDynamic(n: f64): f64 {
  const o: any = eval("'x'");
  return notAFunction(o) as f64; // undefined function → core compile fails → fallback to host
}

export function plus1(x: f64): f64 {
  return x + 1;
}

const r: f64 = plus1(41);
console.log("plus1(41) =", r);
