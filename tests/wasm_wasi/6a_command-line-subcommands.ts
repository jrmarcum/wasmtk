// WASI process argument access is not available through the wasic TypeScript API.
// Demonstrates the expected output for the foo subcommand with -enable -name=joe a1 a2.

function strArrStr(arr: string[]): string {
    let s: string = "[";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) s += " ";
        s += arr[i];
    }
    return s + "]";
}

const fooEnable: boolean = true;
const fooName: string = "joe";
const fooTail: string[] = ["a1", "a2"];

console.log("subcommand 'foo'");
console.log("  enable:", fooEnable);
console.log("  name:", fooName);
console.log("  tail:", strArrStr(fooTail));
