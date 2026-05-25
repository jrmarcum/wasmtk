enum DeployEnv {
  Dev = "DEVELOPMENT",
  Staging = "STAGING",
  Prod = "PRODUCTION",
  Local = 0 // Mixed scalar variant to test flexibility
}

function printEnvHeader(env: DeployEnv): void {
  if (env === DeployEnv.Prod) {
    console.log("Target Context: Live Production Node");
  } else if (env === DeployEnv.Local) {
    console.log("Target Context: Local Mock Node");
  } else {
    console.log("Target Context: Non-Production Workspace");
  }
}

export function testHeterogeneousEnums(): void {
  console.log("--- Test 2: Heterogeneous Enums ---");

  const activeEnv: DeployEnv = DeployEnv.Prod;
  printEnvHeader(activeEnv);

  const fallbackEnv: DeployEnv = DeployEnv.Local;
  printEnvHeader(fallbackEnv);
}

testHeterogeneousEnums();