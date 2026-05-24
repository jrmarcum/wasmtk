// Phase 35 — keyof T: inline type annotation as string parameter/variable
type i32 = number;
type f64 = number;

interface Point {
  x: f64;
  y: f64;
}

interface Config {
  width: i32;
  height: i32;
  scale: f64;
}

function printKey(key: keyof Point): void {
  console.log("key:", key);
}

function lookupConfig(key: keyof Config): void {
  console.log("config key:", key);
}

function matchWidth(key: keyof Config): bool {
  return key === "width";
}

function main(): void {
  printKey("x");       // key: x
  printKey("y");       // key: y

  lookupConfig("width");   // config key: width
  lookupConfig("height");  // config key: height
  lookupConfig("scale");   // config key: scale

  // keyof T as variable type annotation
  const k: keyof Point = "x";
  console.log("stored:", k);  // stored: x

  // keyof T variable used in comparison
  const field: keyof Config = "width";
  if (field === "width") {
    console.log("is width");  // is width
  }
  if (field !== "height") {
    console.log("not height"); // not height
  }

  // keyof T variable passed to function expecting keyof T
  const isWide: bool = matchWidth("width");
  if (isWide) {
    console.log("matched width"); // matched width
  }
}

main();
