// bindgen fixture — #14 Phase 2: host→core callbacks. The core receives JS functions as `any` and
// calls them (the reverse direction of functions-as-`any`). bindgen boxes a passed JS function into a
// host table; the core calls back via the `env.__host_call` import.
type i32 = number;
type f64 = number;

export function applyTwice(fn: any, x: any): any {
  return fn(fn(x));
}

export function combine(fn: any, a: any, b: any): any {
  return fn(a, b);
}
