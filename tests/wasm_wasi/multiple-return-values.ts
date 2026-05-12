interface TwoNums {
    a: number;
    b: number;
}

function vals(): TwoNums {
    return { a: 3, b: 7 };
}

const r1: TwoNums = vals();
console.log(r1.a);
console.log(r1.b);

const r2: TwoNums = vals();
console.log(r2.b);
