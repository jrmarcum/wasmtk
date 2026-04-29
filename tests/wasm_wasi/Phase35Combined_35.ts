// Phase 35 — Combined: typeof and keyof T together
type i32 = number;
type f64 = number;

interface Rect {
  width: f64;
  height: f64;
}

interface Settings {
  volume: i32;
  brightness: i32;
}

// keyof T as function parameter type (treated as string)
function printField(key: keyof Rect): void {
  console.log("field:", key);
}

function applySettings(key: keyof Settings, val: i32): void {
  console.log("setting:", key);
  console.log("value:", val);
}

// typeof in function — assign and print type strings
function describeVar(n: i32, d: f64, s: string, b: bool): void {
  const tn: string = typeof n;
  const td: string = typeof d;
  const ts: string = typeof s;
  const tb: string = typeof b;
  console.log("n:", tn);   // n: number
  console.log("d:", td);   // d: number
  console.log("s:", ts);   // s: string
  console.log("b:", tb);   // b: boolean
}

function main(): void {
  // keyof T variable and function use
  const rectKey: keyof Rect = "width";
  console.log("key:", rectKey);     // key: width

  printField("height");             // field: height
  printField("width");              // field: width

  applySettings("volume", 80);      // setting: volume / value: 80
  applySettings("brightness", 50);  // setting: brightness / value: 50

  // typeof comparisons in main
  const count: i32 = 5;
  const ratio: f64 = 0.75;
  const tag: string = "test";
  const enabled: bool = true;

  if (typeof count !== "string") {
    console.log("count not string");   // count not string
  }
  if (typeof ratio !== "boolean") {
    console.log("ratio not boolean");  // ratio not boolean
  }
  if (typeof tag === "string") {
    console.log("tag is string");      // tag is string
  }
  if (typeof enabled === "boolean") {
    console.log("enabled is boolean"); // enabled is boolean
  }

  // typeof stored and compared
  const tcount: string = typeof count;
  const ttag: string = typeof tag;
  if (tcount === "number") {
    console.log("tcount is number"); // tcount is number
  }
  if (ttag === "string") {
    console.log("ttag is string");   // ttag is string
  }

  // typeof inside nested function call
  describeVar(1, 2.0, "hi", false);

  // keyof T comparison
  const sk: keyof Settings = "volume";
  if (sk === "volume") {
    console.log("sk is volume");     // sk is volume
  }
}

main();
