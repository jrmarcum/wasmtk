if (7 % 2 === 0) {
    console.log("7 is even");
} else {
    console.log("7 is odd");
}

if (8 % 4 === 0) {
    console.log("8 is divisible by 4");
}

if (8 % 2 === 0 || 7 % 2 === 0) {
    console.log("either 8 or 7 are even");
}

const num: number = 9;
if (num < 0) {
    console.log(num, "is negative");
} else if (num < 10) {
    console.log(num, "has 1 digit");
} else {
    console.log(num, "has multiple digits");
}
