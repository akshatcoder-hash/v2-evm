// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { PythAdapter_BaseTest } from "./PythAdapter_BaseTest.t.sol";
import { PythAdapter } from "../../src/oracle/PythAdapter.sol";
import { AddressUtils } from "../../src/libraries/AddressUtils.sol";

contract PythAdapter_SetterTest is PythAdapter_BaseTest {
  using AddressUtils for address;

  function setUp() public override {
    super.setUp();

    vm.deal(ALICE, 1 ether);
    vm.deal(BOB, 1 ether);
  }

  function testCorrectness_AccessControlWhenSetPythPriceId() external {
    // Revert if not owner
    vm.expectRevert(abi.encodeWithSignature("Owned_NotOwner()"));
    vm.startPrank(address(ALICE));
    pythAdapter.setPythPriceId(address(weth).toBytes32(), wethPriceId);
    vm.stopPrank();

    // Should be fine when executed by owner
    vm.startPrank(address(this));
    pythAdapter.setPythPriceId(address(weth).toBytes32(), wethPriceId);
    vm.stopPrank();
  }
}