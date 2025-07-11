// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

library Decoder {
    struct MessageHeader{
       uint32 version;
       uint32 sourceDomain;
       uint32 destinationDomain;
       bytes32 nonce;
       bytes32 sender;
       bytes32 recipient;
       bytes32 destinationCaller;
       uint32 minFinalityThreshold;
       uint32 finalityThresholdExecuted;
       bytes messageBody;
    }

    struct MessageBody{
        uint32 version;
        bytes32 burnToken;
        bytes32 mintRecipient;
        uint256 amount;
        bytes32 messageSender;
        uint256 maxFee;
        uint256 feeExecuted;
        uint256 expirationBlock;
        bytes hookData;
    }

    function decodeMessage(bytes calldata message) internal pure returns (MessageHeader memory) {
        return MessageHeader({
            version: uint32(bytes4(message[0:4])),
            sourceDomain: uint32(bytes4(message[4:8])),
            destinationDomain: uint32(bytes4(message[8:12])),
            nonce: bytes32(message[12:44]),
            sender: bytes32(message[44:76]),
            recipient: bytes32(message[76:108]),
            destinationCaller: bytes32(message[108:140]),
            minFinalityThreshold: uint32(bytes4(message[140:144])),
            finalityThresholdExecuted: uint32(bytes4(message[144:148])),
            messageBody: message[148:]
        });
    }

    function decodeMessageBody(bytes calldata messageBody) internal pure returns (MessageBody memory) {
        return MessageBody({
            version: uint32(bytes4(messageBody[0:4])),
            burnToken: bytes32(messageBody[4:36]),
            mintRecipient: bytes32(messageBody[36:68]),
            amount: uint256(bytes32(messageBody[68: 100])),
            messageSender: bytes32(messageBody[100:132]),
            maxFee: uint256(bytes32(messageBody[132: 164])),
            feeExecuted: uint256(bytes32(messageBody[164: 196])),
            expirationBlock: uint256(bytes32(messageBody[196: 228])),
            hookData: messageBody[228:]
        });
    }

    function getMessageVersion(bytes calldata message) internal pure returns (uint32 messageVersion) {
        messageVersion = uint32(bytes4(message[0:4]));
    }

    function getMessageBodyVersion(bytes calldata message) internal pure returns (uint32 messageBodyVersion) {
        messageBodyVersion = uint32(bytes4(message[148:152]));
    }

    function decodeMessageToHookdata(bytes calldata message) internal pure returns (bytes memory hookdata) {
        hookdata = message[376:];
    }
}