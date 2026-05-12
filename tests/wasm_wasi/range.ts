const nums: number[] = [2, 3, 4];
let sum: number = 0;
for (let idx: number = 0; idx < nums.length; idx++) {
    sum += nums[idx];
}
console.log("sum:", sum);

for (let idx: number = 0; idx < nums.length; idx++) {
    if (nums[idx] === 3) {
        console.log("index:", idx);
    }
}

const kvKeys: string[] = ["a", "b"];
const kvVals: string[] = ["apple", "banana"];
for (let i: number = 0; i < kvKeys.length; i++) {
    console.log(`${kvKeys[i]} -> ${kvVals[i]}`);
}

for (let i: number = 0; i < kvKeys.length; i++) {
    console.log("key:", kvKeys[i]);
}

// 'g' = code point 103, 'o' = code point 111
console.log(0, 103);
console.log(1, 111);
