// Phase 48: switch fallthrough
type i32 = number;

function test(x: i32): void {
  switch (x) {
    case 1:
    case 2:
      console.log("one or two");
      break;
    case 3:
      console.log("three");
      // fallthrough to case 4
    case 4:
      console.log("three or four");
      break;
    default:
      console.log("other");
  }
}

function testDefault(x: i32): void {
  switch (x) {
    case 10:
      console.log("ten");
      break;
    default:
      console.log("not ten");
      // fallthrough after default — no break needed since it's last
  }
}

function main(): void {
  test(1);
  test(2);
  test(3);
  test(4);
  test(5);
  testDefault(10);
  testDefault(99);
}

main();
// Expected output:
// one or two
// one or two
// three
// three or four
// three or four
// other
// ten
// not ten
