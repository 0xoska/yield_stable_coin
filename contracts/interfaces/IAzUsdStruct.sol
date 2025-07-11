// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAzUsdStruct {

    struct CrossParams{
        uint32 destinationDomain;  //Target CCTPV2 Domain
        uint32 minFinalityThreshold; //minimum completion time
        address burnToken; //Destroy token (USDC)
        bytes32 mintRecipient; //The address of the bytes32 type minted USDC receiver
        bytes32 destinationCaller;  //The target caller of type bytes32
        uint256 amount;  //USDC amount
        uint256 maxFee;  //The fee paid to CCTP
        bytes hookData;  //Cross-chain data transmission
    }

    struct RefundInfo {
        uint8 isRefunded;  // 0 == No refund, !0 == refunded
        uint32 refundTime; //Refund initiation time
        uint64 amount;  //USDC amount
        address receiver; //The address of the bytes32 type minted USDC receiver
    }


}