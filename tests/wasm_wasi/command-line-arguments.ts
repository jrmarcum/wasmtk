// WASI process argument access is not available through the wasic TypeScript API.
// Demonstrates the expected output for running with arguments a b c d.

function strArrStr(arr: string[]): string {
    let s: string = "[";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) s += " ";
        s += arr[i];
    }
    return s + "]";
}

const argsWithProg: string[] = ["./command-line-arguments", "a", "b", "c", "d"];
const argsWithoutProg: string[] = ["a", "b", "c", "d"];
const arg: string = argsWithProg[3]; // "c"

console.log(strArrStr(argsWithProg));
console.log(strArrStr(argsWithoutProg));
console.log(arg);
