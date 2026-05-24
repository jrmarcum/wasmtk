// @expected-output:
// 1
// true
// false
// 3
// 2
// true

const vegs: string[] = ["carrot", "bean", "broccoli", "beet", "corn"];

function strIndexOf(arr: string[], v: string): i32 {
    for (let i: i32 = 0; i < arr.length; i++) {
        if (arr[i] === v) return i;
    }
    return -1;
}

function strSome(arr: string[], pred: (s: string) => boolean): boolean {
    for (let i: i32 = 0; i < arr.length; i++) {
        if (pred(arr[i])) return true;
    }
    return false;
}

function strEvery(arr: string[], pred: (s: string) => boolean): boolean {
    for (let i: i32 = 0; i < arr.length; i++) {
        if (!pred(arr[i])) return false;
    }
    return true;
}

function strFilter(arr: string[], pred: (s: string) => boolean): string[] {
    const result: string[] = [];
    for (let i: i32 = 0; i < arr.length; i++) {
        if (pred(arr[i])) result.push(arr[i]);
    }
    return result;
}

function startsWithB(s: string): boolean {
    return s[0] === "b";
}

function longerThan4(s: string): boolean {
    return s.length > 4;
}

console.log(strIndexOf(vegs, "bean"));
console.log(strSome(vegs, startsWithB));
console.log(strEvery(vegs, startsWithB));

const bVegs: string[] = strFilter(vegs, startsWithB);
const longVegs: string[] = strFilter(vegs, longerThan4);

console.log(bVegs.length);
console.log(longVegs.length);
console.log(bVegs[0] === "bean");
