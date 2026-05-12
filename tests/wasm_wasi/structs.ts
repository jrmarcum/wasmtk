interface Person {
    name: string;
    age: number;
}

interface Dog {
    name: string;
    isGood: boolean;
}

function newPerson(name: string, age: number): Person {
    return { name, age };
}

function newPersonWithAge(name: string): Person {
    return { name, age: 42 };
}

function fmtPerson(p: Person): string {
    return `{${p.name} ${p.age}}`;
}

console.log(fmtPerson(newPerson("Bob", 20)));
console.log(fmtPerson(newPerson("Alice", 30)));
console.log(fmtPerson({ name: "Fred", age: 0 }));
console.log(fmtPerson(newPersonWithAge("Ann")));
console.log(fmtPerson(newPersonWithAge("Jon")));

const s: Person = newPerson("Sean", 50);
console.log(s.name);
console.log(s.age);

s.age = 51;
console.log(s.age);

const dog: Dog = { name: "Rex", isGood: true };
console.log(`{${dog.name} ${dog.isGood}}`);
