const i: number = 2;
let writeResult: string = "";
switch (i) {
    case 1: writeResult = "one"; break;
    case 2: writeResult = "two"; break;
    case 3: writeResult = "three"; break;
}
console.log("write", i, "as", writeResult);

const day: number = 2;
switch (day) {
    case 0:
    case 6:
        console.log("It's the weekend");
        break;
    default:
        console.log("It's a weekday");
}

const hour: number = 15;
if (hour < 12) {
    console.log("It's before noon");
} else {
    console.log("It's after noon");
}

function whatAmI(tag: string): string {
    switch (tag) {
        case "bool": return "bool";
        case "int": return "int";
        default: return `unknown type ${tag}`;
    }
}
console.log(whatAmI("bool"));
console.log(whatAmI("int"));
console.log(whatAmI("string"));
