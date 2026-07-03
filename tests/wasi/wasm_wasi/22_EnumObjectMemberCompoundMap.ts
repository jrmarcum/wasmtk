type i32 = number;

enum DeviceStatus {
  Offline,
  Initializing,
  Online,
  Maintenance
}

class NetworkNode {
  id: i32;
  status: DeviceStatus;

  constructor(id: i32) {
    this.id = id;
    this.status = DeviceStatus.Offline; // Initial value assignment
  }

  updateStatus(next: DeviceStatus): void {
    this.status = next;
  }
}

export function testEnumClassIntegration(): void {
  console.log("--- Test 3: Enum Property Integration ---");

  const router = new NetworkNode(101);
  console.log("Initial Status Value:", router.status); // Expected: 0 (DeviceStatus.Offline)

  router.updateStatus(DeviceStatus.Online);
  console.log("Updated Status Value:", router.status); // Expected: 2 (DeviceStatus.Online)
}

testEnumClassIntegration();