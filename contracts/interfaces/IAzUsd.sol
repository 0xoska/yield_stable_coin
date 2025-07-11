// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAzUsdStruct} from "./IAzUsdStruct.sol";
import {IAzUsdError} from "./IAzUsdError.sol";

interface IAzUsd is IAzUsdStruct, IAzUsdError {

    enum Way{TokenMint, TokenRefund}

    event UpdatePause(bool currentState);

    event UpdateAllowToken(address token, bool state);

    event UpdateBlacklist(address user, bool state);
    
    event Refund(uint256 indexed thisRefundId, address user, uint256 amount);

}