// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAzUsdStruct} from "./IAzUsdStruct.sol";
import {IAzUsdError} from "./IAzUsdError.sol";

interface IAzUsd is IAzUsdStruct, IAzUsdError {

    enum Way{TokenMint, TokenRefund}

    event UpdatePause(bool currentState);

    event UpdateRate(uint16 newRate);

    event UpdateValidBytesContract(uint32 destinationDomain,bytes32 contractAddress);

    event UpdateAllowTokens(address[] tokens, bool[] states);

    event UpdateBlacklist(address user, bool state);
    
    event Refund(uint256 indexed thisRefundId, address user, uint256 amount);

    event TouchCCTPV2Cross(address sender, uint256 amount);

    event TouchCCTPV2Receive(uint256 indexed thisRefundId, address receiver);

}