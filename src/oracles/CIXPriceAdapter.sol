// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ICIXPriceAdapter } from "@hmx/oracles/interfaces/ICIXPriceAdapter.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ABDKMath64x64 } from "@hmx/libraries/ABDKMath64x64.sol";
import { IEcoPythCalldataBuilder3 } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder3.sol";

/// @dev Customized Index Pyth Adapter - Index price will be calculated using geometric mean according to weight config
contract CIXPriceAdapter is OwnableUpgradeable, ICIXPriceAdapter {
  using ABDKMath64x64 for int128;

  // constant
  int128 private immutable _E8_PRECISION_64X64 = ABDKMath64x64.fromUInt(1e8);

  // errors
  error CIXPriceAdapter_BrokenPythPrice();
  error CIXPriceAdapter_UnknownAssetId();
  error CIXPriceAdapter_BadParams();
  error CIXPriceAdapter_BadWeightSum();

  // state variables
  ICIXPriceAdapter.CIXConfig public config;

  // events
  event LogSetConfig(uint256 _cE8, bytes32[] _pythPriceIds, uint256[] _weightsE8, bool[] _usdQuoteds);
  event LogSetPyth(address _oldPyth, address _newPyth);

  function initialize() external initializer {
    OwnableUpgradeable.__Ownable_init();
  }

  function _accumulateWeightedPrice(
    int128 _accum,
    uint256 _priceE8,
    uint256 _weightE8,
    bool _usdQuoted
  ) private view returns (int128) {
    int128 _price = _convertE8To64x64(_priceE8);
    int128 _weight = _convertE8To64x64(_weightE8);
    if (_usdQuoted) _weight = _weight.neg();

    return _accum.mul(_price.pow(_weight));
  }

  function _convertE8To64x64(uint256 _n) private view returns (int128 _output) {
    _output = ABDKMath64x64.fromUInt(_n).div(_E8_PRECISION_64X64);
    return _output;
  }

  function _convert64x64ToE8(int128 _n) private view returns (uint128 _output) {
    _output = _n.mul(_E8_PRECISION_64X64).toUInt();
    return _output;
  }

  /**
   * Getter
   */

  /// Calculate geometric average price according to the formula
  /// price = c * (price1 ^ +-weight1) * (price2 ^ +-weight2) * ... * (priceN ^ +-weightN)
  function getPrice(
    IEcoPythCalldataBuilder3.BuildData[] calldata _buildDatas
  ) external view returns (uint256 _priceE18) {
    // 1. Declare _accum as c
    int128 _accum = _convertE8To64x64(config.cE8);

    // 2. Loop through config.
    //    Reduce the parameter with geometric average calculation.
    uint256 _len = config.assetIds.length;
    for (uint256 i = 0; i < _len; ) {
      // Get price from Pyth
      uint256 _priceE8 = _getPriceE8ByAssetId(config.assetIds[i], _buildDatas);

      // Accumulate the _accum with (priceN ^ +-weightN)
      _accum = _accumulateWeightedPrice(_accum, _priceE8, config.weightsE8[i], config.usdQuoteds[i]);

      unchecked {
        ++i;
      }
    }

    // 3. Convert the final result to uint256 in e18 basis
    _priceE18 = _convert64x64ToE8(_accum) * 1e10;
  }

  function _getPriceE8ByAssetId(
    bytes32 _assetId,
    IEcoPythCalldataBuilder3.BuildData[] memory _buildDatas
  ) private pure returns (uint256 priceE8) {
    uint256 _len = _buildDatas.length;
    for (uint256 i = 0; i < _len; ) {
      if (_assetId == _buildDatas[i].assetId) return uint256(int256(_buildDatas[i].priceE8));

      unchecked {
        ++i;
      }
    }
  }

  /**
   * Setter
   */
  /// @notice Set the Pyth price id for the given asset.
  /// @param _cE8 A magic constant. Need to be recalculate every time the weight is changed.
  /// @param _assetIds An array asset id defined by HMX. This array index is relative to weightsE8.
  /// @param _weightsE8 An array of weights of certain asset in e8 basis. This should be relative to _pythPriceIds.
  function setConfig(
    uint256 _cE8,
    bytes32[] memory _assetIds,
    uint256[] memory _weightsE8,
    bool[] memory _usdQuoteds
  ) external onlyOwner {
    // 1. Validate params

    uint256 _len = _assetIds.length;
    // Validate length
    {
      if (_len != _weightsE8.length || _len != _usdQuoteds.length) revert CIXPriceAdapter_BadParams();
      if (_cE8 == 0) revert CIXPriceAdapter_BadParams();
    }

    // Validate weight and price id
    {
      uint256 _weightSum;
      for (uint256 i = 0; i < _len; ) {
        // Accum weight sum
        _weightSum += _weightsE8[i];

        unchecked {
          ++i;
        }
      }

      if (_weightSum != 1e8) revert CIXPriceAdapter_BadWeightSum();
    }

    // 2. Assign config to storage
    config.cE8 = _cE8;
    config.assetIds = _assetIds;
    config.weightsE8 = _weightsE8;
    config.usdQuoteds = _usdQuoteds;

    emit LogSetConfig(_cE8, _assetIds, _weightsE8, _usdQuoteds);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}
