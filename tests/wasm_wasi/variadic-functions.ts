function sum(...nums: number[]): void {
    let s: string = "[";
    for (let i: number = 0; i < nums.length; i++) {
        if (i > 0) s += " ";
        s += `${nums[i]}`;
    }
    s += "]";
    let total: number = 0;
    for (let i: number = 0; i < nums.length; i++) {
        total += nums[i];
    }
    console.log(`${s} ${total}`);
}

sum(1, 2);
sum(1, 2, 3);

const nums: number[] = [1, 2, 3, 4];
sum(...nums);
