const a: number[] = [0, 0, 0, 0, 0];

function numArrStr(arr: number[]): string {
    let s: string = "[";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) s += " ";
        s += `${arr[i]}`;
    }
    return s + "]";
}

console.log("emp:", numArrStr(a));

a[4] = 100;
console.log("set:", numArrStr(a));
console.log("get:", a[4]);
console.log("len:", a.length);

const b: number[] = [1, 2, 3, 4, 5];
console.log("dcl:", numArrStr(b));

const twoD: number[][] = [[0, 0, 0], [0, 0, 0]];
for (let row: number = 0; row < 2; row++) {
    for (let col: number = 0; col < 3; col++) {
        twoD[row][col] = row + col;
    }
}

let twoDStr: string = "[";
for (let r: number = 0; r < twoD.length; r++) {
    if (r > 0) twoDStr += " ";
    twoDStr += numArrStr(twoD[r]);
}
twoDStr += "]";
console.log("2d:", twoDStr);
