function sortStrings(arr: string[]): void {
    for (let i: number = 0; i < arr.length - 1; i++) {
        for (let j: number = 0; j < arr.length - 1 - i; j++) {
            if (arr[j] > arr[j + 1]) {
                const tmp: string = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = tmp;
            }
        }
    }
}

function sortNums(arr: number[]): void {
    for (let i: number = 0; i < arr.length - 1; i++) {
        for (let j: number = 0; j < arr.length - 1 - i; j++) {
            if (arr[j] > arr[j + 1]) {
                const tmp: number = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = tmp;
            }
        }
    }
}

function strArrStr(arr: string[]): string {
    let s: string = "[";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) s += " ";
        s += arr[i];
    }
    return s + "]";
}

function numArrStr(arr: number[]): string {
    let s: string = "[";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) s += " ";
        s += `${arr[i]}`;
    }
    return s + "]";
}

const strs: string[] = ["c", "a", "b"];
sortStrings(strs);
console.log("Strings:", strArrStr(strs));

const ints: number[] = [7, 2, 4];
sortNums(ints);
console.log("Ints:   ", numArrStr(ints));

let isSorted: boolean = true;
for (let i: number = 1; i < ints.length; i++) {
    if (ints[i - 1] > ints[i]) { isSorted = false; break; }
}
console.log("Sorted: ", isSorted);
