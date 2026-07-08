// Fixture for the bindgen kebab↔camel round-trip regression.
// These export names do NOT survive kebabToCamel(toKebabCase(name)):
//   readID  -> read-id  -> readId   (!= readID)
//   toHTML  -> to-html  -> toHtml   (!= toHTML)
// so the generated loader must resolve them via the _ex(...) kebab fallback.
export function readID(x: i32): i32 {
  return x + 1;
}

export function toHTML(x: i32): i32 {
  return x * 2;
}
