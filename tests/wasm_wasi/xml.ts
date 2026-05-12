interface Plant {
    id: number;
    name: string;
    origin: string[];
}

function buildPlantXml(plant: Plant, indent: string): string {
    let s: string = `${indent}<plant id="${plant.id}">\n`;
    s += `${indent}  <name>${plant.name}</name>\n`;
    for (let i: number = 0; i < plant.origin.length; i++) {
        s += `${indent}  <origin>${plant.origin[i]}</origin>\n`;
    }
    s += `${indent}</plant>`;
    return s;
}

const coffee: Plant = { id: 27, name: "Coffee", origin: ["Ethiopia", "Brazil"] };
const tomato: Plant = { id: 81, name: "Tomato", origin: ["Mexico", "California"] };

const coffeeXml: string = buildPlantXml(coffee, " ");
console.log(coffeeXml);

console.log('<?xml version="1.0" encoding="UTF-8"?>');
console.log(coffeeXml);

console.log(`Plant id=${coffee.id}, name=${coffee.name}, origin=[${coffee.origin[0]} ${coffee.origin[1]}]`);

const nestingXml: string = ` <nesting>\n   <parent>\n     <child>\n${buildPlantXml(coffee, "       ")}\n${buildPlantXml(tomato, "       ")}\n     </child>\n   </parent>\n </nesting>`;
console.log(nestingXml);
