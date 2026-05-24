function strArrStr(arr: string[]): string {
    let s: string = "[";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) s += " ";
        s += arr[i];
    }
    return s + "]";
}

function numArrStr(arr: number[]): string {
    let s: string = "[";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) s += " ";
        s += `${arr[i]}`;
    }
    return s + "]";
}

const sl: string[] = ["", "", ""];
console.log("emp:", strArrStr(sl));

sl[0] = "a";
sl[1] = "b";
sl[2] = "c";
console.log("set:", strArrStr(sl));
console.log("get:", sl[2]);
console.log("len:", sl.length);

sl.push("d");
sl.push("e");
sl.push("f");
console.log("apd:", strArrStr(sl));

const c: string[] = sl.slice(0);
console.log("cpy:", strArrStr(c));

const l1: string[] = sl.slice(2, 5);
console.log("sl1:", strArrStr(l1));
const l2: string[] = sl.slice(0, 5);
console.log("sl2:", strArrStr(l2));
const l3: string[] = sl.slice(2);
console.log("sl3:", strArrStr(l3));

const t: string[] = ["g", "h", "i"];
console.log("dcl:", strArrStr(t));

const twoD: number[][] = [];
for (let i: number = 0; i < 3; i++) {
    const inner: number[] = [];
    for (let j: number = 0; j <= i; j++) {
        inner.push(i + j);
    }
    twoD.push(inner);
}

let twoDStr: string = "[";
for (let i: number = 0; i < twoD.length; i++) {
    if (i > 0) twoDStr += " ";
    twoDStr += numArrStr(twoD[i]);
}
twoDStr += "]";
console.log("2d:", twoDStr);
