// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { TestBase } from "forge-std/Base.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheatsSafe } from "forge-std/StdCheats.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";

import { Deployment } from "../../script/Deployment.s.sol";
import { StorageDeployment } from "../deployment/StorageDeployment.s.sol";

// Mocks
import { MockErc20 } from "../mocks/MockErc20.sol";
import { MockPyth } from "pyth-sdk-solidity/MockPyth.sol";
import { MockErc20 } from "../mocks/MockErc20.sol";
import { MockCalculator } from "../mocks/MockCalculator.sol";
import { MockPerpStorage } from "../mocks/MockPerpStorage.sol";
import { MockVaultStorage } from "../mocks/MockVaultStorage.sol";
import { MockOracleMiddleware } from "../mocks/MockOracleMiddleware.sol";

import { Deployment } from "../../script/Deployment.s.sol";
import { StorageDeployment } from "../deployment/StorageDeployment.s.sol";
// Interfaces
import { IPerpStorage } from "../../src/storages/interfaces/IPerpStorage.sol";
import { IConfigStorage } from "../../src/storages/interfaces/IConfigStorage.sol";

// Calculator
import { Calculator } from "../../src/contracts/Calculator.sol";

// Handlers
import { CrossMarginHandler } from "../../src/handlers/CrossMarginHandler.sol";

// Services
import { CrossMarginService } from "../../src/services/CrossMarginService.sol";

// Storages
import { ConfigStorage } from "../../src/storages/ConfigStorage.sol";
import { PerpStorage } from "../../src/storages/PerpStorage.sol";
import { VaultStorage } from "../../src/storages/VaultStorage.sol";

import { IConfigStorage } from "../../src/storages/interfaces/IConfigStorage.sol";

import { PLPv2 } from "../../src/contracts/PLPv2.sol";

