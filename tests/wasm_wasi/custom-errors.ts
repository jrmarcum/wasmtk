interface ArgError {
    arg: number;
    msg: string;
}

interface Result {
    val: number;
    err: ArgError;
    hasErr: boolean;
}

function newArgError(arg: number, msg: string): ArgError {
    return { arg, msg };
}

function f(arg: number): Result {
    if (arg === 42) {
        return { val: -1, err: newArgError(arg, "can't work with it"), hasErr: true };
    }
    return { val: arg + 3, err: { arg: 0, msg: "" }, hasErr: false };
}

const r: Result = f(42);
if (r.hasErr) {
    console.log(r.err.arg);
    console.log(r.err.msg);
} else {
    console.log("err doesn't match ArgError");
}
