interface Vec2 {
    x: number;
    y: number;
}

interface Rect {
    topLeft: Vec2;
    bottomRight: Vec2;
    width: number;
}

const origin: Vec2 = { x: 0.0, y: 0.0 };
const box: Rect = { topLeft: { x: 2.0, y: 3.0 }, bottomRight: { x: 8.0, y: 7.0 }, width: 6.0 };

// Direct struct field access still works
console.log(origin.x);
console.log(box.width);

// Chained struct field access: a.b.c
console.log(box.topLeft.x);
console.log(box.topLeft.y);
console.log(box.bottomRight.x);
console.log(box.bottomRight.y);

// Chained access in template literal
const desc: string = `topLeft=(${box.topLeft.x},${box.topLeft.y})`;
console.log(desc);
