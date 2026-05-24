interface Plant {
    id: number;
    name: string;
    origin1: string;
    origin2: string;
}

function printPlantXml(plant: Plant, indent: string): void {
    console.log(`${indent}<plant id="${plant.id}">`);
    console.log(`${indent}  <name>${plant.name}</name>`);
    console.log(`${indent}  <origin>${plant.origin1}</origin>`);
    console.log(`${indent}  <origin>${plant.origin2}</origin>`);
    console.log(`${indent}</plant>`);
}

const coffee: Plant = { id: 27, name: "Coffee", origin1: "Ethiopia", origin2: "Brazil" };
const tomato: Plant = { id: 81, name: "Tomato", origin1: "Mexico", origin2: "California" };

printPlantXml(coffee, " ");

console.log('<?xml version="1.0" encoding="UTF-8"?>');
printPlantXml(coffee, " ");

console.log(`Plant id=${coffee.id}, name=${coffee.name}, origin=[${coffee.origin1} ${coffee.origin2}]`);

console.log(" <nesting>");
console.log("   <parent>");
console.log("     <child>");
printPlantXml(coffee, "       ");
printPlantXml(tomato, "       ");
console.log("     </child>");
console.log("   </parent>");
console.log(" </nesting>");
