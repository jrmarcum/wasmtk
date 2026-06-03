// @expected-output:
// true
// false
// true
// false
// 2

const names: string[] = ["alice", "bob", "charlie", "anna"];

function anyMatch(arr: string[], pred: (s: string) => boolean): boolean {
    for (let i: i32 = 0; i < arr.length; i++) {
        if (pred(arr[i])) return true;
    }
    return false;
}

function allMatch(arr: string[], pred: (s: string) => boolean): boolean {
    for (let i: i32 = 0; i < arr.length; i++) {
        if (!pred(arr[i])) return false;
    }
    return true;
}

function countMatch(arr: string[], pred: (s: string) => boolean): i32 {
    let count: i32 = 0;
    for (let i: i32 = 0; i < arr.length; i++) {
        if (pred(arr[i])) count = count + 1;
    }
    return count;
}

function startsWithA(s: string): boolean {
    return s[0] === "a";
}

function isLong(s: string): boolean {
    return s.length > 3;
}

console.log(anyMatch(names, startsWithA));
console.log(allMatch(names, startsWithA));
console.log(anyMatch(names, isLong));
console.log(allMatch(names, isLong));
console.log(countMatch(names, startsWithA));
