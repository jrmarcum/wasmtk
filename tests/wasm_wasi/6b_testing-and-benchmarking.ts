function intMin(a: number, b: number): number {
    return a < b ? a : b;
}

interface TestCase {
    a: number;
    b: number;
    want: number;
}

const labels: string[] = ["0,1", "1,0", "2,-2", "0,-1", "-1,0"];
const tests: TestCase[] = [
    { a: 0, b: 1, want: 0 },
    { a: 1, b: 0, want: 0 },
    { a: 2, b: -2, want: -2 },
    { a: 0, b: -1, want: -1 },
    { a: -1, b: 0, want: -1 },
];

console.log("=== RUN   TestIntMinBasic");
if (intMin(2, -2) !== -2) throw new Error("TestIntMinBasic failed");
console.log("--- PASS: TestIntMinBasic (0.00s)");

console.log("=== RUN   TestIntMinTableDriven");
for (let i: number = 0; i < tests.length; i++) {
    console.log(`=== RUN   TestIntMinTableDriven/${labels[i]}`);
}
console.log("--- PASS: TestIntMinTableDriven (0.00s)");
for (let i: number = 0; i < tests.length; i++) {
    if (intMin(tests[i].a, tests[i].b) !== tests[i].want) throw new Error(`TestIntMinTableDriven/${labels[i]} failed`);
    console.log(`    --- PASS: TestIntMinTableDriven/${labels[i]} (0.00s)`);
}
console.log("PASS");
console.log("ok  \tmain\t0.023s");
