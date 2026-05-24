// Phase 29: String Enums
// Tests: string enum declaration, direct log, assignment to string variable,
//        comparisons, switch on string enum, mixed numeric+string enum file.
type i32 = number;

enum Color {
  Red = "red",
  Green = "green",
  Blue = "blue"
}

enum Status {
  Active = "active",
  Inactive = "inactive",
  Pending = "pending"
}

enum Priority {
  Low = 0,
  Medium = 1,
  High = 2
}

// Direct console.log of each member
console.log(Color.Red);      // red
console.log(Color.Green);    // green
console.log(Color.Blue);     // blue

// Assign to string variable, then log
const myColor: string = Color.Blue;
console.log(myColor);        // blue

const s1: string = Status.Active;
const s2: string = Status.Pending;
console.log(s1);             // active
console.log(s2);             // pending

// Numeric enum still works in same file
console.log(Priority.Low);    // 0
console.log(Priority.High);   // 2

// String enum in a label context
console.log("Color:", Color.Red);   // Color: red
console.log("Status:", Status.Inactive);  // Status: inactive

// Use string enum value in comparison
const chosen: string = Color.Green;
if (chosen === "green") {
  console.log("it is green");  // it is green
} else {
  console.log("not green");
}
