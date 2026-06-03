// @expected-output:
// 2
// -1
// true
// false

const fruits: string[] = ["apple", "banana", "cherry", "date"];

function strIndexOf(arr: string[], v: string): i32 {
    for (let i: i32 = 0; i < arr.length; i++) {
        if (arr[i] === v) return i;
    }
    return -1;
}

function strIncludes(arr: string[], v: string): boolean {
    return strIndexOf(arr, v) >= 0;
}

console.log(strIndexOf(fruits, "cherry"));
console.log(strIndexOf(fruits, "grape"));
console.log(strIncludes(fruits, "banana"));
console.log(strIncludes(fruits, "mango"));
