function mulberry32(seed: number): () => number {
    let s: number = seed;
    return function(): number {
        s = (s + 0x6D2B79F5) | 0;
        let t: number = Math.imul(s ^ (s >>> 15), 1 | s);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

const r1: () => number = mulberry32(42);
const v1: number = Math.floor(r1() * 100);
const v2: number = Math.floor(r1() * 100);
console.log(`${v1},${v2}`);

const r2: () => number = mulberry32(42);
console.log(r2());

const r3: () => number = mulberry32(42);
const v3: number = r3() * 5 + 5;
const v4: number = r3() * 5 + 5;
console.log(`${v3},${v4}`);

const r4: () => number = mulberry32(42);
const a1: number = Math.floor(r4() * 100);
const a2: number = Math.floor(r4() * 100);
console.log(`${a1},${a2}`);

const r5: () => number = mulberry32(42);
const b1: number = Math.floor(r5() * 100);
const b2: number = Math.floor(r5() * 100);
console.log(`${b1},${b2}`);
