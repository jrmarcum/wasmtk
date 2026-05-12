function plus(a: number, b: number): number {
    return a + b;
}

function plusPlus(a: number, b: number, c: number): number {
    return a + b + c;
}

const res: number = plus(1, 2);
console.log("1+2 =", res);

const res2: number = plusPlus(1, 2, 3);
console.log("1+2+3 =", res2);
