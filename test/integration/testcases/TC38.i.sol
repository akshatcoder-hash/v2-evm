// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { LiquidityTester } from "@hmx-test/testers/LiquidityTester.sol";
import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";

contract TC38 is BaseIntTest_WithActions {
  function testCorrectness_TC38_MarketAveragePriceCalculation() external {
    // T0: Initialized state
    // ALICE as liquidity provider
    // BOB as trader
    IConfigStorage.MarketConfig memory _marketConfig = configStorage.getMarketConfigByIndex(wbtcMarketIndex);

    _marketConfig.maxLongPositionSize = 20_000_000 * 1e30;
    _marketConfig.maxShortPositionSize = 20_000_000 * 1e30;
    configStorage.setMarketConfig(wbtcMarketIndex, _marketConfig);

    // T1: Add liquidity in pool USDC 100_000 , WBTC 100
    vm.deal(ALICE, executionOrderFee);
    wbtc.mint(ALICE, 100 * 1e8);

    addLiquidity(
      ALICE,
      ERC20(address(wbtc)),
      100 * 1e8,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );

    vm.deal(ALICE, executionOrderFee);
    usdc.mint(ALICE, 100_000 * 1e6);

    addLiquidity(
      ALICE,
      ERC20(address(usdc)),
      100_000 * 1e6,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );

    {
      // PLP => 1_994_000.00(WBTC) + 100_000 (USDC)
      assertPLPTotalSupply(2_094_000 * 1e18);

      // assert PLP
      assertTokenBalanceOf(ALICE, address(plpV2), 2_094_000 * 1e18);
      assertPLPLiquidity(address(wbtc), 99.7 * 1e8);
      assertPLPLiquidity(address(usdc), 100_000 * 1e6);
    }

    // T2: Open 2 positions in the same market and the same exposure
    {
      // Assert collateral (PLP 100,000 + Collateral 1,000) => 101_000
      assertVaultTokenBalance(address(usdc), 100_000 * 1e6, "TC38: before deposit collateral");
    }

    usdc.mint(BOB, 100_000 * 1e6);
    usdc.mint(CAROL, 100_000 * 1e6);
    depositCollateral(BOB, 0, ERC20(address(usdc)), 100_000 * 1e6);
    depositCollateral(CAROL, 0, ERC20(address(usdc)), 100_000 * 1e6);

    {
      // Assert collateral (PLP 100,000 + Collateral 1,000) => 101_000
      assertVaultTokenBalance(address(usdc), 300_000 * 1e6, "TC38: before deposit collateral");
    }

    //  Open position
    // - Long ETHUSD 100,000 USD (Tp in wbtc) //  (100_000 + 0.1%) => 100_100

    // Long ETH
    vm.deal(BOB, 1 ether);
    marketBuy(BOB, 0, wethMarketIndex, 100_000 * 1e30, address(usdc), tickPrices, publishTimeDiff, block.timestamp);

    // PLP LIQUIDITY 99.7 WBTC, 100_000 usdc
    {
      /* 
      BEFORE T3

      Pending Borrowing Fee = 0 (no skip)
      AUM = PLP VALUE - PNL + PENDING_BORROWING_FEE
      AUM = 2093835074056630000000000000000000000 - (-65469) +0
      AUM = 2093835074056630000000000000000065469
      PNL = plpValue - aum + pendingBorrowingFee) negative of PNL means plp is profit
      */

      uint256 plpValueBefore = calculator.getPLPValueE30(false);
      uint256 pendingBorrowingFeeBefore = calculator.getPendingBorrowingFeeE30();
      uint256 aumBefore = calculator.getAUME30(false);

      assertApproxEqRel(plpValueBefore, 2093835074056630000000000000000000000, MAX_DIFF, "PLP TVL Before Feed Price");
      assertApproxEqRel(pendingBorrowingFeeBefore, 0, MAX_DIFF, "Pending Borrowing Fee Before Feed Price");
      assertApproxEqRel(aumBefore, 2093835074056630000000000000000065469, MAX_DIFF, "AUM Before Feed Price");

      assertApproxEqRel(
        -int256(aumBefore - plpValueBefore - pendingBorrowingFeeBefore),
        -65469,
        MAX_DIFF,
        "GLOBAL PNLE30"
      );
    }

    {
      // Assert positions before T3
      (int256 _BobUnrealizedPnlE30, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(BOB, 0), 0, 0);
      (int256 _CarolUnrealizedPnlE30, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(CAROL, 0), 0, 0);

      assertEq(_BobUnrealizedPnlE30, 0, "T2: Bob unrealized Pnl");
      assertEq(_CarolUnrealizedPnlE30, 0, "T2: CAROL unrealized Pnl");
    }

    // T3: CAROL open new position with the same market and same exposure with BOB
    // - ETH 1,500 => 1,600
    {
      skip(1);
      tickPrices[0] = 73781; // ETH tick price $1,600
      setPrices(tickPrices, publishTimeDiff);
    }

    // Long ETH
    vm.deal(CAROL, 1 ether);
    marketBuy(CAROL, 0, wethMarketIndex, 100_000 * 1e30, address(usdc), tickPrices, publishTimeDiff, block.timestamp);

    {
      // Assert positions
      (int256 _BobUnrealizedPnlE30, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(BOB, 0), 0, 0);
      (int256 _CarolUnrealizedPnlE30, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(CAROL, 0), 0, 0);

      assertEq(_BobUnrealizedPnlE30, 0, "T3: Bob unrealized Pnl");
      assertEq(_CarolUnrealizedPnlE30, 0, "T3: CAROL unrealized Pnl");
    }

    // T4: Move the price so that both positions are profitable
    //     Have one position go over max profit, one position below max profit
    // Price changed (at same block, no borrowing fee in this case)
    // - ETH 1,600 => 1,634.56
    {
      skip(15);
      tickPrices[0] = 73995; // ETH tick price $1,634.56
      setPrices(tickPrices, publishTimeDiff);
    }

    {
      // Assert before force Take Max Profit
      (int256 _BobUnrealizedPnlE30, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(BOB, 0), 0, 0);
      (int256 _CarolUnrealizedPnlE30, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(CAROL, 0), 0, 0);

      assertEq(_BobUnrealizedPnlE30, 7_200 * 1e30, "T4: Bob unrealized Pnl");
      assertEq(_CarolUnrealizedPnlE30, 1730362327240939953049650331945816, "T4: CAROL unrealized Pnl");

      // Bob Delta = 9016484913540967321995421402572359
      // Bob Unrealized Pnl = 9016484913540967321995421402572359 * 0.8 = 7.2131879308327738576e+33/1e30 = 7213.1879308327738576

      // Carol Delta = 2162952909051174941312062914932271
      // Carol Unrealized Pnl = 2162952909051174941312062914932271 * 0.8 = 1.730362327240939953e+33/1e30 = 1730.362327240939953

      assertApproxEqRel(
        -(9016484913540967321995421402572359 + 2162952909051174941312062914932271),
        calculator.getGlobalPNLE30(),
        MAX_DIFF,
        "T4: Global Pnl before"
      );
    }

    forceTakeMaxProfit(BOB, 0, wethMarketIndex, address(usdc), tickPrices, publishTimeDiff, block.timestamp);

    {
      // Assert after force Take Max Profit
      (int256 _BobUnrealizedPnlE30, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(BOB, 0), 0, 0);
      (int256 _CarolUnrealizedPnlE30, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(CAROL, 0), 0, 0);

      assertEq(_BobUnrealizedPnlE30, 0, "T4: Bob unrealized Pnl");
      assertEq(_CarolUnrealizedPnlE30, 1703132488051454382517233323699814, "T4: CAROL unrealized Pnl");

      // Carol Delta = 2128915610064317978146541654624768
      // Carol Unrealized Pnl = 2128915610064317978146541654624768 * 0.8 = 1.7031324880514543825e+33/1e30 = 1703.1324880514543825

      assertApproxEqRel(
        -(2128915610064317978146541654624768),
        calculator.getGlobalPNLE30(),
        MAX_DIFF,
        "T4: Global Pnl after"
      );
    }
  }
}