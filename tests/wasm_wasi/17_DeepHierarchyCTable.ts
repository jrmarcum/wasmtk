type i32 = number;

class Account {
  id: i32;
  balance: i32;

  constructor(id: i32, initial: i32) {
    this.id = id;
    this.balance = initial;
  }

  calculateBonus(): i32 {
    return this.balance / 100;
  }
}

class PremiumAccount extends Account {
  multiplier: i32;

  constructor(id: i32, initial: i32, mult: i32) {
    super(id, initial);
    this.multiplier = mult;
  }

  override calculateBonus(): i32 {
    return (this.balance / 100) * this.multiplier;
  }
}

class ExecutiveAccount extends PremiumAccount {
  flatBonus: i32;

  constructor(id: i32, initial: i32, mult: i32, flat: i32) {
    super(id, initial, mult);
    this.flatBonus = flat;
  }

  override calculateBonus(): i32 {
    // Calls super to verify method chaining behaves predictably within overrides
    return super.calculateBonus() + this.flatBonus;
  }
}

export function testVTableHierarchy(): void {
  console.log("--- Test 1: Deep VTable Hierarchy ---");

  // Verify Base Layer
  const acc1: Account = new Account(1, 1000);
  console.log("Base Bonus:", acc1.calculateBonus()); // Expected: 10

  // Verify Mid Layer (Polymorphic Assignment)
  const acc2: Account = new PremiumAccount(2, 1000, 3);
  console.log("Premium Bonus:", acc2.calculateBonus()); // Expected: 30

  // Verify Leaf Layer (Dynamic + Super Chain Lookup)
  const acc3: Account = new ExecutiveAccount(3, 1000, 3, 50);
  console.log("Executive Bonus:", acc3.calculateBonus()); // Expected: 80
}

testVTableHierarchy();