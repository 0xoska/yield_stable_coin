// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAzUsd {

    enum Way{TokenMint, TokenRefund, TokenSafeTransfer, TokenStream}

    event UpdateBlacklist(address user, bool state);
    event Refund(address indexed user, uint256 amount);
    event Stream(uint256 thisFlowId);
    event Flow(address sender, address receiver, uint256 amount);
    event Release(address receiver, uint256 amount);

    struct FlowInfo{
        uint64 startTime;
        uint64 lastestWithdrawTime;
        uint64 endTime;
        address sender;
        address receiver;
        uint128 flowAmount; 
        uint128 alreadyWithdrawAmount;
    }


}