abstract contract BaseTest is TestBase, Deployment, StorageDeployment, StdAssertions, StdCheatsSafe {
  address internal ALICE;
  address internal BOB;
  address internal CAROL;
  address internal DAVE;

  // storages
  ConfigStorage internal configStorage;
  PerpStorage internal perpStorage;
  VaultStorage internal vaultStorage;

  // other contracts
  PLPv2 internal plp;
  Calculator internal calculator;

  // mock
  MockPyth internal mockPyth;
  MockCalculator internal mockCalculator;
  MockPerpStorage internal mockPerpStorage;
  MockVaultStorage internal mockVaultStorage;
  MockOracleMiddleware internal mockOracle;

  MockErc20 internal weth;
  MockErc20 internal wbtc;
  MockErc20 internal dai;
  MockErc20 internal usdc;
  MockErc20 internal usdt;

  MockErc20 internal bad;

  // market indexes
  uint256 ethMarketIndex;
  uint256 btcMarketIndex;

  bytes32 internal constant wethPriceId = 0x0000000000000000000000000000000000000000000000000000000000000001;
  bytes32 internal constant wbtcPriceId = 0x0000000000000000000000000000000000000000000000000000000000000002;
  bytes32 internal constant daiPriceId = 0x0000000000000000000000000000000000000000000000000000000000000003;
  bytes32 internal constant usdcPriceId = 0x0000000000000000000000000000000000000000000000000000000000000004;
  bytes32 internal constant usdtPriceId = 0x0000000000000000000000000000000000000000000000000000000000000005;

  constructor() {
    // Creating a mock Pyth instance with 60 seconds valid time period
    // and 1 wei for updating price.
    mockPyth = new MockPyth(60, 1);

    ALICE = makeAddr("Alice");
    BOB = makeAddr("BOB");
    CAROL = makeAddr("CAROL");
    DAVE = makeAddr("DAVE");

    weth = deployMockErc20("Wrapped Ethereum", "WETH", 18);
    wbtc = deployMockErc20("Wrapped Bitcoin", "WBTC", 8);
    dai = deployMockErc20("DAI Stablecoin", "DAI", 18);
    usdc = deployMockErc20("USD Coin", "USDC", 6);
    usdc = deployMockErc20("USD Tether", "USDT", 6);
    bad = deployMockErc20("Bad Coin", "BAD", 2);

    plp = new PLPv2();

    configStorage = deployConfigStorage();
    perpStorage = deployPerpStorage();
    vaultStorage = deployVaultStorage();

    mockOracle = new MockOracleMiddleware();
    mockCalculator = new MockCalculator(address(mockOracle));

    mockPerpStorage = new MockPerpStorage();
    mockVaultStorage = new MockVaultStorage();
    mockOracle = new MockOracleMiddleware();
    configStorage = new ConfigStorage();

    _setUpLiquidityConfig();
    _setUpSwapConfig();
    _setUpTradingConfig();
    _setUpMarketConfigs();
    _setUpPlpTokenConfigs();
    _setUpCollateralTokenConfigs();

    // set general config
    configStorage.setCalculator(address(mockCalculator));
    configStorage.setOracle(address(mockOracle));
  }

  // --------- Deploy Helpers ---------
  function deployMockErc20(string memory name, string memory symbol, uint8 decimals) internal returns (MockErc20) {
    return new MockErc20(name, symbol, decimals);
  }

  function deployPerp88v2() internal returns (Deployment.DeployReturnVars memory) {
    DeployLocalVars memory deployLocalVars = DeployLocalVars({ pyth: mockPyth, defaultOracleStaleTime: 300 });
    return deploy(deployLocalVars);
  }

  /**
   * HANDLER
   */

  function deployCrossMarginHandler(
    address _crossMarginService,
    address _configStorage
  ) internal returns (CrossMarginHandler) {
    return new CrossMarginHandler(_crossMarginService, _configStorage);
  }

  /**
   * SERVICE
   */

  function deployCrossMarginService(
    address _configStorage,
    address _vaultStorage,
    address _calculator
  ) internal returns (CrossMarginService) {
    return new CrossMarginService(_configStorage, _vaultStorage, _calculator);
  }

  /**
   * CALCULATOR
   */

  function deployCalculator(
    address _oracle,
    address _vaultStorage,
    address _perpStorage,
    address _configStorage
  ) internal returns (Calculator) {
    return new Calculator(_oracle, _vaultStorage, _perpStorage, _configStorage);
  }

  /**
   * TEST HELPERS
   */

  /// @notice Helper function to create a price feed update data.
  /// @dev The price data is in the format of [wethPrice, wbtcPrice, daiPrice, usdcPrice] and in 8 decimals.
  /// @param priceData The price data to create the update data.
  function buildPythUpdateData(int64[] memory priceData) internal view returns (bytes[] memory) {
    require(priceData.length == 4, "invalid price data length");
    bytes[] memory priceDataBytes = new bytes[](4);
    for (uint256 i = 1; i <= priceData.length; ) {
      priceDataBytes[i - 1] = mockPyth.createPriceFeedUpdateData(
        bytes32(uint256(i)),
        priceData[i - 1] * 1e8,
        0,
        -8,
        priceData[i - 1] * 1e8,
        0,
        uint64(block.timestamp)
      );
      unchecked {
        ++i;
      }
    }
    return priceDataBytes;
  }

  /// --------- Setup helper ------------

  /// @notice set up liquidity config
  function _setUpLiquidityConfig() private {
    configStorage.setLiquidityConfig(
      IConfigStorage.LiquidityConfig({
        depositFeeRate: 0,
        withdrawFeeRate: 0,
        maxPLPUtilization: (80 * 1e18) / 100,
        plpSafetyBufferThreshold: 0,
        taxFeeRate: 0,
        flashLoanFeeRate: 0,
        dynamicFeeEnabled: false,
        enabled: true,
        plpTotalTokenWeight: 0
      })
    );
  }

  /// @notice set up swap config
  function _setUpSwapConfig() private {
    configStorage.setSwapConfig(IConfigStorage.SwapConfig({ stablecoinSwapFeeRate: 0, swapFeeRate: 0 }));
  }

  /// @notice set up trading config
  function _setUpTradingConfig() private {
    configStorage.setTradingConfig(
      IConfigStorage.TradingConfig({ fundingInterval: 1, borrowingDevFeeRate: 0, minProfitDuration: 0, maxPosition: 5 })
    );
  }

  /// @notice set up all market configs in Perp
  function _setUpMarketConfigs() private {
    // add market config
    IConfigStorage.MarketConfig memory _ethConfig = IConfigStorage.MarketConfig({
      assetId: "ETH",
      assetClass: 1,
      maxProfitRate: 9e18,
      longMaxOpenInterestUSDE30: 1_000_000 * 1e30,
      shortMaxOpenInterestUSDE30: 1_000_000 * 1e30,
      minLeverage: 1,
      initialMarginFraction: 0.01 * 1e18,
      maintenanceMarginFraction: 0.005 * 1e18,
      increasePositionFeeRate: 0,
      decreasePositionFeeRate: 0,
      maxFundingRate: 0,
      priceConfidentThreshold: 0.01 * 1e18,
      allowIncreasePosition: true,
      active: true
    });

    IConfigStorage.MarketConfig memory _btcConfig = IConfigStorage.MarketConfig({
      assetId: "BTC",
      assetClass: 1,
      maxProfitRate: 9e18,
      longMaxOpenInterestUSDE30: 1_000_000 * 1e30,
      shortMaxOpenInterestUSDE30: 1_000_000 * 1e30,
      minLeverage: 1,
      initialMarginFraction: 0.01 * 1e18,
      maintenanceMarginFraction: 0.005 * 1e18,
      increasePositionFeeRate: 0,
      decreasePositionFeeRate: 0,
      maxFundingRate: 0,
      priceConfidentThreshold: 0.01 * 1e18,
      allowIncreasePosition: true,
      active: true
    });

    ethMarketIndex = configStorage.addMarketConfig(_ethConfig);
    btcMarketIndex = configStorage.addMarketConfig(_btcConfig);
  }

  /// @notice set up all plp token configs in Perp
  function _setUpPlpTokenConfigs() private {
    // set PLP token
    configStorage.setPLP(address(plp));

    // add Accepted Token for LP config
    IConfigStorage.PLPTokenConfig[] memory _plpTokenConfig = new IConfigStorage.PLPTokenConfig[](5);
    // WETH
    _plpTokenConfig[0] = IConfigStorage.PLPTokenConfig({
      decimals: 18,
      targetWeight: 20e18,
      bufferLiquidity: 0,
      maxWeightDiff: 0,
      isStableCoin: false,
      accepted: true
    });
    // WBTC
    _plpTokenConfig[1] = IConfigStorage.PLPTokenConfig({
      decimals: 8,
      targetWeight: 20e18,
      bufferLiquidity: 0,
      maxWeightDiff: 0,
      isStableCoin: false,
      accepted: true
    });
    // DAI
    _plpTokenConfig[2] = IConfigStorage.PLPTokenConfig({
      decimals: 18,
      targetWeight: 10e18,
      bufferLiquidity: 0,
      maxWeightDiff: 0,
      isStableCoin: true,
      accepted: true
    });
    // USDC
    _plpTokenConfig[3] = IConfigStorage.PLPTokenConfig({
      decimals: 6,
      targetWeight: 30e18,
      bufferLiquidity: 0,
      maxWeightDiff: 0,
      isStableCoin: true,
      accepted: true
    });
    // USDT
    _plpTokenConfig[4] = IConfigStorage.PLPTokenConfig({
      decimals: 6,
      targetWeight: 20e18,
      bufferLiquidity: 0,
      maxWeightDiff: 0,
      isStableCoin: true,
      accepted: true
    });

    configStorage.setPlpTokenConfig(address(weth), _plpTokenConfig[0]);
    configStorage.setPlpTokenConfig(address(wbtc), _plpTokenConfig[1]);
    configStorage.setPlpTokenConfig(address(dai), _plpTokenConfig[2]);
    configStorage.setPlpTokenConfig(address(usdc), _plpTokenConfig[3]);
    configStorage.setPlpTokenConfig(address(usdt), _plpTokenConfig[4]);
  }

  /// @notice set up all collateral token configs in Perp
  function _setUpCollateralTokenConfigs() private {
    IConfigStorage.CollateralTokenConfig memory _collatTokenConfigWeth = IConfigStorage.CollateralTokenConfig({
      decimals: weth.decimals(),
      collateralFactor: 0.8 * 1e18,
      isStableCoin: false,
      accepted: true,
      settleStrategy: address(0)
    });

    configStorage.setCollateralTokenConfig(address(weth), _collatTokenConfigWeth);

    IConfigStorage.CollateralTokenConfig memory _collatTokenConfigWbtc = IConfigStorage.CollateralTokenConfig({
      decimals: wbtc.decimals(),
      collateralFactor: 0.9 * 1e18,
      isStableCoin: false,
      accepted: true,
      settleStrategy: address(0)
    });

    configStorage.setCollateralTokenConfig(address(wbtc), _collatTokenConfigWbtc);
  }

  function abs(int256 x) external pure returns (uint256) {
    return uint256(x >= 0 ? x : -x);
  }
}
