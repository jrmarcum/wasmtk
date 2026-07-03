// Phase 52.9 — String.fromCodePoint(n): UTF-8 encode code point(s) into a string.
// NOTE: multi-byte code points are compared by printed bytes only — wasic .length is the UTF-8
// byte count while TS .length is UTF-16 code units, so .length is only checked on ASCII results.
type i32 = number;

const a: string = String.fromCodePoint(65);
console.log("a:", a); // A
console.log("a.length:", a.length); // 1 (ASCII)

const bc: string = String.fromCodePoint(0x42, 0x43);
console.log("bc:", bc); // BC

const accent: string = String.fromCodePoint(0xE9); // é (2 UTF-8 bytes)
console.log("accent:", accent);

const euro: string = String.fromCodePoint(0x20AC); // € (3 UTF-8 bytes)
console.log("euro:", euro);

const smile: string = String.fromCodePoint(0x1F600); // 😀 (4 UTF-8 bytes)
console.log("smile:", smile);

const code: i32 = 97;
const r: string = String.fromCodePoint(code); // runtime arg → a
console.log("r:", r);

const word: string = "x" + String.fromCodePoint(89) + "z";
console.log("word:", word); // xYz
