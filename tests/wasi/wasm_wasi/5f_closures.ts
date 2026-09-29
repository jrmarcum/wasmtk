function intSeq(): () => number {
    let i: number = 0;
    return function(): number {
        i++;
        return i;
    };
}

const nextInt: () => number = intSeq();
console.log(nextInt());
console.log(nextInt());
console.log(nextInt());

const newInts: () => number = intSeq();
console.log(newInts());
