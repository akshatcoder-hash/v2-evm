// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Owned } from "../base/Owned.sol";

// Interfaces
import { ICrossMarginHandler } from "./interfaces/ICrossMarginHandler.sol";
import { ICrossMarginService } from "../services/interfaces/ICrossMarginService.sol";
import { IConfigStorage } from "../storages/interfaces/IConfigStorage.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";

contract CrossMarginHandler is Owned, ReentrancyGuard, ICrossMarginHandler {
  using SafeERC20 for ERC20;

  /**
   * EVENTS
   */
  event LogSetCrossMarginService(address indexed oldCrossMarginService, address newCrossMarginService);
  event LogSetPyth(address indexed oldPyth, address newPyth);
  event LogDepositCollateral(
    address indexed primaryAccount,
    uint256 indexed subAccountId,
    address token,
    uint256 amount
  );
  event LogWithdrawCollateral(
    address indexed primaryAccount,
    uint256 indexed subAccountId,
    address token,
    uint256 amount
  );

  /**
   * STATES
   */
  address public crossMarginService;
  address public pyth;

  constructor(address _crossMarginService, address _pyth) {
    crossMarginService = _crossMarginService;
    pyth = _pyth;

    // Sanity check
    ICrossMarginService(_crossMarginService).vaultStorage();
    IPyth(_pyth).getValidTimePeriod();
  }

  /**
   * MODIFIER
   */

  // NOTE: Validate only accepted collateral token to be deposited
  modifier onlyAcceptedToken(address _token) {
    IConfigStorage(ICrossMarginService(crossMarginService).configStorage()).validateAcceptedCollateral(_token);
    _;
  }

  /**
   * SETTER
   */

  /// @notice Set new CrossMarginService contract address.
  /// @param _crossMarginService New CrossMarginService contract address.
  function setCrossMarginService(address _crossMarginService) external onlyOwner {
    if (_crossMarginService == address(0)) revert ICrossMarginHandler_InvalidAddress();
    emit LogSetCrossMarginService(crossMarginService, _crossMarginService);
    crossMarginService = _crossMarginService;

    // Sanity check
    ICrossMarginService(_crossMarginService).vaultStorage();
  }

  /// @notice Set new Pyth contract address.
  /// @param _pyth New Pyth contract address.
  function setPyth(address _pyth) external onlyOwner {
    if (_pyth == address(0)) revert ICrossMarginHandler_InvalidAddress();
    emit LogSetPyth(pyth, _pyth);
    pyth = _pyth;

    // Sanity check
    IPyth(_pyth).getValidTimePeriod();
  }

  /**
   * CALCULATION
   */

  /// @notice Calculate new trader balance after deposit collateral token.
  /// @dev This uses to call deposit function on service and calculate new trader balance when they depositing token as collateral.
  /// @param _account Trader's primary wallet account.
  /// @param _subAccountId Trader's sub account ID.
  /// @param _token Token that's deposited as collateral.
  /// @param _amount Token depositing amount.
  function depositCollateral(
    address _account,
    uint8 _subAccountId,
    address _token,
    uint256 _amount
  ) external nonReentrant onlyAcceptedToken(_token) {
    // Transfer depositing token from trader's wallet to VaultStorage
    ERC20(_token).safeTransferFrom(msg.sender, ICrossMarginService(crossMarginService).vaultStorage(), _amount);

    // Call service to deposit collateral
    ICrossMarginService(crossMarginService).depositCollateral(_account, _subAccountId, _token, _amount);

    emit LogDepositCollateral(_account, _subAccountId, _token, _amount);
  }

  /// @notice Calculate new trader balance after withdraw collateral token.
  /// @dev This uses to call withdraw function on service and calculate new trader balance when they withdrawing token as collateral.
  /// @param _account Trader's primary wallet account.
  /// @param _subAccountId Trader's sub account ID.
  /// @param _token Token that's withdrawn as collateral.
  /// @param _amount Token withdrawing amount.
  /// @param _priceData Price update data
  function withdrawCollateral(
    address _account,
    uint8 _subAccountId,
    address _token,
    uint256 _amount,
    bytes[] memory _priceData
  ) external nonReentrant onlyAcceptedToken(_token) {
    // Call update oracle price
    IPyth(pyth).updatePriceFeeds{ value: IPyth(pyth).getUpdateFee(_priceData) }(_priceData);

    // Call service to withdraw collateral
    ICrossMarginService(crossMarginService).withdrawCollateral(_account, _subAccountId, _token, _amount);

    emit LogWithdrawCollateral(_account, _subAccountId, _token, _amount);
  }
}