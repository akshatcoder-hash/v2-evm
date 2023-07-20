// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

/// Forge
import { TestBase } from "forge-std/Base.sol";
import { StdCheatsSafe } from "forge-std/StdCheats.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { console2 } from "forge-std/console2.sol";
import { stdJson } from "forge-std/StdJson.sol";

/// HMX tests
import { ForkEnv } from "@hmx-test/fork/bases/ForkEnv.sol";
import { Cheats } from "@hmx-test/base/Cheats.sol";
import { Deployer } from "@hmx-test/libs/Deployer.sol";

/// HMX
import { IExt01Handler } from "@hmx/handlers/interfaces/IExt01Handler.sol";
import { GlpSwitchCollateralExt } from "@hmx/extensions/switch-collateral/GlpSwitchCollateralExt.sol";

contract GlpSwitchCollateralExt_ForkTest is TestBase, Cheats, StdAssertions, StdCheatsSafe {
  uint256 constant V3_SWAP_EXACT_IN = 0x00;

  address internal constant EXT01_EXECUTOR = 0x7FDD623c90a0097465170EdD352Be27A9f3ad817;
  address internal constant USER = 0x10C69D9d8AE54FD1Ab12A4beC82c2695b977bcEC;
  uint8 internal constant SUB_ACCOUNT_ID = 0;

  IExt01Handler internal ext01Handler;
  GlpSwitchCollateralExt internal glpSwitchCollateralExt;

  function setUp() external {
    vm.createSelectFork(vm.rpcUrl("arbitrum_fork"), 113073035);

    vm.startPrank(ForkEnv.multiSig);
    Deployer.upgrade("ConfigStorage", address(ForkEnv.proxyAdmin), address(ForkEnv.configStorage));
    Deployer.upgrade("CrossMarginService", address(ForkEnv.proxyAdmin), address(ForkEnv.crossMarginService));
    vm.stopPrank();

    vm.startPrank(ForkEnv.deployer);
    glpSwitchCollateralExt = GlpSwitchCollateralExt(
      address(
        Deployer.deployGlpSwitchCollateralExt(
          address(ForkEnv.configStorage),
          address(ForkEnv.weth),
          address(ForkEnv.sGlp),
          address(ForkEnv.glpManager),
          address(ForkEnv.gmxVault),
          address(ForkEnv.gmxRewardRouterV2)
        )
      )
    );
    ext01Handler = Deployer.deployExt01Handler(
      address(ForkEnv.proxyAdmin),
      address(ForkEnv.crossMarginService),
      address(ForkEnv.liquidationService),
      address(ForkEnv.liquidityService),
      address(ForkEnv.tradeService),
      address(ForkEnv.ecoPyth2),
      50
    );
    ext01Handler.setOrderExecutor(EXT01_EXECUTOR, true);
    ext01Handler.setMinExecutionFee(1, 0.1 * 1e9);
    ForkEnv.ecoPyth2.setUpdater(address(ext01Handler), true);
    address[] memory _handlers = new address[](1);
    _handlers[0] = address(ext01Handler);
    address[] memory _services = new address[](1);
    _services[0] = address(ForkEnv.crossMarginService);
    bool[] memory _isAllows = new bool[](1);
    _isAllows[0] = true;
    ForkEnv.configStorage.setServiceExecutors(_services, _handlers, _isAllows);
    ForkEnv.configStorage.setSwitchCollateralExtension(address(ForkEnv.sGlp), address(glpSwitchCollateralExt), true);
    ForkEnv.configStorage.setSwitchCollateralExtension(address(ForkEnv.weth), address(glpSwitchCollateralExt), true);
    vm.stopPrank();

    vm.label(address(ext01Handler), "ext01Handler");
    vm.label(address(ForkEnv.crossMarginService), "crossMarginService");
  }

  function testRevert_WhenFromTokenNotCollateral() external {
    vm.startPrank(USER);
    vm.expectRevert(abi.encodeWithSignature("IConfigStorage_NotAcceptedCollateral()"));
    ext01Handler.createExtOrder{ value: 0.1 * 1e9 }(
      IExt01Handler.CreateExtOrderParams({
        orderType: 1,
        executionFee: 0.1 * 1e9,
        data: abi.encode(
          0,
          address(ForkEnv.pendle),
          address(ForkEnv.weth),
          79115385,
          41433673370671066,
          abi.encode(address(glpSwitchCollateralExt), new bytes(0))
        )
      })
    );
    vm.stopPrank();
  }

  function testRevert_WhenToTokenNotCollateral() external {
    vm.startPrank(USER);
    vm.expectRevert(abi.encodeWithSignature("IConfigStorage_NotAcceptedCollateral()"));
    ext01Handler.createExtOrder{ value: 0.1 * 1e9 }(
      IExt01Handler.CreateExtOrderParams({
        orderType: 1,
        executionFee: 0.1 * 1e9,
        data: abi.encode(
          0,
          address(ForkEnv.usdc_e),
          address(ForkEnv.pendle),
          79115385,
          41433673370671066,
          abi.encode(address(glpSwitchCollateralExt), new bytes(0))
        )
      })
    );
    vm.stopPrank();
  }

  function testRevert_WhenFromAndToTokenAreSame() external {
    vm.startPrank(USER);
    vm.expectRevert(abi.encodeWithSignature("IExt01Handler_SameFromToToken()"));
    ext01Handler.createExtOrder{ value: 0.1 * 1e9 }(
      IExt01Handler.CreateExtOrderParams({
        orderType: 1,
        executionFee: 0.1 * 1e9,
        data: abi.encode(
          0,
          address(ForkEnv.usdc_e),
          address(ForkEnv.usdc_e),
          79115385,
          41433673370671066,
          abi.encode(address(glpSwitchCollateralExt), new bytes(0))
        )
      })
    );
    vm.stopPrank();
  }

  function testRevert_WhenSlippage() external {
    vm.startPrank(USER);
    ext01Handler.createExtOrder{ value: 0.1 * 1e9 }(
      IExt01Handler.CreateExtOrderParams({
        orderType: 1,
        executionFee: 0.1 * 1e9,
        data: abi.encode(
          SUB_ACCOUNT_ID,
          address(ForkEnv.sGlp),
          address(ForkEnv.weth),
          5000000000000000000,
          2652487522183761,
          abi.encode(address(glpSwitchCollateralExt), new bytes(0))
        )
      })
    );
    vm.stopPrank();

    vm.startPrank(EXT01_EXECUTOR);
    // Taken price data from https://arbiscan.io/tx/0x2a1bea44f6b1858aef7661b19cec49a4d74e3c9fd1fedb7ab26b09ac712cc0ad
    // but change ETH to tick 0 which equals to 1 USD.
    bytes32[] memory _priceData = new bytes32[](3);
    _priceData[0] = 0x0127130192adfffffe000001ffffff00cdac00c0fd01288100bef300e5df0000;
    _priceData[1] = 0x00ddd500048e007ddd000094fff0c8000a18ffd2e7fff436fff3560008be0000;
    _priceData[2] = 0x000f9e00b0e500b5af00bc5300d656007f720000000000000000000000000000;
    bytes32[] memory _publishTimeData = new bytes32[](3);
    _publishTimeData[0] = bytes32(0);
    _publishTimeData[1] = bytes32(0);
    _publishTimeData[2] = bytes32(0);
    ext01Handler.executeOrders(1, payable(EXT01_EXECUTOR), _priceData, _publishTimeData, block.timestamp, "");
    vm.stopPrank();

    // Trader balance should be the same
    assertEq(ForkEnv.vaultStorage.traderBalances(USER, address(ForkEnv.sGlp)), 5000000000000000000);
  }

  function testRevert_WhenSwitchCollateralMakesEquityBelowIMR() external {
    vm.startPrank(USER);
    ext01Handler.createExtOrder{ value: 0.1 * 1e9 }(
      IExt01Handler.CreateExtOrderParams({
        orderType: 1,
        executionFee: 0.1 * 1e9,
        data: abi.encode(
          SUB_ACCOUNT_ID,
          address(ForkEnv.sGlp),
          address(ForkEnv.weth),
          5000000000000000000,
          0,
          abi.encode(address(glpSwitchCollateralExt), new bytes(0))
        )
      })
    );
    vm.stopPrank();

    vm.startPrank(EXT01_EXECUTOR);
    // Taken price data from https://arbiscan.io/tx/0x2a1bea44f6b1858aef7661b19cec49a4d74e3c9fd1fedb7ab26b09ac712cc0ad
    // but change ETH to tick 0 which equals to 1 USD.
    bytes32[] memory _priceData = new bytes32[](3);
    _priceData[0] = 0x0007130192adfffffe000001ffffff00cdac00c0fd01288100bef300e5df0000;
    _priceData[1] = 0x00ddd500048e007ddd000094fff0c8000a18ffd2e7fff436fff3560008be0000;
    _priceData[2] = 0x000f9e00b0e500b5af00bc5300d656007f720000000000000000000000000000;
    bytes32[] memory _publishTimeData = new bytes32[](3);
    _publishTimeData[0] = bytes32(0);
    _publishTimeData[1] = bytes32(0);
    _publishTimeData[2] = bytes32(0);
    ext01Handler.executeOrders(1, payable(EXT01_EXECUTOR), _priceData, _publishTimeData, block.timestamp, "");
    vm.stopPrank();

    // Trader balance should be the same
    assertEq(ForkEnv.vaultStorage.traderBalances(USER, address(ForkEnv.sGlp)), 5000000000000000000);
  }

  function testCorrectness_WhenSwitchCollateralFromSglpToTokenInGlpVault() external {
    vm.startPrank(USER);
    ext01Handler.createExtOrder{ value: 0.1 * 1e9 }(
      IExt01Handler.CreateExtOrderParams({
        orderType: 1,
        executionFee: 0.1 * 1e9,
        data: abi.encode(
          SUB_ACCOUNT_ID,
          address(ForkEnv.sGlp),
          address(ForkEnv.weth),
          5000000000000000000,
          0,
          abi.encode(address(glpSwitchCollateralExt), new bytes(0))
        )
      })
    );
    vm.stopPrank();

    vm.startPrank(EXT01_EXECUTOR);
    // Taken price data from https://arbiscan.io/tx/0x2a1bea44f6b1858aef7661b19cec49a4d74e3c9fd1fedb7ab26b09ac712cc0ad
    uint256 _wethBefore = ForkEnv.vaultStorage.traderBalances(USER, address(ForkEnv.weth));
    bytes32[] memory _priceData = new bytes32[](3);
    _priceData[0] = 0x0127130192adfffffe000001ffffff00cdac00c0fd01288100bef300e5df0000;
    _priceData[1] = 0x00ddd500048e007ddd000094fff0c8000a18ffd2e7fff436fff3560008be0000;
    _priceData[2] = 0x000f9e00b0e500b5af00bc5300d656007f720000000000000000000000000000;
    bytes32[] memory _publishTimeData = new bytes32[](3);
    _publishTimeData[0] = bytes32(0);
    _publishTimeData[1] = bytes32(0);
    _publishTimeData[2] = bytes32(0);
    ext01Handler.executeOrders(1, payable(EXT01_EXECUTOR), _priceData, _publishTimeData, block.timestamp, "");
    vm.stopPrank();
    uint256 _wethAfter = ForkEnv.vaultStorage.traderBalances(USER, address(ForkEnv.weth));

    // Trader balance should be the same
    assertEq(ForkEnv.vaultStorage.traderBalances(USER, address(ForkEnv.sGlp)), 0);
    assertEq(_wethAfter - _wethBefore, 2652487522183760);
  }

  function testCorrectness_WhenSwitchCollateralFromTokenInGlpVaultToSglp() external {
    vm.startPrank(USER);
    ext01Handler.createExtOrder{ value: 0.1 * 1e9 }(
      IExt01Handler.CreateExtOrderParams({
        orderType: 1,
        executionFee: 0.1 * 1e9,
        data: abi.encode(
          SUB_ACCOUNT_ID,
          address(ForkEnv.weth),
          address(ForkEnv.sGlp),
          ForkEnv.vaultStorage.traderBalances(USER, address(ForkEnv.weth)),
          0,
          abi.encode(address(glpSwitchCollateralExt), new bytes(0))
        )
      })
    );
    vm.stopPrank();

    vm.startPrank(EXT01_EXECUTOR);
    // Taken price data from https://arbiscan.io/tx/0x2a1bea44f6b1858aef7661b19cec49a4d74e3c9fd1fedb7ab26b09ac712cc0ad
    uint256 _sGlpBefore = ForkEnv.vaultStorage.traderBalances(USER, address(ForkEnv.sGlp));
    bytes32[] memory _priceData = new bytes32[](3);
    _priceData[0] = 0x0127130192adfffffe000001ffffff00cdac00c0fd01288100bef300e5df0000;
    _priceData[1] = 0x00ddd500048e007ddd000094fff0c8000a18ffd2e7fff436fff3560008be0000;
    _priceData[2] = 0x000f9e00b0e500b5af00bc5300d656007f720000000000000000000000000000;
    bytes32[] memory _publishTimeData = new bytes32[](3);
    _publishTimeData[0] = bytes32(0);
    _publishTimeData[1] = bytes32(0);
    _publishTimeData[2] = bytes32(0);
    ext01Handler.executeOrders(1, payable(EXT01_EXECUTOR), _priceData, _publishTimeData, block.timestamp, "");
    vm.stopPrank();
    uint256 _sGlpAfter = ForkEnv.vaultStorage.traderBalances(USER, address(ForkEnv.sGlp));

    // Trader balance should be the same
    assertEq(ForkEnv.vaultStorage.traderBalances(USER, address(ForkEnv.weth)), 0);
    assertEq(_sGlpAfter - _sGlpBefore, 74640579149339718);
  }
}
