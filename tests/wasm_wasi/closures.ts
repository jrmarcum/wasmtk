function intSeq(): () => number {
    let i: number = 0;
    return function(): number {
        i++;
        return i;
    };
}

const nextInt = intSeq();
console.log(nextInt());
console.log(nextInt());
console.log(nextInt());

const newInts = intSeq();
console.log(newInts());
