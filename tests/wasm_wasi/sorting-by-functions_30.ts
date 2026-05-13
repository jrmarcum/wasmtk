interface Person {
    name: string;
    age: number;
}

function strArrStr(arr: string[]): string {
    let s: string = "[";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) s += " ";
        s += arr[i];
    }
    return s + "]";
}

function sortByLen(arr: string[]): void {
    for (let i: number = 0; i < arr.length - 1; i++) {
        for (let j: number = 0; j < arr.length - 1 - i; j++) {
            if (arr[j].length > arr[j + 1].length) {
                const tmp: string = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = tmp;
            }
        }
    }
}

function sortPersonsByAge(arr: Person[]): void {
    for (let i: number = 0; i < arr.length - 1; i++) {
        for (let j: number = 0; j < arr.length - 1 - i; j++) {
            if (arr[j].age > arr[j + 1].age) {
                const tmp: Person = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = tmp;
            }
        }
    }
}

const fruits: string[] = ["peach", "kiwi", "apple"];
sortByLen(fruits);
console.log(strArrStr(fruits));

const people: Person[] = [
    { name: "Alice", age: 25 },
    { name: "Eve", age: 2 },
    { name: "Bob", age: 35 },
];
sortPersonsByAge(people);

let pStr: string = "[";
for (let i: number = 0; i < people.length; i++) {
    if (i > 0) pStr += " ";
    pStr += `{${people[i].name} ${people[i].age}}`;
}
pStr += "]";
console.log(pStr);
