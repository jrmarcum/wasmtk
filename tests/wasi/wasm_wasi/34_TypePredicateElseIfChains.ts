// Phase 34 — Type predicates: two sibling guards in an if/else-if chain inside a helper, each
// narrowing the same base-typed parameter to a different derived interface.
type i32 = number;

interface Item {
  typeTag: i32;
}

interface Weapon extends Item {
  damage: i32;
}

interface Armor extends Item {
  defense: i32;
}

function isWeapon(item: Item): item is Weapon {
  return item.typeTag === 1;
}

function isArmor(item: Item): item is Armor {
  return item.typeTag === 2;
}

function evaluateItem(item: Item): i32 {
  if (isWeapon(item)) {
    return item.damage;
  } else if (isArmor(item)) {
    return item.defense;
  }
  return 0;
}

export function testTypePredicateChains(): void {
  console.log("--- Test 2: Type Predicate Else-If Chains ---");

  const w: Weapon = { typeTag: 1, damage: 150 };
  const a: Armor = { typeTag: 2, defense: 75 };

  console.log("Evaluated Weapon Damage:", evaluateItem(w)); // Expected: 150
  console.log("Evaluated Armor Defense:", evaluateItem(a)); // Expected: 75
}

testTypePredicateChains();
