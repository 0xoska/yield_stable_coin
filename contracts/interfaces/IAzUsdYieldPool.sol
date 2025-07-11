// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAzUsdStruct} from "./IAzUsdStruct.sol";
import {IAzUsdError} from "./IAzUsdError.sol";

interface IAzUsdYieldPool is IAzUsdStruct, IAzUsdError {

    event UpdatePause(bool currentState);

    event ReceiveRefundInfo(uint128 indexed thisRefundId, uint256 refundAmount);

    event Emergency(uint128 indexed thisRefundId, uint256 refundAmount, uint256 balance);

}