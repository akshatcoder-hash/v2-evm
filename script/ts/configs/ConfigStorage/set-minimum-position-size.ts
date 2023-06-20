import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { ConfigStorage__factory, EcoPyth__factory, PythAdapter__factory } from "../../../../typechain";
import { getConfig } from "../../utils/config";

const config = getConfig();
const minimumPositionSize = 10;

async function main() {
  const deployer = (await ethers.getSigners())[0];
  const configStorage = ConfigStorage__factory.connect(config.storages.config, deployer);

  console.log("> ConfigStorage: Set Minimum Position Size...");
  await (await configStorage.setMinimumPositionSize(minimumPositionSize)).wait();
  console.log("> ConfigStorage: Set Minimum Position Size success!");
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
