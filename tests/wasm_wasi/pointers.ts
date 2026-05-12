interface ValRef {
    val: number;
}

function zeroval(ival: number): void {
    ival = 0;
}

function zeroref(obj: ValRef): void {
    obj.val = 0;
}

let i: number = 1;
console.log("initial:", i);

zeroval(i);
console.log("zeroval:", i);

const iRef: ValRef = { val: i };
zeroref(iRef);
console.log("zeroref:", iRef.val);

console.log("reference:", `{val:${iRef.val}}`);
