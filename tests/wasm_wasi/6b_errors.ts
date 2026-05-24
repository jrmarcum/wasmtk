interface Result {
    val: number;
    errMsg: string;
    hasErr: boolean;
}

function f1(arg: number): Result {
    if (arg === 42) {
        return { val: -1, errMsg: "can't work with 42", hasErr: true };
    }
    return { val: arg + 3, errMsg: "", hasErr: false };
}

interface ArgError {
    arg: number;
    prob: string;
}

interface Result2 {
    val: number;
    argErr: ArgError;
    hasErr: boolean;
}

function f2(arg: number): Result2 {
    if (arg === 42) {
        return { val: -1, argErr: { arg, prob: "can't work with 42" }, hasErr: true };
    }
    return { val: arg + 3, argErr: { arg: 0, prob: "" }, hasErr: false };
}

const inputs: number[] = [7, 42];

for (let i: number = 0; i < inputs.length; i++) {
    const r: Result = f1(inputs[i]);
    if (r.hasErr) {
        console.log("f1 failed:", r.errMsg);
    } else {
        console.log("f1 worked:", r.val);
    }
}

for (let i: number = 0; i < inputs.length; i++) {
    const r: Result2 = f2(inputs[i]);
    if (r.hasErr) {
        console.log("f2 failed:", `${r.argErr.arg} - ${r.argErr.prob}`);
    } else {
        console.log("f2 worked:", r.val);
    }
}

const ae: Result2 = f2(42);
if (ae.hasErr) {
    console.log(ae.argErr.arg);
    console.log(ae.argErr.prob);
}
