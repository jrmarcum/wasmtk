// The "Escape" Test
type i32 = number;
function createScaler(multiplier: i32) {
  return (val: i32) => val * multiplier; 
}

console.log(createScaler(2)(5)); // Output: 10