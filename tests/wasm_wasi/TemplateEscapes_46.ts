// Phase 46 — Escape sequences in template literals (backtick strings).
// Tests \n \t \\ in template literal text segments.

type bool = boolean;

function assert(condition: bool, msg: string): void {
    if (!condition) throw new Error(msg);
}

// \n in a plain template literal (no expression)
const nl: string = `line1\nline2`;
assert(nl.length === 11, "\\n in template should be 1 byte");

// \t in template literal
const tab: string = `A\tB`;
assert(tab.length === 3, "\\t in template should be 1 byte");

// \\ in template literal produces a single backslash
const bksl: string = `path\\file`;
assert(bksl.length === 9, "\\\\ in template should be 1 byte");

// \r in template literal
const cr: string = `a\rb`;
assert(cr.length === 3, "\\r in template should be 1 byte");

// \b in template literal
const bs: string = `a\bb`;
assert(bs.length === 3, "\\b in template should be 1 byte");

// Multiple escapes in same template
const multi: string = `a\tb\nc`;
assert(multi.length === 5, "multiple escapes in template");

// Escape in text segment BEFORE an expression
const name: string = "world";
const tmpl: string = `hello\n${name}`;
assert(tmpl.length === 11, "\\n before expression in template");

// Escape in text segment AFTER an expression
const prefix: string = "hi";
const tmpl2: string = `${prefix}\nthere`;
assert(tmpl2.length === 8, "\\n after expression in template");

console.log("TemplateEscapes ok");
