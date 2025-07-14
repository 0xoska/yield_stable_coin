// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAzUsdError {
     error BalanceZero();
     error InValidTargetBytes32Contract(bytes32);
     error AlreadyRefund(string);
     error InvalidCollateralDecimals();
     error InsufficientBalance(uint256); 
}