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

// #14 structural marshalling — objects/arrays as `any`
export function makePoint(a: f64, b: f64): any {
  const o: any = dynObject();
  dynSet(o, "x", dynNumber(a));
  dynSet(o, "y", dynNumber(b));
  return o;
}

export function triple(a: f64, b: f64, c: f64): any {
  const arr: any = dynArray();
  dynPush(arr, dynNumber(a));
  dynPush(arr, dynNumber(b));
  dynPush(arr, dynNumber(c));
  return arr;
}

export function sumArr(arr: any): any {
  const len: i32 = dynArrLen(arr);
  let s: f64 = 0;
  let i: i32 = 0;
  while (i < len) {
    const e: i32 = dynArrGet(arr, i);
    s = s + dynNumberValue(e);
    i = i + 1;
  }
  return dynNumber(s);
}

export function getX(o: any): any {
  return o.x;
}

// #14 final item — functions-as-`any`: return a dynrt function value (built from strings via the
// `Function(params, body)` producer) as `any`. bindgen wraps it as a callable JS proxy on the host.
export function getDoubler(): any {
  return Function("x", "return x * 2;");
}
