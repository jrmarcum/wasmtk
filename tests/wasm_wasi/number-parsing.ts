function parseFloat_(s: string): number {
    let result: number = 0;
    let decimal: boolean = false;
    let factor: number = 0.1;
    let neg: boolean = false;
    let i: number = 0;
    if (s[0] === "-") { neg = true; i = 1; }
    for (; i < s.length; i++) {
        const c: string = s[i];
        if (c === ".") { decimal = true; continue; }
        const d: number = c.charCodeAt(0) - 48;
        if (decimal) { result += d * factor; factor *= 0.1; }
        else { result = result * 10 + d; }
    }
    return neg ? -result : result;
}

function parseInt_(s: string, base: number): number {
    let result: number = 0;
    const chars: string = "0123456789abcdef";
    for (let i: number = 0; i < s.length; i++) {
        const c: string = s[i].toLowerCase();
        const d: number = chars.indexOf(c);
        if (d < 0 || d >= base) return NaN;
        result = result * base + d;
    }
    return result;
}

const f: number = parseFloat_("1.234");
console.log(f);

const i: number = parseInt_("123", 10);
console.log(i);

const d: number = parseInt_("1c8", 16);
console.log(d);

const u: number = parseInt_("789", 10);
console.log(u);

const k: number = parseInt_("135", 10);
console.log(k, "<nil>");

const bad: number = parseInt_("wat", 10);
if (isNaN(bad)) {
    console.log('strconv.Atoi: parsing "wat": invalid syntax');
}
