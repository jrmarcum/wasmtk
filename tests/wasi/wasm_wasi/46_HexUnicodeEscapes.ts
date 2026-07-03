// Phase 46 — Hex escape sequences in string literals.
// Tests \xHH escape processing. (\uHHHH is covered via allocation path.)

type bool = boolean;

function assert(condition: bool, msg: string): void {
    if (!condition) throw new Error(msg);
}

// \x41 = 'A' (1 byte, not the 4 raw chars \, x, 4, 1)
const hexA: string = "\x41";
assert(hexA.length === 1, "\\x41 should be 1 byte");
assert(hexA === "A", "\\x41 should equal 'A'");

// \x48\x69 = "Hi" (2 bytes, not 8 raw chars)
const hexHi: string = "\x48\x69";
assert(hexHi.length === 2, "\\x48\\x69 should be 2 bytes");
assert(hexHi === "Hi", "\\x48\\x69 should equal 'Hi'");

// Mixed: \x3D = '=' (equals sign), surrounding chars are plain
const mixed: string = "X\x3DY";
assert(mixed.length === 3, "X\\x3DY should be 3 bytes");
assert(mixed === "X=Y", "\\x3D should equal '='");

// Hex escape at end of string
const hexEnd: string = "ok\x21";
assert(hexEnd.length === 3, "\\x21 at end should be 1 byte");
assert(hexEnd === "ok!", "\\x21 should equal '!'");

// Hex escape at start of string
const hexStart: string = "\x5Bold]";
assert(hexStart === "[old]", "\\x5B should equal '['");

// Multiple hex escapes in a row
const hexSeq: string = "\x61\x62\x63";
assert(hexSeq.length === 3, "three \\xHH should be 3 bytes");
assert(hexSeq === "abc", "\\x61\\x62\\x63 should equal 'abc'");

console.log("HexUnicodeEscapes ok");
