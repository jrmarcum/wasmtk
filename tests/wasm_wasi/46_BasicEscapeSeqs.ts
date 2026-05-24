// Phase 46 — Basic escape sequences in string literals.
// Covers all single-char escapes: \n \r \t \b \f \v \0 \\

type bool = boolean;

function assert(condition: bool, msg: string): void {
    if (!condition) throw new Error(msg);
}

// \n — newline (0x0A): 1 byte, not 2 raw chars
const nl: string = "a\nb";
assert(nl.length === 3, "\\n should be 1 byte");

// \r — carriage return (0x0D): 1 byte
const cr: string = "a\rb";
assert(cr.length === 3, "\\r should be 1 byte");

// \t — tab (0x09): 1 byte
const tab: string = "a\tb";
assert(tab.length === 3, "\\t should be 1 byte");

// \b — backspace (0x08): 1 byte
const bs: string = "a\bb";
assert(bs.length === 3, "\\b should be 1 byte");

// \f — form feed (0x0C): 1 byte
const ff: string = "a\fb";
assert(ff.length === 3, "\\f should be 1 byte");

// \v — vertical tab (0x0B): 1 byte
const vt: string = "a\vb";
assert(vt.length === 3, "\\v should be 1 byte");

// \0 — null character (0x00): 1 byte
const nul: string = "a\0b";
assert(nul.length === 3, "\\0 should be 1 byte");

// \\ — single backslash: 1 byte, not 2 raw chars
const bksl: string = "a\\b";
assert(bksl.length === 3, "\\\\ should be 1 byte");

// Longer string with \n in the middle
const greeting: string = "hello\nworld";
assert(greeting.length === 11, "\\n in longer string");

// Multiple escapes in one string: \t and \n
const multi: string = "a\tb\nc";
assert(multi.length === 5, "mixed \\t and \\n");

console.log("BasicEscapeSeqs ok");
