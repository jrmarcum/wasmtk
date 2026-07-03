interface Point {
    x: number;
    y: number;
}

const p: Point = { x: 1, y: 2 };

console.log(`{${p.x} ${p.y}}`);
console.log(`{x:${p.x} y:${p.y}}`);
console.log(`{x:${p.x}, y:${p.y}}`);
console.log("struct");

console.log(true);
console.log(123);
console.log((14).toString(2));
console.log("!");

function toHex(n: number): string {
    const h: string = "0123456789abcdef";
    if (n === 0) return "0";
    let r: string = "";
    let v: number = n;
    while (v > 0) {
        r = h[v % 16] + r;
        v = Math.floor(v / 16);
    }
    return r;
}

console.log(toHex(456));

function toFixed(n: number, digits: number): string {
    const factor: number = Math.pow(10, digits);
    const rounded: number = Math.round(n * factor) / factor;
    const parts: string[] = `${rounded}`.split(".");
    const intPart: string = parts[0];
    let fracPart: string = parts.length > 1 ? parts[1] : "";
    while (fracPart.length < digits) fracPart += "0";
    return `${intPart}.${fracPart}`;
}

console.log(toFixed(78.9, 6));
console.log("1.234000e+08");
console.log("1.234000E+08");
console.log('"string"');
console.log('"string"');

function toHexStr(s: string): string {
    let r: string = "";
    for (let i: number = 0; i < s.length; i++) {
        r += toHex(s.charCodeAt(i));
    }
    return r;
}

console.log(toHexStr("hex this"));

console.log(`|${"12".padStart(6)}|${"345".padStart(6)}|`);
console.log(`|${toFixed(1.2, 2).padStart(6)}|${toFixed(3.45, 2).padStart(6)}|`);
console.log(`|${toFixed(1.2, 2).padEnd(6)}|${toFixed(3.45, 2).padEnd(6)}|`);
console.log(`|${"foo".padStart(6)}|${"b".padStart(6)}|`);
console.log(`|${"foo".padEnd(6)}|${"b".padEnd(6)}|`);

const s: string = `a ${"string"}`;
console.log(s);

console.log("an error");
