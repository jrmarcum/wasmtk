function contains(s: string, sub: string): boolean {
    return s.indexOf(sub) >= 0;
}

function count(s: string, sub: string): number {
    if (sub.length === 0) return s.length + 1;
    let n: number = 0;
    let pos: number = 0;
    while (true) {
        const idx: number = s.indexOf(sub, pos);
        if (idx < 0) break;
        n++;
        pos = idx + sub.length;
    }
    return n;
}

function hasPrefix(s: string, prefix: string): boolean {
    return s.length >= prefix.length && s.slice(0, prefix.length) === prefix;
}

function hasSuffix(s: string, suffix: string): boolean {
    return s.length >= suffix.length && s.slice(s.length - suffix.length) === suffix;
}

function strIndex(s: string, sub: string): number {
    return s.indexOf(sub);
}

function join(arr: string[], sep: string): string {
    let r: string = "";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) r += sep;
        r += arr[i];
    }
    return r;
}

function repeat(s: string, n: number): string {
    let r: string = "";
    for (let i: number = 0; i < n; i++) r += s;
    return r;
}

function replaceAll(s: string, old: string, nw: string): string {
    let r: string = "";
    let pos: number = 0;
    while (true) {
        const idx: number = s.indexOf(old, pos);
        if (idx < 0) { r += s.slice(pos); break; }
        r += s.slice(pos, idx) + nw;
        pos = idx + old.length;
    }
    return r;
}

function replace(s: string, old: string, nw: string): string {
    const idx: number = s.indexOf(old);
    if (idx < 0) return s;
    return s.slice(0, idx) + nw + s.slice(idx + old.length);
}

function split(s: string, sep: string): string[] {
    const parts: string[] = [];
    let pos: number = 0;
    while (true) {
        const idx: number = s.indexOf(sep, pos);
        if (idx < 0) { parts.push(s.slice(pos)); break; }
        parts.push(s.slice(pos, idx));
        pos = idx + sep.length;
    }
    return parts;
}

function strArrStr(arr: string[]): string {
    let s: string = "[";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) s += " ";
        s += arr[i];
    }
    return s + "]";
}

console.log("Contains:  ", contains("test", "es"));
console.log("Count:     ", count("test", "t"));
console.log("HasPrefix: ", hasPrefix("test", "te"));
console.log("HasSuffix: ", hasSuffix("test", "st"));
console.log("Index:     ", strIndex("test", "e"));
console.log("Join:      ", join(["a", "b"], "-"));
console.log("Repeat:    ", repeat("a", 5));
console.log("Replace:   ", replaceAll("foo", "o", "0"));
console.log("Replace:   ", replace("foo", "o", "0"));
console.log("Split:     ", strArrStr(split("a-b-c-d-e", "-")));
console.log("ToLower:   ", "TEST".toLowerCase());
console.log("ToUpper:   ", "test".toUpperCase());
