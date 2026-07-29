enum LogLevel {
  Info = "INFO",
  Warn = "WARNING",
  Error = "ERROR",
}

function processLog(level: LogLevel, message: string): void {
  if (level === LogLevel.Error) {
    console.log("[CRITICAL]", level, message);
  } else {
    console.log("[LOG]", level, message);
  }
}

export function testStringEnums(): void {
  console.log("--- Test 3: String Enums ---");

  const activeLevel: LogLevel = LogLevel.Error;

  console.log("Enum Direct Value:", LogLevel.Info); // Expected: "INFO"

  processLog(LogLevel.Info, "System initialized"); // Expected: [LOG] INFO System initialized
  processLog(activeLevel, "Disk space low"); // Expected: [CRITICAL] ERROR Disk space low
}

testStringEnums();
