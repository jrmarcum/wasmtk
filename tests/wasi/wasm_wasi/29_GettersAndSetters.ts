type i32 = number;

class TemperatureSensor {
  private _celsius: i32;

  constructor(celsius: i32) {
    this._celsius = celsius;
  }

  // Getter method
  get fahrenheit(): i32 {
    return (this._celsius * 9 / 5) + 32;
  }

  // Setter method
  set fahrenheit(f: i32) {
    this._celsius = (f - 32) * 5 / 9;
  }

  get celsius(): i32 {
    return this._celsius;
  }
}

export function testGettersAndSetters(): void {
  console.log("--- Test 2: Getters and Setters ---");

  const sensor = new TemperatureSensor(0);

  console.log("Initial Celsius:", sensor.celsius); // Expected: 0
  console.log("Initial Fahrenheit:", sensor.fahrenheit); // Expected: 32 (via getter)

  // Update via setter
  sensor.fahrenheit = 212;

  console.log("Updated Celsius:", sensor.celsius); // Expected: 100 (via setter calculation)
  console.log("Updated Fahrenheit:", sensor.fahrenheit); // Expected: 212
}

testGettersAndSetters();
