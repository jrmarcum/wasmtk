// Phase 46 — Combined escape sequence test.
// All escape categories: \n \t \\ \r \b \f \v \0 and \xHH hex.

type bool = boolean;

function assert(condition: bool, msg: string): void {
    if (!condition) throw new Error(msg);
}

// --- Single-char control escapes ---

const s_nl: string = "foo\nbar";
assert(s_nl.length === 7, "\\n in string");

const s_tab: string = "key\tval";
assert(s_tab.length === 7, "\\t in string");

const s_bs: string = "C:\\path";
assert(s_bs.length === 7, "\\\\ in string");

const s_cr: string = "a\rb";
assert(s_cr.length === 3, "\\r in string");

const s_bk: string = "a\bb";
assert(s_bk.length === 3, "\\b in string");

const s_ff: string = "a\fb";
assert(s_ff.length === 3, "\\f in string");

const s_vt: string = "a\vb";
assert(s_vt.length === 3, "\\v in string");

const s_nu: string = "a\0b";
assert(s_nu.length === 3, "\\0 in string");

// --- Template literal escapes ---

const t1: string = `row1\nrow2`;
assert(t1.length === 9, "\\n in template");

const t2: string = `col1\tcol2`;
assert(t2.length === 9, "\\t in template");

const t3: string = `back\\slash`;
assert(t3.length === 10, "\\\\ in template");

// --- Hex escape sequences ---

// \x0A = newline, \x09 = tab, both verify to the same as named escapes
const h_nl: string = "a\x0Ab";
assert(h_nl.length === 3, "\\x0A (newline) should be 1 byte");

const h_tab: string = "a\x09b";
assert(h_tab.length === 3, "\\x09 (tab) should be 1 byte");

// \x41 = 'A', \x5A = 'Z'
const h_az: string = "\x41\x5A";
assert(h_az.length === 2, "\\x41\\x5A should be 2 bytes");
assert(h_az === "AZ", "\\x41\\x5A should equal 'AZ'");

// --- Cross-check: hex and named escape produce the same string ---
const by_name: string = "a\nb";
const by_hex: string = "a\x0Ab";
assert(by_name.length === by_hex.length, "\\n and \\x0A have same length");
assert(by_name === by_hex, "\\n and \\x0A produce same string");

console.log("Phase46Combined ok");
