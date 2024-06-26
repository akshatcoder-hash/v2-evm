import { ethers } from "ethers";
import { ConfigStorage__factory, TradeHelper__factory } from "../../../../typechain";
import { loadConfig } from "../../utils/config";
import { Command } from "commander";
import signers from "../../entities/signers";
import assetClasses from "../../entities/asset-classes";
import SafeWrapper from "../../wrappers/SafeWrapper";

type AddMarketConfig = {
  marketIndex: number;
  assetId: string;
  increasePositionFeeRateBPS: number;
  decreasePositionFeeRateBPS: number;
  initialMarginFractionBPS: number;
  maintenanceMarginFractionBPS: number;
  maxProfitRateBPS: number;
  assetClass: number;
  allowIncreasePosition: boolean;
  active: boolean;
  fundingRate: {
    maxSkewScaleUSD: ethers.BigNumber;
    maxFundingRate: ethers.BigNumber;
  };
  maxLongPositionSize: ethers.BigNumber;
  maxShortPositionSize: ethers.BigNumber;
  isAdaptiveFeeEnabled: boolean;
};

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const BigNumber = ethers.BigNumber;

  const marketConfigs: Array<AddMarketConfig> = [
    {
      marketIndex: 49,
      assetId: ethers.utils.formatBytes32String("STRK"),
      maxLongPositionSize: ethers.BigNumber.from(0),
      maxShortPositionSize: ethers.BigNumber.from(0),
      increasePositionFeeRateBPS: 5,
      decreasePositionFeeRateBPS: 5,
      initialMarginFractionBPS: 1000,
      maintenanceMarginFractionBPS: 50,
      maxProfitRateBPS: 40000,
      assetClass: 0,
      allowIncreasePosition: true,
      active: true,
      fundingRate: {
        maxSkewScaleUSD: ethers.BigNumber.from("50000000000000000000000000000000000000"),
        maxFundingRate: ethers.BigNumber.from("8000000000000000000"),
      },
      isAdaptiveFeeEnabled: true,
    },
    {
      marketIndex: 50,
      assetId: ethers.utils.formatBytes32String("PYTH"),
      maxLongPositionSize: ethers.utils.parseUnits("100000", 30),
      maxShortPositionSize: ethers.utils.parseUnits("100000", 30),
      increasePositionFeeRateBPS: 5,
      decreasePositionFeeRateBPS: 5,
      initialMarginFractionBPS: 1000,
      maintenanceMarginFractionBPS: 50,
      maxProfitRateBPS: 40000,
      assetClass: 0,
      allowIncreasePosition: true,
      active: true,
      fundingRate: {
        maxSkewScaleUSD: ethers.BigNumber.from("50000000000000000000000000000000000000"),
        maxFundingRate: ethers.BigNumber.from("8000000000000000000"),
      },
      isAdaptiveFeeEnabled: true,
    },
    {
      marketIndex: 51,
      assetId: ethers.utils.formatBytes32String("PENDLE"),
      maxLongPositionSize: ethers.utils.parseUnits("100000", 30),
      maxShortPositionSize: ethers.utils.parseUnits("100000", 30),
      increasePositionFeeRateBPS: 5,
      decreasePositionFeeRateBPS: 5,
      initialMarginFractionBPS: 1000,
      maintenanceMarginFractionBPS: 50,
      maxProfitRateBPS: 40000,
      assetClass: 0,
      allowIncreasePosition: true,
      active: true,
      fundingRate: {
        maxSkewScaleUSD: ethers.BigNumber.from("200000000000000000000000000000000000000"),
        maxFundingRate: ethers.BigNumber.from("8000000000000000000"),
      },
      isAdaptiveFeeEnabled: true,
    },
    {
      marketIndex: 52,
      assetId: ethers.utils.formatBytes32String("W"),
      maxLongPositionSize: ethers.BigNumber.from("0"),
      maxShortPositionSize: ethers.BigNumber.from("0"),
      increasePositionFeeRateBPS: 5,
      decreasePositionFeeRateBPS: 5,
      initialMarginFractionBPS: 400,
      maintenanceMarginFractionBPS: 50,
      maxProfitRateBPS: 100000,
      assetClass: 0,
      allowIncreasePosition: true,
      active: true,
      fundingRate: {
        maxSkewScaleUSD: ethers.BigNumber.from("200000000000000000000000000000000000000"),
        maxFundingRate: ethers.BigNumber.from("8000000000000000000"),
      },
      isAdaptiveFeeEnabled: true,
    },
    {
      marketIndex: 53,
      assetId: ethers.utils.formatBytes32String("ENA"),
      maxLongPositionSize: ethers.utils.parseUnits("120000", 30),
      maxShortPositionSize: ethers.utils.parseUnits("120000", 30),
      increasePositionFeeRateBPS: 5,
      decreasePositionFeeRateBPS: 5,
      initialMarginFractionBPS: 400,
      maintenanceMarginFractionBPS: 50,
      maxProfitRateBPS: 100000,
      assetClass: 0,
      allowIncreasePosition: true,
      active: true,
      fundingRate: {
        maxSkewScaleUSD: ethers.BigNumber.from("200000000000000000000000000000000000000"),
        maxFundingRate: ethers.BigNumber.from("8000000000000000000"),
      },
      isAdaptiveFeeEnabled: true,
    },
  ];

  const configStorage = ConfigStorage__factory.connect(config.storages.config, deployer);
  const tradeHelper = TradeHelper__factory.connect(config.helpers.trade, deployer);
  const safeWrapper = new SafeWrapper(chainId, config.safe, deployer);

  console.log("[ConfigStorage] Setting market config...");
  for (let i = 0; i < marketConfigs.length; i++) {
    console.log(
      `[ConfigStorage] Setting ${ethers.utils.parseBytes32String(marketConfigs[i].assetId)} market config...`
    );
    const existingMarketConfig = await configStorage.marketConfigs(marketConfigs[i].marketIndex);
    if (existingMarketConfig.assetId !== marketConfigs[i].assetId) {
      console.log(`marketIndex ${marketConfigs[i].marketIndex} wrong asset id`);
      throw "bad asset id";
    }
    // await safeWrapper.proposeTransaction(
    //   tradeHelper.address,
    //   0,
    //   tradeHelper.interface.encodeFunctionData("updateBorrowingRate", [marketConfigs[i].assetClass])
    // );
    // await safeWrapper.proposeTransaction(
    //   tradeHelper.address,
    //   0,
    //   tradeHelper.interface.encodeFunctionData("updateFundingRate", [marketConfigs[i].marketIndex])
    // );
    const tx = await safeWrapper.proposeTransaction(
      configStorage.address,
      0,
      configStorage.interface.encodeFunctionData("setMarketConfig", [
        marketConfigs[i].marketIndex,
        marketConfigs[i],
        marketConfigs[i].isAdaptiveFeeEnabled,
      ])
    );
    console.log(`[ConfigStorage] Tx: ${tx}`);
  }
  console.log("[ConfigStorage] Finished");
}

const prog = new Command();

prog.requiredOption("--chain-id <number>", "chain id", parseInt);

prog.parse(process.argv);

const opts = prog.opts();

main(opts.chainId)
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
