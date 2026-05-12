const mKeys: string[] = [];
const mVals: number[] = [];

function mapSet(k: string, v: number): void {
    for (let i: number = 0; i < mKeys.length; i++) {
        if (mKeys[i] === k) { mVals[i] = v; return; }
    }
    mKeys.push(k);
    mVals.push(v);
}

function mapGet(k: string): number {
    for (let i: number = 0; i < mKeys.length; i++) {
        if (mKeys[i] === k) return mVals[i];
    }
    return 0;
}

function mapDel(k: string): void {
    for (let i: number = 0; i < mKeys.length; i++) {
        if (mKeys[i] === k) {
            mKeys.splice(i, 1);
            mVals.splice(i, 1);
            return;
        }
    }
}

function mapHas(k: string): boolean {
    for (let i: number = 0; i < mKeys.length; i++) {
        if (mKeys[i] === k) return true;
    }
    return false;
}

function mapStr(): string {
    const pairs: string[] = [];
    for (let i: number = 0; i < mKeys.length; i++) {
        pairs.push(`${mKeys[i]}:${mVals[i]}`);
    }
    pairs.sort();
    let s: string = "map[";
    for (let i: number = 0; i < pairs.length; i++) {
        if (i > 0) s += " ";
        s += pairs[i];
    }
    return s + "]";
}

mapSet("k1", 7);
mapSet("k2", 13);
console.log("map:", mapStr());

const v1: number = mapGet("k1");
console.log("v1:", v1);

const v3: number = mapGet("k3");
console.log("v3:", v3);

console.log("len:", mKeys.length);

mapDel("k2");
console.log("map:", mapStr());

const prs: boolean = mapHas("k2");
console.log("prs:", prs);

const n2Keys: string[] = ["foo", "bar"];
const n2Vals: number[] = [1, 2];
const n2Pairs: string[] = [];
for (let i: number = 0; i < n2Keys.length; i++) {
    n2Pairs.push(`${n2Keys[i]}:${n2Vals[i]}`);
}
n2Pairs.sort();
let n2Str: string = "map[";
for (let i: number = 0; i < n2Pairs.length; i++) {
    if (i > 0) n2Str += " ";
    n2Str += n2Pairs[i];
}
n2Str += "]";
console.log("map:", n2Str);
