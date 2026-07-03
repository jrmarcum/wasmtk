// @expected-output:
// 3
// 4
// true

const words: string[] = ["red", "green", "blue", "rouge", "rose"];

function strFilter(arr: string[], pred: (s: string) => boolean): string[] {
    const result: string[] = [];
    for (let i: i32 = 0; i < arr.length; i++) {
        if (pred(arr[i])) result.push(arr[i]);
    }
    return result;
}

function startsWithR(s: string): boolean {
    return s[0] === "r";
}

function longerThan3(s: string): boolean {
    return s.length > 3;
}

const rWords: string[] = strFilter(words, startsWithR);
const longWords: string[] = strFilter(words, longerThan3);

console.log(rWords.length);
console.log(longWords.length);
console.log(rWords[0] === "red");
