// WASI command-line flag parsing is not available through the wasic TypeScript API.
// Demonstrates the expected output for flags -word=opt -numb=7 -fork -svar=flag.

function strArrStr(arr: string[]): string {
    let s: string = "[";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) s += " ";
        s += arr[i];
    }
    return s + "]";
}

const word: string = "opt";
const numb: number = 7;
const fork: boolean = true;
const svar: string = "flag";
const tail: string[] = [];

console.log("word:", word);
console.log("numb:", numb);
console.log("fork:", fork);
console.log("svar:", svar);
console.log("tail:", strArrStr(tail));
