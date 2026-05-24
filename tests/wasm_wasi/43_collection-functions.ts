const strs: string[] = ["peach", "apple", "pear", "plum"];

function indexOf(arr: string[], v: string): number {
    for (let i: number = 0; i < arr.length; i++) {
        if (arr[i] === v) return i;
    }
    return -1;
}

function includes(arr: string[], v: string): boolean {
    return indexOf(arr, v) >= 0;
}

function some(arr: string[], pred: (s: string) => boolean): boolean {
    for (let i: number = 0; i < arr.length; i++) {
        if (pred(arr[i])) return true;
    }
    return false;
}

function every(arr: string[], pred: (s: string) => boolean): boolean {
    for (let i: number = 0; i < arr.length; i++) {
        if (!pred(arr[i])) return false;
    }
    return true;
}

function filter(arr: string[], pred: (s: string) => boolean): string[] {
    const result: string[] = [];
    for (let i: number = 0; i < arr.length; i++) {
        if (pred(arr[i])) result.push(arr[i]);
    }
    return result;
}

function mapStr(arr: string[], fn: (s: string) => string): string[] {
    const result: string[] = [];
    for (let i: number = 0; i < arr.length; i++) {
        result.push(fn(arr[i]));
    }
    return result;
}

function strArrStr(arr: string[]): string {
    let s: string = "[";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) s += " ";
        s += arr[i];
    }
    return s + "]";
}

console.log(indexOf(strs, "pear"));
console.log(includes(strs, "grape"));
console.log(some(strs, (v: string) => v[0] === "p"));
console.log(every(strs, (v: string) => v[0] === "p"));
console.log(strArrStr(filter(strs, (v: string) => v[0] === "p")));
console.log(strArrStr(mapStr(strs, (v: string) => v.toUpperCase())));
