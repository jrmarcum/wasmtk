// #14 follow-up — a modc library with `any`-signature functions, marshalled host↔core by bindgen.
type i32 = number;
type f64 = number;

export function identity(x: any): any {
  return x;
}

export function addOne(x: any): any {
  const n: f64 = x as f64;
  return dynNumber(n + 1);
}

export function typeName(x: any): any {
  const t: i32 = dynTypeof(x);
  if (t === 3) return dynString("number");
  if (t === 4) return dynString("string");
  if (t === 2) return dynString("boolean");
  return dynString("other");
}

export function exclaim(s: any): any {
  return dynAdd(s, dynString("!"));
}
